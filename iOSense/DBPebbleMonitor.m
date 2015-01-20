//
//  DBPebbleMonitor.m
//  iOSense
//
//  Created by DB on 1/18/15.
//  Copyright (c) 2015 Rafael Aguayo. All rights reserved.
//

#import "DBPebbleMonitor.h"

#import <PebbleKit/PebbleKit.h>

static NSString *const kPebbleAppUUID = @"00674CB5-AFEE-464D-B791-5CDBA233EA93";
static const NSUInteger kPebbleAccelHz = 20;
static const NSUInteger kPebbleAccelPeriodMs = 1000 / kPebbleAccelHz;

// keys in dict the pebble app sends
//static const uint8_t KEY_TRANSACTION_ID = 0x1;	//unused
static const uint8_t kKeyNumBytes		= 0x2;
static const uint8_t kKeyData           = 0x3;

NSString *const kKeyPebbleX = @"PebX";
NSString *const kKeyPebbleY = @"PebY";
NSString *const kKeyPebbleZ = @"PebZ";
NSString *const kKeyPebbleTimestamp = @"PebT";
NSString *const kKeyPebbleWatch = @"PebWatch";

NSString *const kNotificationPebbleData = @"PebbleMonitorNotifyData";
NSString *const kNotificationPebbleConnected = @"PebbleMonitorNotifyConnected";
NSString *const kNotificationPebbleDisconnected = @"PebbleMonitorNotifyDisconnected";

#define DEFAULT_ACCEL_VALUE @(NAN)

NSDictionary* pebbleDefaultValuesDict() {
	return @{kKeyPebbleX: DEFAULT_ACCEL_VALUE,
			 kKeyPebbleY: DEFAULT_ACCEL_VALUE,
			 kKeyPebbleZ: DEFAULT_ACCEL_VALUE};
}

//===============================================================
#pragma mark Properties
//===============================================================

@interface DBPebbleMonitor () <PBPebbleCentralDelegate>

@property (strong, nonatomic) PBWatch *myWatch;
@property (nonatomic) BOOL launchedApp;

@end

//===============================================================
#pragma mark Implementation
//===============================================================

@implementation DBPebbleMonitor

//--------------------------------
// initialization
//--------------------------------

-(instancetype) init {
	if (self = [super init]) {
		_launchedApp = NO;
		
		// pebble connection + callbacks
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			[self setupPebble];
		});
	}
	return self;
}

//--------------------------------
// utility funcs
//--------------------------------

- (void)setPebbleUUID:(NSString*)uuidStr {
	uuid_t myAppUUIDbytes;
	NSUUID *myAppUUID = [[NSUUID alloc] initWithUUIDString:uuidStr];
	[myAppUUID getUUIDBytes:myAppUUIDbytes];
	[[PBPebbleCentral defaultCentral] setAppUUID:[NSData dataWithBytes:myAppUUIDbytes length:16]];
}

- (void)setupPebble {
	[[PBPebbleCentral defaultCentral] setDelegate:self];
	[PBPebbleCentral setDebugLogsEnabled:YES];
	[self setPebbleUUID:kPebbleAppUUID];
	self.myWatch = [[PBPebbleCentral defaultCentral] lastConnectedWatch];
	NSLog(@"Last connected watch: %@", self.myWatch);
}

- (void)startWatchApp {
	
	[self.myWatch appMessagesLaunch:^(PBWatch *watch, NSError *error) {
		if (!error) {
			NSLog(@"Successfully launched app.");
		} else {
			NSLog(@"Error launching app: %@", error);
		}
	}];
	
//	__block int counter = 0;
	if (_launchedApp) return;	//only do this once
	_launchedApp = YES;
	[self.myWatch appMessagesAddReceiveUpdateHandler:^BOOL(PBWatch *watch, NSDictionary *update) {
//		counter++;
		[self logUpdate:update fromWatch:watch];
		return YES;
	}];
}

- (void)stopWatchApp {
	[self.myWatch appMessagesKill:^(PBWatch *watch, NSError *error) {
		if(error) {
			NSLog(@"Error closing watchapp: %@", error);
		}
	}];
	
	_launchedApp = NO;
}

//--------------------------------
// PBPebbleCentralDelegate
//--------------------------------

- (void)pebbleCentral:(PBPebbleCentral*)central watchDidConnect:(PBWatch*)watch isNew:(BOOL)isNew {
	[[[UIAlertView alloc] initWithTitle:@"Connected!"
								message:[watch name]
							   delegate:nil cancelButtonTitle:@"OK"
					  otherButtonTitles:nil] show];
	_pebbleConnected = YES;
	NSLog(@"Pebble connected: %@", [watch name]);
	self.myWatch = watch;
	[self startWatchApp];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:kNotificationPebbleConnected
														object:self
													  userInfo:@{kKeyPebbleWatch: watch}];
}

- (void)pebbleCentral:(PBPebbleCentral*)central watchDidDisconnect:(PBWatch*)watch {
	_pebbleConnected = NO;
//	[self logAccelX:NONSENSICAL_DOUBLE
//				  Y:NONSENSICAL_DOUBLE
//				  Z:NONSENSICAL_DOUBLE
//		  timeStamp:currentTimeStampMs()];
	NSLog(@"Pebble disconnected: %@", [watch name]);
	
	if (self.myWatch == watch || [watch isEqual:self.myWatch]) {
		self.myWatch = nil;
	}
	
	[[NSNotificationCenter defaultCenter] postNotificationName:kNotificationPebbleDisconnected
														object:self
													  userInfo:@{kKeyPebbleWatch: watch}];
}

//--------------------------------
// Data processing
//--------------------------------

void extractPebbleData(NSDictionary* data, int*x, int*y, int*z, timestamp_t* t) {
	*x = [data[kKeyPebbleX] intValue];
	*y = [data[kKeyPebbleY] intValue];
	*z = [data[kKeyPebbleZ] intValue];
	*t = [data[kKeyPebbleTimestamp] longLongValue];
}

- (BOOL)logUpdate:(NSDictionary*)update fromWatch:(PBWatch*)watch {
	
	//	int transactionId = (int) [[update objectForKey:@(KEY_TRANSACTION_ID)] integerValue];
	int numBytes = (int) [[update objectForKey:@(kKeyNumBytes)] integerValue];
	NSData* accelData = [update objectForKey:@(kKeyData)];
	const int8_t* dataAr = (const int8_t*) [accelData bytes];
	
	// compute start time of this buffer
	uint numSamples = numBytes / 3;
	uint bufferDuration = numSamples * kPebbleAccelPeriodMs;
	timestamp_t startTime = currentTimeStampMs() - bufferDuration;
	
	int8_t x, y, z;
	timestamp_t sampleTime;
	for (int i = 0; i < numBytes; i += 3) {
		x = dataAr[i];
		y = dataAr[i+1];
		z = dataAr[i+2];
		
		// logging
		sampleTime = startTime + (i/3) * kPebbleAccelPeriodMs;
		NSDictionary* data = @{kKeyPebbleX: @(x),
							   kKeyPebbleY: @(y),
							   kKeyPebbleZ: @(z),
							   kKeyPebbleTimestamp: @(sampleTime),
							   kKeyPebbleWatch:watch};
		[[NSNotificationCenter defaultCenter] postNotificationName:kNotificationPebbleData
															object:self userInfo:data];
	}
	return YES;
}

@end
