//
//  DBSensorMonitor.m
//  DisplayAcc
//
//  Created by DB on 1/8/15.
//

//NOTES:
// -we could just not even invoke the callback when the data we receive is
// invalid, but this way we log when it becomes invalid if it was valid before

#import "DBSensorMonitor.h"

#import <CoreMotion/CoreMotion.h>
#import <CoreLocation/CoreLocation.h>
#import "TimeUtils.h"

static const float kMotionSamplingPeriod = .05;	//20Hz

BOOL motionHasValidMagField(CMDeviceMotion* motion) {
	return motion && motion.magneticField.accuracy != CMMagneticFieldCalibrationAccuracyUncalibrated;
}

BOOL locationValid(CLLocation* location) {
	if (! location) return NO;
	return location.verticalAccuracy > 0 && location.horizontalAccuracy > 0;
}

BOOL headingValid(CLHeading* heading) {
	return heading && heading.headingAccuracy > 0;
}

//TODO make all the keys string constants

NSDictionary* defaultsDictMotion() {
	return @{	@"gravity x (g)": DBINVALID_ACCEL,
				@"gravity y (g)": DBINVALID_ACCEL,
				@"gravity z (g)": DBINVALID_ACCEL,
				@"userAccel x (g)": DBINVALID_ACCEL,
				@"userAccel y (g)": DBINVALID_ACCEL,
				@"userAccel z (g)": DBINVALID_ACCEL,
				@"roll (rad)":	DBINVALID_ANGLE,
				@"pitch (rad)": DBINVALID_ANGLE,
				@"yaw (rad)":	DBINVALID_ANGLE,
				@"rotation x (rad/s)": DBINVALID_ANGLE,
				@"rotation y (rad/s)": DBINVALID_ANGLE,
				@"rotation z (rad/s)": DBINVALID_ANGLE,
				@"mag field accuracy": DBINVALID_ACCURACY_MAG,	//none, low, med, high
				@"mag field x": DBINVALID_MAG,
				@"mag field y": DBINVALID_MAG,
				@"mag field z": DBINVALID_MAG,
				@"motionUpdateTimestamp": DBINVALID_TIMESTAMP};
}

NSDictionary* defaultsDictLocation() {
	return @{	@"latitude (deg)" : DBINVALID_ANGLE,
				@"longitude (deg)": DBINVALID_ANGLE,
				@"altitude (deg)" : DBINVALID_ANGLE,
				@"horizontal accuracy (m)": DBINVALID_ACCURACY_LOC,
				@"vertical accuracy (m)":	DBINVALID_ACCURACY_LOC,
				@"building floor (int)": DBINVALID_FLOOR,
				@"course (degrees)": DBINVALID_ANGLE,
				@"speed (meters/sec)": DBINVALID_SPEED,
				@"locationUpdateTimestamp": DBINVALID_TIMESTAMP};
}

NSDictionary* defaultsDictHeading() {
	return @{	@"headingAccuracy (deg)":  DBINVALID_ACCURACY_HEADING,
				@"magneticHeading (deg)": DBINVALID_ANGLE,	//to magnetic north
				@"trueHeading (deg)":	  DBINVALID_ANGLE,	//to true north
				@"heading x (uTesla)": DBINVALID_HEADING,
				@"heading y (uTesla)": DBINVALID_HEADING,
				@"heading z (uTesla)": DBINVALID_HEADING,
				@"headingUpdateTimestamp": DBINVALID_TIMESTAMP};
}

NSDictionary* dictFromMotion(CMDeviceMotion* motion) {
	BOOL magValid = motionHasValidMagField(motion);
	return @{	@"gravity x (g)": @(motion.gravity.x),
				@"gravity y (g)": @(motion.gravity.y),
				@"gravity z (g)": @(motion.gravity.z),
				@"userAccel x (g)": @(motion.userAcceleration.x),
				@"userAccel y (g)": @(motion.userAcceleration.y),
				@"userAccel z (g)": @(motion.userAcceleration.z),
				@"roll (rad)":	@(motion.attitude.roll),
				@"pitch (rad)": @(motion.attitude.pitch),
				@"yaw (rad)":	@(motion.attitude.yaw),
				@"rotation x (rad/s)": @(motion.rotationRate.x),
				@"rotation y (rad/s)": @(motion.rotationRate.y),
				@"rotation z (rad/s)": @(motion.rotationRate.z),
				@"mag field accuracy": magValid ? @(motion.magneticField.accuracy) : DBINVALID_ACCURACY_MAG,
				@"mag field x": magValid ? @(motion.magneticField.field.x) : DBINVALID_MAG,
				@"mag field y": magValid ? @(motion.magneticField.field.y) : DBINVALID_MAG,
				@"mag field z": magValid ? @(motion.magneticField.field.z) : DBINVALID_MAG,
				@"motionUpdateTimestamp": @(timeStampFromCoreMotionTimeStamp(motion.timestamp))};
}

NSDictionary* dictFromLocation(CLLocation* location) {
	if (! locationValid(location) ) {
		return defaultsDictLocation();
	}
	return @{	@"latitude (deg)" : @(location.coordinate.latitude),
				@"longitude (deg)": @(location.coordinate.longitude),
				@"altitude (deg)" : @(location.altitude),
				@"horizontal accuracy (m)": @(location.horizontalAccuracy),
				@"vertical accuracy (m)":	@(location.verticalAccuracy),
				@"building floor (int)": @(location.floor.level),
				@"course (degrees)": @(location.course),
				@"speed (meters/sec)": @(location.speed),
				@"locationUpdateTimestamp": @(timeStampFromDate(location.timestamp))};
}

NSDictionary* dictFromHeading(CLHeading* heading) {
	if (! headingValid(heading) ) {
		return defaultsDictHeading();
	}
	return @{	@"headingAccuracy (deg)":  @(heading.headingAccuracy),
				@"magneticHeading (deg)": @(heading.magneticHeading),	//to magnetic north
				@"trueHeading (deg)":	  @(heading.trueHeading),		//to true north
				@"heading x (uTesla)": @(heading.x),
				@"heading y (uTesla)": @(heading.y),
				@"heading z (uTesla)": @(heading.z),
				@"headingUpdateTimestamp": @(timeStampFromDate(heading.timestamp))};
}

NSDictionary* allSensorDefaultsDict() {
	NSMutableDictionary* dict = [NSMutableDictionary dictionary];
	[dict addEntriesFromDictionary:defaultsDictMotion()];
	[dict addEntriesFromDictionary:defaultsDictLocation()];
	[dict addEntriesFromDictionary:defaultsDictHeading()];
	return dict;
}

@interface DBSensorMonitor () <CLLocationManagerDelegate>

@property(strong, nonatomic) CLLocationManager* locationManager;
@property(strong, nonatomic) CMMotionManager* motionManager;
@property(strong, nonatomic) NSOperationQueue* queue;

@end

@implementation DBSensorMonitor

- initWithDataReceivedHandler:(void (^)(NSDictionary* data, timestamp_t timestamp))handler {
	if (self = [super init]) {
		_onDataReceived = handler;
		[self initSensing];
	}
	return self;
}

-(void) pollLocation {
	NSMutableDictionary* data = [NSMutableDictionary dictionary];
	if (locationValid(_locationManager.location)) {
		[data addEntriesFromDictionary:dictFromLocation(_locationManager.location)];
	}
	if (headingValid(_locationManager.heading)) {
		[data addEntriesFromDictionary:dictFromHeading(_locationManager.heading)];
	}
	if ([data count]) {
		_onDataReceived(data, currentTimeStampMs());
	}
}

-(void) poll {
	[self pollLocation];
	timestamp_t time = currentTimeStampMs();
	_onDataReceived(dictFromMotion(_motionManager.deviceMotion), time);
}

- (void) initSensing {
	_locationManager = [[CLLocationManager alloc] init];
	_locationManager.delegate = self;
	_locationManager.desiredAccuracy = kCLLocationAccuracyBest;
	[_locationManager startUpdatingLocation];
	[_locationManager startUpdatingHeading];

	_queue = [[NSOperationQueue alloc] init];
	_motionManager = [[CMMotionManager alloc] init];

	_motionManager.deviceMotionUpdateInterval = kMotionSamplingPeriod;
	[_motionManager startDeviceMotionUpdatesToQueue:_queue
	withHandler:^(CMDeviceMotion *motion, NSError *error) {
		NSDictionary* data = dictFromMotion(motion);
		timestamp_t t = timeStampFromCoreMotionTimeStamp(motion.timestamp);
		if (_onDataReceived) {
			_onDataReceived(data, t);
		}
   }];
}

-(void)locationManager:(CLLocationManager *)manager
   didUpdateToLocation:(CLLocation *)newLocation
		  fromLocation:(CLLocation *)oldLocation{
	NSDictionary* data = dictFromLocation(newLocation);
	timestamp_t t = timeStampFromDate(newLocation.timestamp);
	if (_onDataReceived) {
		_onDataReceived(data, t);
	}
}

-(void)locationManager:(CLLocationManager *)manager
	   didUpdateHeading:(CLHeading *)newHeading {
	NSDictionary* data = dictFromHeading(newHeading);
	timestamp_t t = timeStampFromDate(newHeading.timestamp);
	if (_onDataReceived) {
		_onDataReceived(data, t);
	}
}

@end
