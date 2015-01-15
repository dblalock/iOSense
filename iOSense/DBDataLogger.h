//
//  DBDataLogger.h
//  DisplayAcc
//
//  Created by DB on 1/8/15.
//  Copyright (c) 2015 D Blalock. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "TimeUtils.h"

// ================================================================
// DBLogger
// ================================================================

// nothing here is threadsafe, so need to access it only from main thread
@interface DBDataLogger : NSObject

@property(nonatomic) timestamp_t autoFlushLagMs;
@property(nonatomic) timestamp_t gapThresholdMs;
@property(strong, nonatomic) NSString* logName;
@property(strong, nonatomic) NSString* logSubdir;

-(id) initWithSignalNames:(NSArray*)names
			defaultValues:(NSArray*)defaults
			 samplePeriod:(NSUInteger)ms;

-(void) logData:(NSDictionary*)kvPairs withTimeStamp:(timestamp_t)ms;
-(void) logData:(NSDictionary*)kvPairs;
-(void) logDataBuff:(NSArray*)sampleDicts
  withSampleSpacing:(NSUInteger)periodMs
	 finalTimeStamp:(timestamp_t)ms;
-(void) logDataBuff:(NSArray*)sampleDicts
  withSampleSpacing:(NSUInteger)periodMs;

-(void) startLog;
-(void) pauseLog;
-(void) endLog;
-(void) deleteLog;

-(void) flushUpToTimeStamp:(timestamp_t)ms;
-(void) flush;

@end

// basically just for accelerometer x,y,z crammed into one array
NSArray* rawArrayToSampleBuff(id* array, int len, NSArray* keys);
