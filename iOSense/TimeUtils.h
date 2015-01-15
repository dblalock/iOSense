//
//  Utils.h
//  DisplayAcc
//
//  Created by DB on 1/6/15.
//

#import <Foundation/Foundation.h>

typedef int64_t timestamp_t;

// ================================================================
// timestamp funcs
// ================================================================

timestamp_t currentTimeStampMs();
timestamp_t maxTimeStampMs();
timestamp_t minTimeStampMs();
timestamp_t timeStampfromTimeInterval(NSTimeInterval interval);
timestamp_t timeStampFromDate(NSDate* date);

// time since 1970 that coremotion considers to be 0
timestamp_t coreMotionStartTimeMs();

// core motion gives timestamps from system boot, not unix timestamps,
// so we need to add the time at which the system booted
timestamp_t timeStampFromCoreMotionTimeStamp(NSTimeInterval timestamp);

// ================================================================
// other funcs
// ================================================================

int64_t currentTimeMs();

NSDateFormatter* isoDateFormatter();
NSString* currentTimeStr();
//NSDateFormatter* isoDateFormatterForFileName();	//no colons
NSString* currentTimeStrForFileName();			//no colons
