//
//  Utils.m
//  DisplayAcc
//
//  Created by DB on 1/7/15.
//  Copyright (c) 2015 D Blalock. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef int64_t timestamp_t;

// ================================================================
// timestamp_t funcs
// ================================================================

timestamp_t currentTimeStampMs() {
	return [@(floor([[NSDate date] timeIntervalSince1970] * 1000)) longLongValue];
}

timestamp_t maxTimeStampMs() {
	// 2^63 - 1, avoiding overflow from actually doing 2^63
	return (((int64_t) 1) << 62) + ((((int64_t) 1) << 62) - 1);
}

timestamp_t minTimeStampMs() {
	return (-maxTimeStampMs()) - 1;
}

timestamp_t timeStampfromTimeInterval(NSTimeInterval interval) {
	return floor(interval * 1000);	// NSTimeInterval == double
}

timestamp_t timeStampFromDate(NSDate* date) {
	return timeStampfromTimeInterval([date timeIntervalSince1970]);
}

// time since 1970 that coremotion considers to be 0
timestamp_t coreMotionStartTimeMs() {
	static timestamp_t offset = 0;
	if (! offset) {
		NSTimeInterval uptime = [NSProcessInfo processInfo].systemUptime;
		NSTimeInterval nowTimeIntervalSince1970 = [[NSDate date] timeIntervalSince1970];
		offset = nowTimeIntervalSince1970 - uptime;
	}
	return offset;
}

// core motion gives timestamps from system boot, not unix timestamps,
// so we need to add the time at which the system booted
timestamp_t timeStampFromCoreMotionTimeStamp(NSTimeInterval timestamp) {
	return coreMotionStartTimeMs() + timeStampfromTimeInterval(timestamp);
}

// ================================================================
// timestamp_t-agnostic funcs
// ================================================================

int64_t currentTimeMs() {
	return [@(floor([[NSDate date] timeIntervalSince1970] * 1000)) longLongValue];
}

NSDateFormatter* isoDateFormatter() {
	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	//	NSString* localId = [[NSLocale currentLocale] localeIdentifier];
	//	NSLocale *enUSPOSIXLocale = [NSLocale localeWithLocaleIdentifier:];
//	[dateFormatter setLocale:[NSLocale currentLocale]];
	NSLocale *enUSPOSIXLocale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
	[dateFormatter setLocale:enUSPOSIXLocale];
	[dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZZZZZ"];
	return dateFormatter;
}

NSString* currentTimeStr() {
	NSDate *now = [NSDate date];
	NSString *iso8601String = [isoDateFormatter() stringFromDate:now];
	return iso8601String;
}
