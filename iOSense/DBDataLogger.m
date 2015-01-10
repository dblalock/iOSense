//
//  DBDataLogger.m
//  DisplayAcc
//
//  Created by DB on 1/8/15.
//  Copyright (c) 2015 D Blalock. All rights reserved.
//

#import "DBDataLogger.h"

#import "FileUtils.h"
#import "TimeUtils.h"

//SELF: here's how we're gonna deal with logging stuff at heterogeneous
//(and possibly variable) sampling rates:
//	-everything pumps whatever data it's getting into a shared queue
//		-has to have a timestamp--defaults to wall time
//		-technically, just write data via performSelectorOnMainThread so
//		that we don't actually have to deal with a message queue
//	-when it's time to flush stuff (every ~2s):
//		1) put stuff into a list ordered by timestamp
//			-prolly only flush up to ~2s ago, not present, by default
//			-if something from last flush (too early) is there, throw it away
//		2) consume crap in fixed time chunks based on a global sampling rate
//			-eg, eat up all the data in a 5ms chunk of timestamps for 20Hz
//			-fill in data not specified with value from previous sample
//			-prolly just use latest value if >1 specified, but ideally average
//	-have to initially set named signals it's logging so csv, etc, can have
//	consistent dims and so we know what to auto-fill
//		-also have to initially set default values for very 1st sample
//			-actually, no, nil works for everything
//
//	-maybe have option to specify sampling rates for each signal
//		-if it knows this, can put in time stamps automatically
//	-make sure that current state of signals persists across flushes so we
//	don't end up with a bunch of zeros or whatever once the user hits
//	"stop recording" (gps, etc, may only get 1 update during app lifetime)
//
//	-possibly better plan: just do the 1st part (dumping stuff) and write
//	a python script that does parts 2 and 3 (the ordering/combining)

static NSString *const kKeyTimeStamp = @"timestamp";
static NSString *const kDefaultLogName = @"log";
static NSString *const kLogNameAndDateSeparator = @"__";
static NSString *const kCsvSeparator = @",";	//no space -> slightly smaller
static NSString *const kLogFileExt = @".csv";
static NSString *const kFloatFormat = @"%.3f";	// log only decimal places (bad for lat/lon...)
static const timestamp_t kDefaultGapThresholdMs = 2*1000;	//2s
static const timestamp_t kDefaultTimeStamp = -1;

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

@property(nonatomic) NSUInteger samplingPeriodMs;
@property(nonatomic) timestamp_t lastFlushTimeMs;
@property(nonatomic) timestamp_t latestTimeStamp;
@property(nonatomic) timestamp_t prevLastSampleTimeWritten;

@property(strong, nonatomic) NSOutputStream* stream;

@property(nonatomic) BOOL isLogging;
@property(nonatomic) BOOL shouldAppendToLog;

@end


@implementation DBDataLogger

timestamp_t timeStampForSample(NSDictionary* sample) {
	timestamp_t time = [[sample valueForKey:kKeyTimeStamp] unsignedLongLongValue];
	if (time <= 0) {
		NSLog(@"timestamp for sample = %lld, something done bad", time);
	}
	return time;
}

NSArray* sortedByTimeStamp(NSArray* data) {
	if (! data) return nil;
	NSSortDescriptor* sortBy = [NSSortDescriptor sortDescriptorWithKey:kKeyTimeStamp ascending:YES];
	NSArray* wrapSortBy = [NSArray arrayWithObjects:sortBy, nil];
	return [data sortedArrayUsingDescriptors:wrapSortBy];
}

-(id) initWithSignalNames:(NSArray*)names
			defaultValues:(NSArray*)defaults
			   samplePeriod:(NSUInteger)ms {
	if (self = [super init]) {

		// add a "signal" for the time stamp at position 0
		NSMutableArray* defaultsWithTimeStamp = [defaults mutableCopy];
		[defaultsWithTimeStamp insertObject:@(kDefaultTimeStamp) atIndex:0];
		_defaultValues = defaultsWithTimeStamp;
		
		NSMutableArray* sigNames = [names mutableCopy];
		[sigNames insertObject:kKeyTimeStamp atIndex:0];
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
		
		// file stuff
		_logName = kDefaultLogName;
		
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

-(void) logData:(NSDictionary*)kvPairs withTimeStamp:(timestamp_t)ms {
	if (! _isLogging) return;
	
	if (ms <= 0) {
		ms = currentTimeStampMs();
	} else if (ms <= _lastFlushTimeMs) { //we'll just ignore it later anyway
		return;
	}
	
	NSMutableDictionary* sample = [kvPairs mutableCopy];
	[sample setObject:@(ms) forKey:kKeyTimeStamp];
	[_data addObject:sample];
	
//	NSLog(@"logging sample: %@", kvPairs);
//	NSLog(@"logData: current _data: %@", _data);
	
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
	
	int numSamples = [sampleDicts count];
	int finalIdx = numSamples - 1;
	for (int i = 0; i < numSamples; i++) {
		int stepsFromEnd = finalIdx - i;
		int timeFromEnd = stepsFromEnd * periodMs;
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
	int numKeys = [keys count];
	for (int i = 0; i < len; i+= numKeys) {
		NSDictionary* sample = [NSDictionary dictionary];
		for (id key in keys) {
			[sample setValue:array[i++] forKey:key];
		}
		[buff addObject:sample];
	}
	return buff;
}

-(void) flushUpToTimeStamp:(timestamp_t)ms {
	if (! [_data count]) return;
//	NSLog(@"flushing; data nil? %d", _data == nil);
//	NSLog(@"flushing; data count = %d", [_data count]);
////	NSLog(@"data = %@", _data);
//	for(int i = 0; i < [_data count]; i++) {
//		NSLog(@"data[i] = %@", _data[i]);
//	}
//	return;
	NSArray* sorted = sortedByTimeStamp(_data);
	NSInteger numSamples = [sorted count];
	timestamp_t minTime = _lastFlushTimeMs;
	_lastFlushTimeMs = currentTimeStampMs();
	
	// find the start of samples that are after the last flush;
	// at end of loop, start is the first idx in the array that's
	// after minTime; ; ie, start = 1st index in flush samples
	unsigned int start, stop;
	
	for (start = 0; start < numSamples; start++) {
		timestamp_t sampleTime = timeStampForSample(sorted[start]);
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
		timestamp_t sampleTime = timeStampForSample(sorted[stop]);
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

BOOL isFloatingPointNumber(id x) {
//	return !! [x doubleValue];
	if (! [x isKindOfClass:[NSNumber class]]) return NO;
//	return YES;
	const char* typ = [x objCType];
	BOOL isFloat = ! strncmp(typ, @encode(float), 1);
	BOOL isDouble = ! strncmp(typ, @encode(double), 1);
	return isFloat || isDouble;
}

void writeSampleValuesToStream(NSArray* values, NSOutputStream* stream) {
	NSMutableArray* fmtVals = [NSMutableArray arrayWithCapacity:[values count]];
	for (id val in values) {
		if (val && [val doubleValue] && isFloatingPointNumber(val)) {
			[fmtVals addObject:[NSString stringWithFormat:kFloatFormat, [val doubleValue]]];
		} else {
			[fmtVals addObject:val];
		}
	}
	NSString* line = [[fmtVals componentsJoinedByString:kCsvSeparator] stringByAppendingString:@"\n"];
	NSLog(@"writing line: %@", line);
	NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
	[stream write:data.bytes maxLength:data.length];
}

-(void) resetCurrentSampleValues {
	_currentSampleValues = [_defaultValues mutableCopy];
}

-(void) resetCurrentSampleValuesIfGapFromT:(timestamp_t)t toTprev:(timestamp_t)tprev {
	if (t - tprev > _gapThresholdMs) {
		[self resetCurrentSampleValues];
	}
}

// assumes that samples are sorted by increasing timestamp
-(void)writeData:(NSArray*)samples {
	if (! [samples count]) return;

	timestamp_t sampleBoundary = timeStampForSample(samples[0]) + _samplingPeriodMs;
	timestamp_t t = timeStampForSample(samples[0]);
	timestamp_t tprev = _prevLastSampleTimeWritten;
	[self resetCurrentSampleValuesIfGapFromT:t toTprev:tprev];
	
	// ensure that default values don't get written on 1st iteration
	// of the loop the first time this log writes data
	[self updateSampleValues:_currentSampleValues withSample:samples[0]];

	NSDictionary* sample;
	NSMutableArray* prevSampleValues;
	for (int i = 1; i < [samples count]; i++) {
		sample = samples[i];
		
		// Everything within, eg, 20ms, gets combined
		// into one sample, since data sources write asynchronously; we
		// identify when to write by when the current sample's time is
		// past the end of the combining boundary
		//
		// Also note that if there's nothing to update, we'll just
		// write the same data repeatedly so that we stil log at our
		// master sampling rate;
		//
		// However, if there's a huge gap (more than k seconds), just
		// write the default values as a "hey, there's a pause here"
		// flag and continue on; interpolating here wouldn't be super
		// meaningful
		//
		// More precisely:
		//
		// let t, tprev be current and previous sample times
		// let thresh be the end of the current period
		// let gap be the amount of time necessitating a reset
		//
		// let delta = t - tprev
		// let tau = t - thresh
		//
		// case: tau < 0, delta < gap
		//	sample not done yet, so update currentSample
		// case: tau < 0, delta > gap
		//	-impossible unless gap is stupidly small, in which case it's your fault
		//		-what if tprev is -inf?
		//			-then thresh must also be -inf, so this still doesn't happen
		// case: tau > 0, delta < gap
		//	-last sample was the last one in the combined sample
		//	-need to interpolate until the current sample
		// case: tau > 0, delta > gap
		//	-gap happened
		//	-write the previous sample
		//	-reset the current sample before updating it
		//
		// start and end edge conditions:
		//	-currentSampleValues is assumed to be partially completed from
		//	the last write
		//		-unless this is the first stuff we've written, in which case
		//		it's the garbage default values
		//		case partially complete:
		//			-just like if the loop were continuing from a prev iteration
		//		case garbage:
		//			-don't write it even if the next sample crosses thresh
		//	-at the end, we must assume that currentSampleValues is partially
		//	completed, unless we know the next sample won't come until after
		//	the thresh
		//		-but we don't actually know this because everything that isn't
		//		passed into this method hasn't been flushed
		//			-unless the stream is paused, but then something can
		//			explicitly tell us / write currentSample itself		//TODO
		//
		// -actually, screw dealing with gaps...all the interpolated values will
		// get the same timestamp, so you can filter them out later if you want
		//	-only thing we actually have to deal with is not writing garbage
		//	the first time we write
		//
		//
		//
		// So what actually happened is that I decided to ignore dealing with
		// carrying currentSampleValues across invokations and interpolate
		// regardless of whether there was a gap, but still reset stuff after
		// a gap. A gap is unlikely to ever occur cuz phone accel, etc, will
		// pump out data continuously, so if we really cared, we'd have timeouts
		// specific to each signal
		
		// update current and previous samples
		tprev = t;
		t = timeStampForSample(sample);
		[self resetCurrentSampleValuesIfGapFromT:t toTprev:tprev];
		prevSampleValues = _currentSampleValues;
		[self updateSampleValues:_currentSampleValues withSample:sample];

		// write out finished samples, reproducing them forward in time
		// until we hit another sample
		while (t > sampleBoundary) {
			writeSampleValuesToStream(prevSampleValues, _stream);
			sampleBoundary += _samplingPeriodMs;
		}
//		if (sampleBoundary + _gapThresholdMs < sampleTime) {
//			_currentSampleValues = [_defaultValues mutableCopy];
//			writeSampleValuesToStream(_defaultValues, _stream);
//			break;
//		} else {
//			while (sampleTime > sampleBoundary) {
//				writeSampleValuesToStream(prevSampleValues, _stream);
//				sampleBoundary += _samplingPeriodMs;
//			}
//		}
	}
	// deal with last sample not getting written; a slightly more
	// accurate way would be to wait to write this until the next
	// time data is written and combine it with appropriate samples
	// there, but that makes things way more complicated
	writeSampleValuesToStream(prevSampleValues, _stream);
	
	_prevLastSampleTimeWritten = timeStampForSample(sample);
}

-(void) flush {
	[self flushUpToTimeStamp:maxTimeStampMs()];
}

-(void) setLogName:(NSString *)logName {
	if (_isLogging) {
		[self endLog];
		_logName = logName;
		[self startLog];
	} else {
		_logName = logName;
	}
}

-(NSString*) generateLogFilePath {
	NSString* logPath = [FileUtils getFullFileName:_logName];
	logPath = [logPath stringByAppendingString:kLogNameAndDateSeparator];
	logPath = [logPath stringByAppendingString:currentTimeStrForFileName()];
	return [logPath stringByAppendingString:kLogFileExt];
}

-(void) startLog {
	if (_isLogging) return;
	_isLogging = YES;
	
	NSString* logPath = [self generateLogFilePath];
	_stream = [[NSOutputStream alloc] initToFileAtPath:logPath append:_shouldAppendToLog];
	[_stream open];
	
	// write signal names as first line
	writeSampleValuesToStream(_allSignalNames, _stream);
	
	_lastFlushTimeMs = currentTimeStampMs();
	_latestTimeStamp = minTimeStampMs();
}
-(void) pauseLog {
	_isLogging = NO;
	_shouldAppendToLog = YES;
	[self flush];
	[_stream close];
}
-(void) endLog {
	[self pauseLog];
	_shouldAppendToLog = NO;
}
-(void) deleteLog {
	[self endLog];
	[FileUtils deleteFile:[self generateLogFilePath]];
}

@end
