//
//  DBDataLogger.m
//  DisplayAcc
//
//  Created by DB on 1/8/15.
//  Copyright (c) 2015 D Blalock. All rights reserved.
//

// TODO make logging work right
	//logging bizarre timestamps at the end
// TODO figure out why the gyro data is sometimes logged as nan...

#import "DBDataLogger.h"

#import "FileUtils.h"
#import "TimeUtils.h"
#import "MiscUtils.h"
#import "DropboxUploader.h"

#define LOG_DIFFERENTIAL_TIMESTAMPS

static NSUInteger const kTimeStampIndex = 0;
static NSString *const kKeyTimeStamp = @"timestamp";
static NSString *const kKeyNumSkipped = @"numSkipped";
static NSString *const kDefaultLogName = @"log";
static NSString *const kDefaultLogSubdir = @"";
static NSString *const kLogNameAndDateSeparator = @"__";
static NSString *const kCsvSeparator = @",";	//no space -> slightly smaller
static NSString *const kLogFileExt = @".csv";
static NSString *const kNanStr = @"nan";
static NSString *const kNoChangeStr = @"";
//static const uint kFloatDecimalPlaces = 3;
static NSString *const kFloatFormat = @"%.3f";	// log only 3 decimal places
static NSString *const kIntFormat = @"%d";
static const timestamp_t kDefaultGapThresholdMs = 2*1000;	//2s
static const timestamp_t kDefaultTimeStamp = -1;
static const NSUInteger kMaxLinesInLog = 10000;	// ~4MB

@interface DBDataLogger ()

//TODO I think we only really need currentSample and indexes
@property(strong, nonatomic) NSArray* allSignalNames;
//@property(strong, nonatomic) NSSet* allSignalNames;
//@property(strong, nonatomic) NSDictionary* defaultSample;
//@property(strong, nonatomic) NSMutableDictionary* currentSample;
@property(strong, nonatomic) NSArray* defaultValues;
@property(strong, nonatomic) NSDictionary* signalIdxs;
@property(strong, nonatomic) NSMutableArray* currentSampleValues;

@property(strong, atomic) NSMutableArray* data;
@property(strong, atomic) NSMutableArray* prevWrittenVals;

@property(nonatomic) NSUInteger samplingPeriodMs;
@property(nonatomic) timestamp_t lastFlushTimeMs;
@property(nonatomic) timestamp_t latestTimeStamp;
@property(nonatomic) timestamp_t prevLastSampleTimeWritten;

@property(strong, nonatomic) NSString* logPath;
@property(strong, nonatomic) NSOutputStream* stream;

@property(nonatomic) BOOL isLogging;
@property(nonatomic) BOOL shouldAppendToLog;

@property(nonatomic) NSUInteger linesInLog;
@property(nonatomic) NSUInteger samplesSinceWriting;
@property(nonatomic) timestamp_t lastSampleWrittenTime;
// dropbox client
//@property (strong, nonatomic) DBRestClient *restClient;

@end


@implementation DBDataLogger

//--------------------------------------------------------------
#pragma mark Utility funcs
//--------------------------------------------------------------

timestamp_t getTimeStampForSample(NSDictionary* sample) {
	timestamp_t time = [[sample valueForKey:kKeyTimeStamp] longLongValue];
	if (time <= 0) {
		NSLog(@"timestamp for sample = %lld, something done bad", time);
	}
	return time;
}

void setTimeStampForSample(NSDictionary* sample, timestamp_t time) {
	[sample setValue:@(time) forKey:kKeyTimeStamp];
	if (time <= 0) {
		NSLog(@"set timestamp %lld for sample, which is probaly bad", time);
	}
}

timestamp_t getTimeStampForSampleValues(NSArray* values) {
	timestamp_t time = [values[kTimeStampIndex] longLongValue];;
	if (time <= 0) {
		NSLog(@"timestamp for sample = %lld, something done bad", time);
	}
	return time;
}

void setTimeStampForSampleValues(NSMutableArray* values, timestamp_t time) {
	values[kTimeStampIndex] = @(time);
	if (time <= 0) {
		NSLog(@"set timestamp %lld for sample, which is probaly bad", time);
	}
}

NSArray* sortedByTimeStamp(NSArray* data) {
	if (! data) return nil;
	NSSortDescriptor* sortBy = [NSSortDescriptor sortDescriptorWithKey:kKeyTimeStamp ascending:YES];
	NSArray* wrapSortBy = [NSArray arrayWithObjects:sortBy, nil];
	return [data sortedArrayUsingDescriptors:wrapSortBy];
}


- (NSUInteger) indexForSignalName:(id)name {
	return [[_signalIdxs valueForKey:name] unsignedIntegerValue];
}

- (BOOL) signalNameRecognized:(id)name {
	return [_allSignalNames containsObject:name];
}

- (NSMutableArray*) updateSampleValues:(NSMutableArray*)vals withSample:(NSDictionary*)sample {
	for (id signalName in [sample allKeys]) {
		if (! [self signalNameRecognized:signalName]) continue;	//only listen to predefined set
		
		NSUInteger idx = [self indexForSignalName:signalName];
		id value = [sample valueForKey:signalName];
		[vals replaceObjectAtIndex:idx withObject:value];
	}
	return vals;
}

- (NSArray*) orderedSampleValuesWithDefaults:(NSDictionary*)sample {
	return [self updateSampleValues:[_defaultValues mutableCopy] withSample:sample];
}

//--------------------------------------------------------------
#pragma mark init()
//--------------------------------------------------------------

-(id) initWithSignalNames:(NSArray*)names
			defaultValues:(NSArray*)defaults
			   samplePeriod:(NSUInteger)ms {
	if (self = [super init]) {

		// add a "signal" for the time stamp at position 0
		NSMutableArray* defaultsWithTimeStamp = [defaults mutableCopy];
		[defaultsWithTimeStamp insertObject:@(kDefaultTimeStamp) atIndex:kTimeStampIndex];
		_defaultValues = defaultsWithTimeStamp;
		
		NSMutableArray* sigNames = [names mutableCopy];
		[sigNames insertObject:kKeyTimeStamp atIndex:kTimeStampIndex];
		_allSignalNames = sigNames;
		
		// store indices of each signal so dimensions have consistent meaning
		NSMutableDictionary* idxs = [NSMutableDictionary dictionary];
		for (int i = 0; i < [_allSignalNames count]; i++) {
//			NSLog(@"%@ (%@)-> %@ (%@); idx=%@", _allSignalNames[i],
//				  [_allSignalNames[i] class],
//				  _defaultValues[i],
//				  [_defaultValues[i] class],
//				  @(i));
			[idxs setValue:@(i) forKey:_allSignalNames[i]];
		}
		_signalIdxs = idxs;
		
		// initialize data stuff
		_currentSampleValues = [_defaultValues mutableCopy];
		_data = [NSMutableArray array];
		_prevWrittenVals = [NSMutableArray array];
		
		// file stuff
		_logName = kDefaultLogName;
		_logSubdir = kDefaultLogSubdir;
		
		_lastSampleWrittenTime = 0;	// yields absolute timestamp for 1st row
		_linesInLog = 0;
		
		// time stuff
		_samplingPeriodMs = ms;
		_autoFlushLagMs = maxTimeStampMs();
		_gapThresholdMs = kDefaultGapThresholdMs;
		_lastFlushTimeMs = currentTimeStampMs();
		_prevLastSampleTimeWritten = minTimeStampMs();
		
		// flags
		_isLogging = NO;
		_shouldAppendToLog = NO;
	}
	return self;
}

//--------------------------------------------------------------
#pragma mark logData()
//--------------------------------------------------------------

-(void) logData:(NSDictionary*)kvPairs withTimeStamp:(timestamp_t)ms {
//	NSLog(@"logData: t=%lld at time=%lld, logging %@", ms, currentTimeStampMs(), kvPairs);
	if (! _isLogging) return;
	if (! [kvPairs count]) return;
	
	if (ms <= 0) {
		ms = currentTimeStampMs();
	} else if (ms <= _lastFlushTimeMs) { //we'll just ignore it later anyway
		return;
	}
	
	NSMutableDictionary* sample = [kvPairs mutableCopy];
	setTimeStampForSample(sample, ms);
	[_data addObject:sample];
//	NSLog(@"added obj to data: %@", sample);
	
	_latestTimeStamp = MAX(_latestTimeStamp, ms);
	if (_latestTimeStamp - _lastFlushTimeMs > _autoFlushLagMs) {
		[self flush];
	}
}

-(void) logData:(NSDictionary*)kvPairs {
	[self logData:kvPairs withTimeStamp:-1];
}

-(void) logDataBuff:(NSArray*)sampleDicts
  withSampleSpacing:(NSUInteger)periodMs
	 finalTimeStamp:(timestamp_t)ms {
	
	if (ms <= 0) {
		ms = currentTimeStampMs();
	} else if (ms <= _lastFlushTimeMs) { //we'll just ignore it later anyway
		return;
	}
	
	long numSamples = [sampleDicts count];
	long finalIdx = numSamples - 1;
	for (long i = 0; i < numSamples; i++) {
		long stepsFromEnd = finalIdx - i;
		long timeFromEnd = stepsFromEnd * periodMs;
		timestamp_t t = ms - timeFromEnd;
		
		[self logData:sampleDicts[i] withTimeStamp:t];
	}
}

-(void) logDataBuff:(NSArray*)sampleDicts
		withSampleSpacing:(NSUInteger)periodMs {
	[self logDataBuff:sampleDicts withSampleSpacing:periodMs finalTimeStamp:-1];
}

// assumes that for keys {k1,k2,k3}, the array is the values
// k1(0),k2(0),k3(0),k1(1),k2(1),k3(1),...,k3(len/ numKeys);
//
// basically, this is for logging x,y,z accelerometer data all
// crammed into one array
NSArray* rawArrayToSampleBuff(id* array, int len, NSArray* keys) {
	NSMutableArray* buff = [NSMutableArray array];
	long numKeys = [keys count];
	for (int i = 0; i < len; i+= numKeys) {
		NSDictionary* sample = [NSDictionary dictionary];
		for (id key in keys) {
			[sample setValue:array[i++] forKey:key];
		}
		[buff addObject:sample];
	}
	return buff;
}

//--------------------------------------------------------------
#pragma mark writeSampleValues()
//--------------------------------------------------------------

id valToWriteForVal(id val) {
	id valToWrite = val;
	if (val && isFloatingPointNumber(val)) {
		double dbl = [val doubleValue];
		if (isnan(dbl)) {
			valToWrite = kNanStr;
		} else {
			valToWrite = [NSString stringWithFormat:kFloatFormat, dbl];
		}
	}
	return valToWrite;
}

//BOOL valuesEqualIgnoringTimestamp(NSArray* ar1, NSArray* ar2) {
//	if ([ar1 count] != [ar2 count]) return NO;
//	if (![ar1 count]) return NO;
//	for (int i = 0; i < kTimeStampIndex; i++) {
//		if (! [ar1[i] isEqual: ar2[i]]) return NO;
//	}
//	for (int i = kTimeStampIndex+1; i < [ar1 count]; i++) {
//		if (! [ar1[i] isEqual: ar2[i]]) return NO;
//	}
//	return YES;
//}
//
//BOOL allValuesIgnoringTimestampEqualX(NSArray* ar, id x) {
//	if ([ar1 count] != [ar2 count]) return NO;
//	if (![ar count]) return NO;
//	for (int i = 0; i < kTimeStampIndex; i++) {
//		if (! [ar1[i] isEqual: x]) return NO;
//	}
//	for (int i = kTimeStampIndex+1; i < [ar1 count]; i++) {
//		if (! [ar1[i] isEqual: x]) return NO;
//	}
//	return YES;
//}

void writeLineToStream(NSString* line, NSOutputStream* stream) {
	NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
	[stream write:data.bytes maxLength:data.length];
}

void writeArrayToStream(NSArray* ar, NSOutputStream* stream) {
	NSString* line = [[ar componentsJoinedByString:kCsvSeparator] stringByAppendingString:@"\n"];
	writeLineToStream(line, stream);
}

-(void) writeSampleValues:(NSArray*)values toStream:(NSOutputStream*)stream forceWrite:(BOOL)force {
	if ([values count] < kTimeStampIndex) return;
	NSMutableArray* fmtVals = [NSMutableArray arrayWithCapacity:[values count]];
	
	NSString* prevLine = [_prevWrittenVals componentsJoinedByString:kCsvSeparator];
//	NSLog(@"prev line:\n%@", prevLine);
	int numChangedVals = 0;
	
	// first time writing values
	if (! [_prevWrittenVals count]) {
		for (id val in values) {
			[fmtVals addObject:valToWriteForVal(val)];
		}
		_prevWrittenVals = [fmtVals mutableCopy];
		
		numChangedVals = [_prevWrittenVals count];
		
	// not first time writing, so only write differences from last time
	} else {

//#ifdef LOG_DIFFERENTIAL_TIMESTAMPS
//		// record previous timestamp before overwriting it
//		timestamp_t t0 = [[_prevWrittenVals objectAtIndex:kTimeStampIndex] longLongValue];
//#endif
		for (long i = 0; i < [values count]; i++) {
			id val = [values objectAtIndex:i];
			id prevVal = [_prevWrittenVals objectAtIndex:i];
			
			// write it differently based on what type of data it is
			id valToWrite = valToWriteForVal(val);
			
			// only write differences
			if ([valToWrite isEqual: prevVal]) {
				valToWrite = kNoChangeStr;
			} else {
				numChangedVals++;
				_prevWrittenVals[i] = valToWrite;
			}
			
			[fmtVals addObject:valToWrite];
		}
//#ifdef LOG_DIFFERENTIAL_TIMESTAMPS
//		// this throws an NSRangeException if values is nil, though I now
//		// catch that at the start of the function
//		timestamp_t t1 = [[fmtVals objectAtIndex:kTimeStampIndex] longLongValue];
//		[fmtVals setObject:@(t1 - t0) atIndexedSubscript:kTimeStampIndex];
//#endif
	}
	
	// if values this time are the same as the values last time, don't write
	// anything; the timestamp will always change, so check if more than one
	// thing changed
	if (numChangedVals <= 1 && !force) {
		_samplesSinceWriting++;
		NSLog(@"writeSampleValues: not writing output for the %dth time", _samplesSinceWriting);
		return;
	}
	
	timestamp_t t = getTimeStampForSampleValues(values);
#ifdef LOG_DIFFERENTIAL_TIMESTAMPS
	setTimeStampForSampleValues(fmtVals, t - _lastSampleWrittenTime);
#endif

	// create line as string
	NSString* sinceUpdateStr = [NSString stringWithFormat:@"%lu%@",
								(unsigned long) _samplesSinceWriting, kCsvSeparator];
	NSString* valuesStr = [fmtVals componentsJoinedByString:kCsvSeparator];
	NSString* line = [NSString stringWithFormat:@"%@%@\n", sinceUpdateStr, valuesStr];
	
	// debug output
	if (force) {
		NSLog(@"being forced to write sample");
	}
	NSString* dataLine = [values componentsJoinedByString:kCsvSeparator];
	NSLog(@"writing prev line, sample, line:\n%@\n%@\n%@\n", prevLine, dataLine, line);

	writeLineToStream(line, stream);

	// update state
	_lastSampleWrittenTime = t;
	_samplesSinceWriting = 0;
	_linesInLog++;
}

-(void) writeSampleValues:(NSArray*)values toStream:(NSOutputStream*)stream {
	[self writeSampleValues:values toStream:stream forceWrite:NO];
}

//--------------------------------------------------------------
#pragma mark writeData()
//--------------------------------------------------------------

-(void) resetCurrentSampleValues {	//TODO uncomment this
	NSLog(@"resetting current sample values");
	timestamp_t t = getTimeStampForSampleValues(_currentSampleValues);
	_currentSampleValues = [_defaultValues mutableCopy];
	setTimeStampForSampleValues(_currentSampleValues, t);
}

//-(void) resetCurrentSampleValuesIfGapFromT:(timestamp_t)t toTprev:(timestamp_t)tprev {
//	if (t - tprev > _gapThresholdMs) {
//		[self resetCurrentSampleValues];
//	}
//}

// assumes that samples are sorted by increasing timestamp
-(void)writeData:(NSArray*)samples {
	if (! [samples count]) return;

	NSMutableArray* prevSampleValues;// = _currentSampleValues;
	timestamp_t tprev;
	timestamp_t t = _prevLastSampleTimeWritten;
	timestamp_t sampleBoundary = t + _samplingPeriodMs;
	
//	timestamp_t t = getTimeStampForSample(samples[0]);
//	timestamp_t tprev = _prevLastSampleTimeWritten;
//	timestamp_t sampleBoundary = t + _samplingPeriodMs;
//	[self resetCurrentSampleValuesIfGapFromT:t toTprev:tprev];
	
	// ensure that default values don't get written on 1st iteration
	// of the loop the first time this log writes data
//	[self updateSampleValues:_currentSampleValues withSample:samples[0]];

	NSDictionary* sample;
	for (int i = 0; i < [samples count]; i++) {
		sample = samples[i];
		
		// Everything within, eg, 20ms, gets combined
		// into one sample, since data sources write asynchronously; we
		// identify when to write by when the current sample's time is
		// past the end of the combining boundary
		//
		// Also note that if there's nothing to update, we'll just
		// write the same data repeatedly so that we stil log at our
		// master sampling rate
		//
		// However, if there's a huge gap (more than k seconds), write
		// the old sample values (to make they're written at least once),
		// then write the default values as a "hey, there's a pause here"
		// flag and continue on; interpolating here would be misleading
		
		// update current and previous samples
		tprev = t;
		t = getTimeStampForSample(sample);
		prevSampleValues = [_currentSampleValues mutableCopy];
		
		// there was a gap, so write out the previous values exactly once
		if (t - tprev > _gapThresholdMs) {
			// write old values
			[self writeSampleValues:prevSampleValues toStream:_stream];
			
			// write the default values right afterward
			// EDIT: actually, don't...this info will be conveyed by
			// the reset of the current values
//			NSArray* resetVals = _defaultValues;
//			timestamp_t tReset = [prevSampleValues[kTimeStampIndex] longLongValue] + _samplingPeriodMs;
//			vals[kTimeStampIndex] = @(tReset);
//			[self writeSampleValues:resetVals toStream:_stream];
			
			sampleBoundary = t + _samplingPeriodMs;
			[self resetCurrentSampleValues];
			[self updateSampleValues:_currentSampleValues withSample:sample];

		// there was no gap, so write out the old values until we get to
		// the current time
		} else {
			[self updateSampleValues:_currentSampleValues withSample:sample];
			// write out finished samples, reproducing them forward in time
			// until we hit another sample; not actually sure if the 2nd
			// check here is necessary, but certainly it should hold;
			// third condition is definitely necessary for first point logged
			while (t > sampleBoundary && tprev < t && tprev > 0) {
				[self writeSampleValues:prevSampleValues toStream:_stream];
				sampleBoundary += _samplingPeriodMs;
				
				// increment timestamp of "interpolated" sample
				tprev += _samplingPeriodMs;
				prevSampleValues[kTimeStampIndex] = @(tprev);
			}
		}
		
//		[self resetCurrentSampleValuesIfGapFromT:t toTprev:tprev];
//		prevSampleValues = [_currentSampleValues mutableCopy];
//		[self updateSampleValues:_currentSampleValues withSample:sample];

		

	}
	// deal with last sample not getting written; a slightly more
	// accurate way would be to wait to write this until the next
	// time data is written and combine it with appropriate samples
	// there, but that makes things way more complicated
	//
	// also, we force it to write the last sample even if it's the same as
	// the previous one just so that everything is nice and up-to-date at
	// this point (and also so that everything gets written if the log is
	// about to be closed, which *will* be the case sometimes)
	//
	// in the case of only one sample, nothing got written anywhere in the
	// above (and prevSampleValues never got set)
//	if ([samples count] == 1) {
	
//	} else {
		// will probably result in this getting written twice
//		NSLog(@"writeData: forcing it to write output");
//		[self writeSampleValues:_currentSampleValues toStream:_stream forceWrite:YES];
//	}
	
	// only write
//	[self writeSampleValues:_currentSampleValues toStream:_stream forceWrite:YES];
	
	_prevLastSampleTimeWritten = t;

	// start a new log file once this one is too long
	if (_linesInLog >= kMaxLinesInLog) {
		[self endLog];
		[self startLog];
	}
}

//--------------------------------------------------------------
#pragma mark flush()
//--------------------------------------------------------------

-(void) flushUpToTimeStamp:(timestamp_t)ms {
	@synchronized(self) {
		if (! [_data count]) return;

		NSArray* sorted = sortedByTimeStamp(_data);
		NSInteger numSamples = [sorted count];
		timestamp_t minTime = _lastFlushTimeMs;
		_lastFlushTimeMs = currentTimeStampMs();
		
		// find the start of samples that are after the last flush;
		// at end of loop, start is the first idx in the array that's
		// after minTime; ; ie, start = 1st index in flush samples
		unsigned int start, stop;
		
		for (start = 0; start < numSamples; start++) {
			timestamp_t sampleTime = getTimeStampForSample(sorted[start]);
			if (sampleTime < minTime) {
				start++;
			} else {
				break;
			}
		}
		// find the end of samples that are before the given timestamp;
		// at end of loop, stop is one past the last index in the array
		// that's before ms; ie, stop = 1st index in post-flush samples
		for (stop = start; stop < numSamples; stop++) {
			timestamp_t sampleTime = getTimeStampForSample(sorted[stop]);
			if (sampleTime > ms) {
				break;
			}
		}
		
		// flush range (or earlier) includes everything
		if (stop == numSamples) {
			_data = [NSMutableArray array];
			// some data after flush range
		} else {
			NSRange keepRange;
			keepRange.location = stop;
			keepRange.length = numSamples - stop;
			_data = [[sorted subarrayWithRange:keepRange] mutableCopy];
		}
		
		// nothing in flush range
		if (stop == start) return;
		
		NSRange flushRange;
		flushRange.location = start;
		flushRange.length = stop - start;
		NSArray* samplesToFlush = [sorted subarrayWithRange:flushRange];
		[self writeData:samplesToFlush];
	}	//synchronized
}

-(void) flush {
	[self flushUpToTimeStamp:maxTimeStampMs()];

	// force it to write most recent data, not keep buffering changes
	[self writeSampleValues:_currentSampleValues toStream:_stream forceWrite:YES];
}

//--------------------------------------------------------------
#pragma mark Logging paths
//--------------------------------------------------------------

-(void) setLogName:(NSString *)logName {
	@synchronized(self) {
		if (logName == _logName) return;
		if (_isLogging) {
			[self endLog];
			_logName = logName;
			[self startLog];
		} else {
			_logName = logName;
		}
	}
}

-(void) setLogSubdir:(NSString *)logSubdir {
	@synchronized(self) {
		if (logSubdir == _logSubdir) return;
		if (_isLogging) {
			[self endLog];
			_logSubdir = logSubdir;
			[self startLog];
		} else {
			_logSubdir = logSubdir;
		}
	}
}

-(NSString*) generateLogFilePath {
	NSString* logPath;
	logPath = [FileUtils getFullFileName:_logSubdir];
	[FileUtils ensureDirExists:logPath];
	logPath = [logPath stringByAppendingPathComponent:_logName];
	logPath = [logPath stringByAppendingString:kLogNameAndDateSeparator];
	logPath = [logPath stringByAppendingString:currentTimeStrForFileName()];
//	NSLog(@"logPath = %@", logPath);
	return [logPath stringByAppendingString:kLogFileExt];
}

//--------------------------------------------------------------
#pragma mark Logging state
//--------------------------------------------------------------

-(void) startLog {
	@synchronized(self) {
		if (_isLogging) return;
		_isLogging = YES;
		
		_logPath = [self generateLogFilePath];
		_stream = [[NSOutputStream alloc] initToFileAtPath:_logPath append:_shouldAppendToLog];
		[_stream open];
		
		// write signal names as first line
		NSMutableArray* titles = [NSMutableArray arrayWithArray:_allSignalNames];
		[titles insertObject:kKeyNumSkipped atIndex:0];
		writeArrayToStream(titles, _stream);
		_lastSampleWrittenTime = 0;
//		[self writeSampleValues:_allSignalNames toStream:_stream];
		
		_lastFlushTimeMs = currentTimeStampMs();
		_latestTimeStamp = minTimeStampMs();
	}
}
-(void) pauseLog {
	@synchronized(self) {
		_isLogging = NO;
		_shouldAppendToLog = YES;
		[self flush];
		[_stream close];
	}
}
-(void) endLog {
	@synchronized(self) {
		[self pauseLog];
		_shouldAppendToLog = NO;
		
		_linesInLog = 0;
		_samplesSinceWriting = 0;
		
		NSString* dbPath = [_logSubdir stringByAppendingPathComponent:[_logPath lastPathComponent]];
		[[DropboxUploader sharedUploader] addFileToUpload:_logPath toPath:dbPath];
		[[DropboxUploader sharedUploader] tryUploadingFiles];	//will auto-try later anyway
	}
}
-(void) deleteLog {
	[self endLog];
	[FileUtils deleteFile:[self generateLogFilePath]];
}

@end
