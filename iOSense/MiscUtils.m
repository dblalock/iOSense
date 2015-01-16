//
//  MiscUtils.m
//  iOSense
//
//  Created by DB on 1/11/15.
//  Copyright (c) 2015 DB. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import <SSKeychain.h>

NSString* getAppName() {
	return [[[NSBundle mainBundle] infoDictionary] objectForKey:(NSString*)kCFBundleNameKey];
}

NSString* getUniqueDeviceIdentifierAsString() {
	NSString *appName=[[[NSBundle mainBundle] infoDictionary] objectForKey:(NSString*)kCFBundleNameKey];
	
	// to get SSKeyChain, just "pod 'SSKeychain'" and add Security.framework
	NSString *strApplicationUUID = [SSKeychain passwordForService:appName account:@"incoding"];
	if (strApplicationUUID == nil) {
		strApplicationUUID  = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
		[SSKeychain setPassword:strApplicationUUID forService:appName account:@"incoding"];
	}
	return strApplicationUUID;
}

NSUUID* getUniqueDeviceIdentifierUUID() {
	return [[NSUUID alloc] initWithUUIDString:getUniqueDeviceIdentifierAsString()];
}

NSUInteger getUniqueDeviceIdentifierUInt() {
	return [getUniqueDeviceIdentifierUUID() hash];
}

uint64_t getUniqueDeviceIdentifier64bits() {
	uuid_t uuid;
	[getUniqueDeviceIdentifierUUID() getUUIDBytes:uuid];

	// pretty sure this could be shortened and ignore endianness since
	// it just needs to be a long random number, but this is what I pasted
	// from the internet (clearly a good justification)
	NSData *uuidData = [NSData dataWithBytes:uuid length:16];
	NSData *data8 = [uuidData subdataWithRange:NSMakeRange(0, 8)];
	uint64_t value = CFSwapInt64BigToHost(*(int64_t*)([data8 bytes]));
	return value;
}

NSUInteger writeAsJSON(id object, NSOutputStream* stream, BOOL pretty) {
	NSJSONWritingOptions options = pretty ? (NSJSONWritingPrettyPrinted) : 0;
	return [NSJSONSerialization writeJSONObject:object
									   toStream:stream
										options:options
										  error:nil];
}

NSData* toJSONData(id object, BOOL pretty) {
	NSJSONWritingOptions options = pretty ? (NSJSONWritingPrettyPrinted) : 0;
	return [NSJSONSerialization dataWithJSONObject:object
										   options:options
											 error:nil];
}

NSString* toJSONString(id object, BOOL pretty) {
	NSData* data = toJSONData(object, pretty);
	return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

UIViewController* getRootViewController() {
	return [[UIApplication sharedApplication] keyWindow].rootViewController;
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

BOOL objsDifferent(id x, id y) {
//	NSLog(@"%@ and %@ different?", x, y);
	if (x == y) return NO;
	BOOL xIsNum = [x isKindOfClass:[NSNumber class]];
	BOOL yIsNum = [y isKindOfClass:[NSNumber class]];
	if (xIsNum && yIsNum) {
		return ! [x isEqualToNumber:y];
	}
	return ! [x isEqual:y];
}
