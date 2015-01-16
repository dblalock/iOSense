//
//  DBSensorMonitor.h
//  DisplayAcc
//
//  Created by DB on 1/8/15.
//  Copyright (c) 2015 D Blalock. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "TimeUtils.h"

// any number < -180.0 should work for everything; important that it be
// negative since negative vals are how {speed, course, * accuracy}
// (and possibly a couple others) signal that they're invalid
#define NONSENSICAL_DOUBLE NAN
#define NONSENSICAL_NUMBER @(NONSENSICAL_DOUBLE)

// other values are more meaningful, but really nice to just have one value
// to mark invalidity for subsequent mining

// motion defaults
#define DBINVALID_ACCEL				NONSENSICAL_NUMBER
#define DBINVALID_ANGLE				NONSENSICAL_NUMBER
#define DBINVALID_MAG				NONSENSICAL_NUMBER
#define DBINVALID_ACCURACY_MAG		NONSENSICAL_NUMBER //@(CMMagneticFieldCalibrationAccuracyUncalibrated)// = -1
#define DBINVALID_ACCURACY_LOC		NONSENSICAL_NUMBER	//@(-1)

// location defaults (not covered by above)
#define DBINVALID_DISTANCE          NONSENSICAL_NUMBER
#define DBINVALID_FLOOR				NONSENSICAL_NUMBER
#define DBINVALID_SPEED				NONSENSICAL_NUMBER	//@(-1)

// heading defaults (not covered by above)
#define DBINVALID_ACCURACY_HEADING	NONSENSICAL_NUMBER	//@(-1)
#define DBINVALID_HEADING			NONSENSICAL_NUMBER

// other defaults
#define DBINVALID_HASH				NONSENSICAL_NUMBER
#define DBINVALID_TIMESTAMP			NONSENSICAL_NUMBER


@interface DBSensorMonitor : NSObject

@property (nonatomic, copy) void (^onDataReceived)(NSDictionary* data, timestamp_t timestamp);
@property (nonatomic) BOOL sendOnlyIfDifferent;

-(instancetype) initWithDataReceivedHandler:(void (^)(NSDictionary* data, timestamp_t timestamp))handler;
-(void) poll;	//force update
-(void) pollLocation;	//force update of only location / heading

@end

NSDictionary* allSensorDefaultsDict();
//NSArray* allSensorDataKeys();
//NSArray* allSensorDataDefaultValues();