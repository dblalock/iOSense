//
//  DBSensorMonitor.m
//  DisplayAcc
//
//  Created by DB on 1/8/15.
//

//NOTES:
// -we could just not even invoke the callback when the data we receive is
// invalid, but this way we log when it becomes invalid if it was valid before
// -we quantize some things to ints to save space (especially when written
// to a csv); this should result in effectively no error, since many of them
// are either ints that happen to be passed as doubles (eg, the number of
// meters to which CoreLocation thinks it's accurate) or have decimal places
// that are likely just noise anyway (eg, the heading of the phone in degrees)

//TODO deal with significant changes for lat/lon properly

#import "DBSensorMonitor.h"

#import <CoreMotion/CoreMotion.h>
#import <CoreLocation/CoreLocation.h>
#import "TimeUtils.h"

#define ANONYMIZE
//#define INCLUDE_MOTION_HASH
//#define INCLUDE_HEADING_HASH

//================================================================
// Constants
//================================================================

//-------------------------------
// Change thresholds
//-------------------------------

// utility consts
static const double RADS_PER_DEGREE = M_2_PI / 360.0;
static const double METERS_PER_DEGREE_LAT = 111130;	// approx, depends on lat
static const double DEGREES_PER_METER = 1.0 / METERS_PER_DEGREE_LAT;

// general thresholds
static const double THRESH_DEGREES_ANGLE_DBL = 3.0;
#define THRESH_DEGREES_ANGLE @(THRESH_DEGREES_ANGLE_DBL)
#define THRESH_RADS_ANGLE @(THRESH_DEGREES_ANGLE_DBL * RADS_PER_DEGREE)

// motion thresholds
#define THRESH_ACCEL 	@(1.0 / 32)				// g
#define THRESH_ATTITUDE THRESH_RADS_ANGLE		// rad
#define THRESH_GYRO  	@(1.0 / 32)				// rad/s
#define THRESH_MAG  	@0						// unknown unit
#define THRESH_ACC_MAG	@0						// enum

// location thresholds
#define THRESH_LATLON 	@(3 * DEGREES_PER_METER)// deg
#define THRESH_ALTITUDE @3						// m
#define THRESH_FLOOR 	@1						// floors
#define THRESH_SPEED 	@.25					// m/s
#define THRESH_ACC_LOC	@0						// m

// heading thresholds
#define THRESH_MAG_HEADING @3					// uTesla
#define THRESH_ACC_HEADING @0					// deg

// sampling rate (don't ask me why this is the only const following
// the objc naming convention...)
static const float kMotionSamplingPeriod = .05;	//20Hz

//-------------------------------
// Data keys
//-------------------------------

// motion
NSString *const KEY_GRAV_X = @"gravX";	// accel due to gravity, g
NSString *const KEY_GRAV_Y = @"gravY";	// accel due to gravity, g
NSString *const KEY_GRAV_Z = @"gravZ";	// accel due to gravity, g
NSString *const KEY_USR_X  = @"usrX";	// accel due to user, g
NSString *const KEY_USR_Y  = @"usrY";	// accel due to user, g
NSString *const KEY_USR_Z  = @"usrZ";	// accel due to user, g
NSString *const KEY_ROLL   = @"roll";	// rad
NSString *const KEY_PITCH  = @"pitch";	// rad
NSString *const KEY_YAW	   = @"yaw";	// rad
NSString *const KEY_GYRO_X = @"gyroX";	// rad/s
NSString *const KEY_GYRO_Y = @"gyroY";	// rad/s
NSString *const KEY_GYRO_Z = @"gyroZ";	// rad/s
NSString *const KEY_MAG_ACC= @"magAcc";	// {uncalibrated, low, med, high}
NSString *const KEY_MAG_X  = @"magX";	// (undocumented unit, perhaps degrees)
NSString *const KEY_MAG_Y  = @"magY";	// (undocumented unit, perhaps degrees)
NSString *const KEY_MAG_Z  = @"magZ";	// (undocumented unit, perhaps degrees)
#ifdef INCLUDE_MOTION_HASH
NSString *const KEY_MOTION_UPDATE_HASH = @"_hashMot"; // 0-999 value identifying an update
#endif

// location
NSString *const KEY_LATITUDE  = @"lat";					// deg
NSString *const KEY_LONGITUDE = @"lon";					// deg
NSString *const KEY_ALTITUDE  = @"alt";					// m
NSString *const KEY_HORIZONTAL_ACC = @"horzAcc";		// m
NSString *const KEY_VERTICAL_ACC   = @"vertAcc";		// m
#ifndef ANONYMIZE
NSString *const KEY_BUILDING_FLOOR = @"floor";			// int, floor number
#endif
NSString *const KEY_COURSE = @"course";					// deg
NSString *const KEY_SPEED = @"speed";					// m/s
NSString *const KEY_LOCATION_UPDATE_HASH = @"_hashLoc";	// 0-999 value identifying an update

// heading
NSString *const KEY_HEADING_ACC = @"headAcc";	// deg
NSString *const KEY_MAG_HEADING  = @"magHead";	// deg
#ifndef ANONYMIZE
NSString *const KEY_TRUE_HEADING = @"truHead";	// deg
#endif
NSString *const KEY_HEADING_X = @"headX";		// (uTesla)
NSString *const KEY_HEADING_Y = @"headY";		// (uTesla)
NSString *const KEY_HEADING_Z = @"headZ";		// (uTesla)
#ifdef INCLUDE_HEADING_HASH
NSString *const KEY_HEADING_UPDATE_HASH  = @"_hashHead";	// 0-999 value identifying an update
#endif

//================================================================
// Utility funcs
//================================================================

BOOL motionHasValidMagField(CMDeviceMotion* motion) {
	return motion && motion.magneticField.accuracy != CMMagneticFieldCalibrationAccuracyUncalibrated;
}

BOOL locationValid(CLLocation* location) {
	return (location
		&& location.verticalAccuracy > 0
		&& location.horizontalAccuracy > 0);
}

BOOL headingValid(CLHeading* heading) {
	return heading && heading.headingAccuracy > 0;
}

int hashTimeStamp(timestamp_t t) {
	return t % 1000;
}

static BOOL changeAboveThresh(double old, double new, double thresh) {
	return fabs(old - new) >= thresh;
}

static BOOL valChanged(id oldVal, id newVal, id thresh) {
//	NSLog(@"checking if stuff changed");
	// if there is no previous value, always a change
//	if (! oldVal) {
//		return YES;
//	}

	// if not the same kind of class, always a change
	if (! [newVal isMemberOfClass:[oldVal class]]) {
		return YES;
	}
	
	// if both numbers, numeric equality with provided threshold
	BOOL oldValIsNum = [oldVal isKindOfClass:[NSNumber class]];
	BOOL newValIsNum = [newVal isKindOfClass:[NSNumber class]];
	BOOL threshIsNum = [thresh isKindOfClass:[NSNumber class]];
	if (oldValIsNum && newValIsNum) {
//		NSLog(@"stuff is numbers!");
		// always exceeds a meaningless threshold
		if (! threshIsNum) return YES;
		
		double old = [oldVal doubleValue];
		double new = [newVal doubleValue];
		double threshDbl = [thresh doubleValue];
		return changeAboveThresh(old, new, threshDbl);
//		BOOL changed = changeAboveThresh(old, new, threshDbl);
//		if (! changed) {
//			NSLog(@"number didn't change");
//		} else {
//			NSLog(@"number changed!");
//		}
	}
	
	// otherwise, use class isEqual
	return [newVal isEqual:oldVal];
}

// note that this assumes != is the correct comparison for dict values and/or that
// the > operator is defined on them
NSDictionary* extractChanges(NSDictionary* oldDict, NSDictionary* newDict, NSDictionary* thresholds) {
//	NSLog(@"called extract changes...");
	if (! [newDict count]) return [NSMutableDictionary dictionary];
	if (! [oldDict count]) return newDict;
	
	NSMutableDictionary* dict = [NSMutableDictionary dictionary];
//	NSLog(@"extracting changes...");
	for (id key in [newDict allKeys]) {
		id oldVal = [oldDict objectForKey:key];
		id newVal = [newDict objectForKey:key];
		if (! thresholds) {
			[dict setObject:newVal forKey:key];
			continue;
		}
		id thresh = [thresholds objectForKey:key];
		if (valChanged(oldVal, newVal, thresh)) {
			[dict setObject:newVal forKey:key];
		}
	}
	return dict;
}

//================================================================
// Anonymization funcs
//================================================================

#ifdef ANONYMIZE
// to anonymize, need to:
//	-remove either floor or altitude
//	-add random, but consistent, offset to lat/lon/altitude (and ideally
//	change basis entirely so that direction is also altered)
//	-remove either true north or magnetic north
#import "MiscUtils.h"	// for device UDID

static BOOL sInitialized = NO;
static int sAltitudeOffset;
static int sLatOffset;
static int sLonOffset;
static double sLatLatCoeff;
static double sLatLonCoeff;
static double sLonLatCoeff;
static double sLonLonCoeff;

double l2_norm(double x, double y) {
	return sqrt(x*x + y*y);
}

double anonAltitude(double alt) {
	return alt + sAltitudeOffset;
}
double anonLatitude(double lat, double lon) {
	return (lat + sLatOffset) * sLatLatCoeff + (lon + sLonOffset) * sLatLonCoeff;
}
double anonLongitude(double lat, double lon) {
	return (lat + sLatOffset) * sLonLatCoeff + (lon + sLonOffset) * sLonLonCoeff;
}

#define MAX_OFFSET_DEGREES 16
static void initAnonymizing() {		// not threadsafe !
	if (sInitialized) return;
	sInitialized = YES;
	
	srand48((int32_t)getUniqueDeviceIdentifier64bits());
	sAltitudeOffset = drand48() * 2 * MAX_OFFSET_DEGREES - MAX_OFFSET_DEGREES;
	sLatOffset		= drand48() * 2 * MAX_OFFSET_DEGREES - MAX_OFFSET_DEGREES;
	sLonOffset		= drand48() * 2 * MAX_OFFSET_DEGREES - MAX_OFFSET_DEGREES;
	
	// We anonymize latitude and longitude by taking the original
	// <lat, lon> vector and converting it to a different basis (and
	// adding an offset to each).
	//
	// We bias this basis towards the original one by pulling the 1st
	// diagonal from [1, 2) before normalizing to unit length, rather
	// than [-.5, .5). This results in a possible change in angle of
	// [-30deg, 30deg). The bias is desirable because otherwise, it
	// might appear that people who, eg, aim their phone out in front
	// of them as they walk, are holding it in the opposite of their
	// direction of motion.
	//
	// Also, note that we force the basis vectors to be orthogonal; if we
	// didn't do this, a subset of users would have latitudes and longitudes
	// that were basically the same direction, which would make for very
	// confusing GPS fixes.
	sLatLatCoeff = 1 + drand48();		// [1, 2)
	sLatLonCoeff = drand48() - .5;		// [-.5, .5)
	double latMag = l2_norm(sLatLatCoeff, sLatLonCoeff);
	sLatLatCoeff /= latMag;			// eg  2 / sqrt(5)	//y1
	sLatLonCoeff /= latMag;			// eg  1 / sqrt(5)	//x1
	sLonLonCoeff = sLatLonCoeff;	// eg  1 / sqrt(5)	//x2 = y1
	sLonLatCoeff = -sLatLatCoeff;	// eg -2 / sqrt(5)	//y2 = -x1
}
#endif // ANONYMIZE


//================================================================
// Dictionary creation funcs
//================================================================

// --------------------------------------------------------------
// Default sensor values
// --------------------------------------------------------------

NSDictionary* defaultsDictMotion() {
	return @{	KEY_GRAV_X: DBINVALID_ACCEL,
				KEY_GRAV_Y: DBINVALID_ACCEL,
				KEY_GRAV_Z: DBINVALID_ACCEL,
				KEY_USR_X: DBINVALID_ACCEL,
				KEY_USR_Y: DBINVALID_ACCEL,
				KEY_USR_Z: DBINVALID_ACCEL,
				KEY_ROLL: DBINVALID_ANGLE,
				KEY_PITCH: DBINVALID_ANGLE,
				KEY_YAW: DBINVALID_ANGLE,
				KEY_GYRO_X: DBINVALID_ANGLE,
				KEY_GYRO_Y: DBINVALID_ANGLE,
				KEY_GYRO_Z: DBINVALID_ANGLE,
				KEY_MAG_ACC: DBINVALID_ACCURACY_MAG,
				KEY_MAG_X: DBINVALID_MAG,
				KEY_MAG_Y: DBINVALID_MAG,
				KEY_MAG_Z: DBINVALID_MAG,
#ifdef INCLUDE_MOTION_HASH
				KEY_MOTION_UPDATE_HASH: DBINVALID_HASH
#endif
				};
//				@"motionUpdateTimestamp": DBINVALID_TIMESTAMP};
}

NSDictionary* defaultsDictLocation() {
	return @{	KEY_LATITUDE : DBINVALID_ANGLE,
				KEY_LONGITUDE: DBINVALID_ANGLE,
				KEY_ALTITUDE : DBINVALID_DISTANCE,
				KEY_HORIZONTAL_ACC: DBINVALID_ACCURACY_LOC,
				KEY_VERTICAL_ACC: DBINVALID_ACCURACY_LOC,
#ifndef ANONYMIZE
				KEY_BUILDING_FLOOR: DBINVALID_FLOOR,
#endif
				KEY_COURSE: DBINVALID_ANGLE,
				KEY_SPEED: DBINVALID_SPEED,
				KEY_LOCATION_UPDATE_HASH: DBINVALID_HASH};
//				@"locationUpdateTimestamp": DBINVALID_TIMESTAMP};
}

NSDictionary* defaultsDictHeading() {
	return @{	KEY_HEADING_ACC:  DBINVALID_ACCURACY_HEADING,
				KEY_MAG_HEADING:  DBINVALID_ANGLE,	//to magnetic north
#ifndef ANONYMIZE
				KEY_TRUE_HEADING: DBINVALID_ANGLE,	//to true north
#endif
				KEY_HEADING_X: DBINVALID_HEADING,
				KEY_HEADING_Y: DBINVALID_HEADING,
				KEY_HEADING_Z: DBINVALID_HEADING,
#ifdef INCLUDE_HEADING_HASH
				KEY_HEADING_UPDATE_HASH: DBINVALID_HASH
#endif
				};
//				@"headingUpdateTimestamp": DBINVALID_TIMESTAMP};
}

// --------------------------------------------------------------
// Change thresholds
// --------------------------------------------------------------

NSDictionary* changeThreshsDictMotion() {
	return @{	KEY_GRAV_X: THRESH_ACCEL,
				KEY_GRAV_Y: THRESH_ACCEL,
				KEY_GRAV_Z: THRESH_ACCEL,
				KEY_USR_X: THRESH_ACCEL,
				KEY_USR_Y: THRESH_ACCEL,
				KEY_USR_Z: THRESH_ACCEL,
				KEY_ROLL:  THRESH_ATTITUDE,
				KEY_PITCH: THRESH_ATTITUDE,
				KEY_YAW:   THRESH_ATTITUDE,
				KEY_GYRO_X: THRESH_GYRO,
				KEY_GYRO_Y: THRESH_GYRO,
				KEY_GYRO_Z: THRESH_GYRO,
				KEY_MAG_ACC: THRESH_ACC_MAG,
				KEY_MAG_X: THRESH_MAG,
				KEY_MAG_Y: THRESH_MAG,
				KEY_MAG_Z: THRESH_MAG};
}

NSDictionary* changeThreshsDictLocation() {
	return @{	KEY_LATITUDE : THRESH_LATLON,
				KEY_LONGITUDE: THRESH_LATLON,
				KEY_ALTITUDE : THRESH_ALTITUDE,
				KEY_HORIZONTAL_ACC: THRESH_ACC_LOC,
				KEY_VERTICAL_ACC: THRESH_ACC_LOC,
#ifndef ANONYMIZE
				KEY_BUILDING_FLOOR: THRESH_FLOOR,
#endif
				KEY_COURSE: THRESH_DEGREES_ANGLE,
				KEY_SPEED: THRESH_SPEED};
}

NSDictionary* changeThreshsDictHeading() {
	return @{	KEY_HEADING_ACC:  THRESH_ACC_HEADING,
				KEY_MAG_HEADING:  THRESH_DEGREES_ANGLE,	//to magnetic north
#ifndef ANONYMIZE
				KEY_TRUE_HEADING: THRESH_DEGREES_ANGLE,	//to true north
#endif
				KEY_HEADING_X: THRESH_MAG_HEADING,
				KEY_HEADING_Y: THRESH_MAG_HEADING,
				KEY_HEADING_Z: THRESH_MAG_HEADING};
}

// --------------------------------------------------------------
// Dicts from sensor readings
// --------------------------------------------------------------

NSDictionary* dictFromMotion(CMDeviceMotion* motion) {
	BOOL magValid = motionHasValidMagField(motion);
	return @{	KEY_GRAV_X: @(motion.gravity.x),
				KEY_GRAV_Y: @(motion.gravity.y),
				KEY_GRAV_Z: @(motion.gravity.z),
				KEY_USR_X: @(motion.userAcceleration.x),
				KEY_USR_Y: @(motion.userAcceleration.y),
				KEY_USR_Z: @(motion.userAcceleration.z),
				KEY_ROLL:  @(motion.attitude.roll),
				KEY_PITCH: @(motion.attitude.pitch),
				KEY_YAW:   @(motion.attitude.yaw),
				KEY_GYRO_X: @(motion.rotationRate.x),
				KEY_GYRO_Y: @(motion.rotationRate.y),
				KEY_GYRO_Z: @(motion.rotationRate.z),
				KEY_MAG_ACC: magValid ? @(motion.magneticField.accuracy) : DBINVALID_ACCURACY_MAG,
				KEY_MAG_X: magValid ? @(motion.magneticField.field.x) : DBINVALID_MAG,
				KEY_MAG_Y: magValid ? @(motion.magneticField.field.y) : DBINVALID_MAG,
				KEY_MAG_Z: magValid ? @(motion.magneticField.field.z) : DBINVALID_MAG,
#ifdef INCLUDE_MOTION_HASH
				KEY_MOTION_UPDATE_HASH: @(hashTimeStamp(currentTimeStampMs()))
#endif
				};
				//this would be slightly better, but it's not clear that it works...
//				@"motionUpdateTimestamp": @(timeStampFromCoreMotionTimeStamp(motion.timestamp))};
}

NSDictionary* dictFromLocation(CLLocation* location) {
	if (! locationValid(location) ) {
		return defaultsDictLocation();
	}

	double lat = location.coordinate.latitude;
	double lon = location.coordinate.latitude;
	double alt = location.altitude;
	long floor = location.floor.level;
#ifdef ANONYMIZE
	lat = anonLatitude(lat, lon);
	lon = anonLongitude(lat, lon);
	alt = anonAltitude(alt);
	floor = NAN;
#endif
	// note that we turn the latitude and longitude into strings so that we
	// can ensure full precision regardless of any subsequent quantization
	// in logging; this is kind of a hack since anyone trying to use the
	// data directly, rather than log it as a string, would get a pretty
	// strange surprise. We use 6 decimal places since this yields ~.5ft of
	// location accuracy (since it's given in degrees) and is thus probably
	// more accurate than the GPS is anyway
	return @{
				KEY_LATITUDE : [NSString stringWithFormat:@"%6f", lat],
				KEY_LONGITUDE: [NSString stringWithFormat:@"%6f", lon],
				KEY_ALTITUDE : @((int)alt),
				KEY_HORIZONTAL_ACC: @((int)location.horizontalAccuracy),
				KEY_VERTICAL_ACC:	@((int)location.verticalAccuracy),
#ifndef ANONYMIZE
				KEY_BUILDING_FLOOR: @(floor),
#endif
				KEY_COURSE: @(location.course),
				KEY_SPEED: @(location.speed),
				KEY_LOCATION_UPDATE_HASH: @(hashTimeStamp(timeStampFromDate(location.timestamp)))};
//				@"locationUpdateTimestamp": @(timeStampFromDate(location.timestamp))};
}

NSDictionary* dictFromHeading(CLHeading* heading) {
	if (! headingValid(heading) ) {
		return defaultsDictHeading();
	}
//	double trueHeading = heading.trueHeading;
//#ifdef ANONYMIZE
//	trueHeading = NAN;
//#endif
	return @{	KEY_HEADING_ACC:  @((int)heading.headingAccuracy),
				KEY_MAG_HEADING: @((int)heading.magneticHeading),	//to magnetic north
#ifndef ANONYMIZE
				KEY_TRUE_HEADING:@((int)heading.trueHeading),		//to true north
#endif
				KEY_HEADING_X: @((int)heading.x),
				KEY_HEADING_Y: @((int)heading.y),
				KEY_HEADING_Z: @((int)heading.z),
#ifdef INCLUDE_HEADING_HASH
				KEY_HEADING_UPDATE_HASH: @(hashTimeStamp(timeStampFromDate(heading.timestamp)))
#endif
				};
//				@"headingUpdateTimestamp": @(timeStampFromDate(heading.timestamp))};
}

NSDictionary* allSensorDefaultsDict() {
	NSMutableDictionary* dict = [NSMutableDictionary dictionary];
	[dict addEntriesFromDictionary:defaultsDictMotion()];
	[dict addEntriesFromDictionary:defaultsDictLocation()];
	[dict addEntriesFromDictionary:defaultsDictHeading()];
	return dict;
}

//================================================================
// DBSensorMonitor
//================================================================

@interface DBSensorMonitor () <CLLocationManagerDelegate>

@property(strong, nonatomic) CLLocationManager* locationManager;
@property(strong, nonatomic) CMMotionManager* motionManager;
@property(strong, nonatomic) NSOperationQueue* queue;

@property(strong, atomic) NSMutableDictionary* prevDataMotion;
@property(strong, atomic) NSMutableDictionary* prevDataLocation;
@property(strong, atomic) NSMutableDictionary* prevDataHeading;

@property(strong, nonatomic) NSObject* lockMotion;
@property(strong, nonatomic) NSObject* lockLocation;
@property(strong, nonatomic) NSObject* lockHeading;

@end

@implementation DBSensorMonitor

//--------------------------------------------------------------
// public methods
//--------------------------------------------------------------

//-------------------------------
// initialization
//-------------------------------

-(instancetype) initWithDataReceivedHandler:(void (^)(NSDictionary* data, timestamp_t timestamp))handler {
#ifdef ANONYMIZE
	initAnonymizing();
#endif
	if (self = [super init]) {
		_onDataReceived = handler;
		_sendOnlyIfDifferent = NO;
		[self initSensing];
		
		_prevDataMotion = [NSMutableDictionary dictionary];
		_prevDataLocation = [NSMutableDictionary dictionary];
		_prevDataHeading = [NSMutableDictionary dictionary];
		
		_lockMotion = [[NSObject alloc] init];
		_lockLocation = [[NSObject alloc] init];
		_lockHeading = [[NSObject alloc] init];
	}
	return self;
}

-(instancetype) init {
	return [self initWithDataReceivedHandler:nil];
}

-(void) initSensing {
	_locationManager = [[CLLocationManager alloc] init];
	_locationManager.delegate = self;
	_locationManager.desiredAccuracy = kCLLocationAccuracyBest;
	[_locationManager startUpdatingLocation];
	_locationManager.headingFilter = THRESH_DEGREES_ANGLE_DBL;	// don't even send the events
	[_locationManager startUpdatingHeading];

	_queue = [[NSOperationQueue alloc] init];
	_motionManager = [[CMMotionManager alloc] init];

	_motionManager.deviceMotionUpdateInterval = kMotionSamplingPeriod;
	[_motionManager startDeviceMotionUpdatesToQueue:_queue
	withHandler:^(CMDeviceMotion *motion, NSError *error) {
		[self sendMotion:motion];
   }];
}

//-------------------------------
// polling
//-------------------------------

-(void) pollLocation {
	[self sendLocation:_locationManager.location];
	[self sendHeading:_locationManager.heading];
}

-(void) pollMotion {
	[self sendMotion:_motionManager.deviceMotion];
}

-(void) poll {
	[self pollLocation];
	[self pollMotion];
}

//--------------------------------------------------------------
// private methods
//--------------------------------------------------------------

-(void) sendData:(NSDictionary*)data withTime:(timestamp_t)t {
	if (_onDataReceived && [data count]) {
		_onDataReceived(data, t);
	}
}

-(void) sendMotionData:(NSDictionary*)data withTime:(timestamp_t)time {
	if (_sendOnlyIfDifferent) {
		@synchronized(_lockMotion) {
			NSDictionary* changes = extractChanges(_prevDataMotion,
												   data,
												   changeThreshsDictMotion());
			[_prevDataMotion addEntriesFromDictionary:changes];
			[self sendData:changes withTime:time];
		}
	} else {
//		NSLog(@"sending motion data: %@", data);
		[self sendData:data withTime:time];
	}
}

-(void) sendLocationData:(NSDictionary*)data withTime:(timestamp_t)time {
	if (_sendOnlyIfDifferent) {
		@synchronized(_lockLocation) {
			NSDictionary* changes = extractChanges(_prevDataLocation,
												   data,
												   changeThreshsDictLocation());
			[_prevDataLocation addEntriesFromDictionary:changes];
			[self sendData:changes withTime:time];
		}
	} else {
		[self sendData:data withTime:time];
	}
}

-(void) sendHeadingData:(NSDictionary*)data withTime:(timestamp_t)time {
	if (_sendOnlyIfDifferent) {
		@synchronized(_lockHeading) {
			NSDictionary* changes = extractChanges(_prevDataHeading,
												   data,
												   changeThreshsDictHeading());
			[_prevDataHeading addEntriesFromDictionary:changes];
			[self sendData:changes withTime:time];
		}
	} else {
		[self sendData:data withTime:time];
	}
}

-(void) sendMotion:(CMDeviceMotion *)motion {
	NSDictionary* data = dictFromMotion(motion);
	//this would sort of be better, but it's ~1s off
//	timestamp_t t = timeStampFromCoreMotionTimeStamp(motion.timestamp);
	timestamp_t t = currentTimeStampMs();
	[self sendMotionData:data withTime:t];
}

-(void) sendLocation:(CLLocation *)location {
	NSDictionary* data = dictFromLocation(location);
	timestamp_t t = timeStampFromDate(location.timestamp);
	[self sendLocationData:data withTime:t];
}

-(void) sendHeading:(CLHeading *)heading {
	NSDictionary* data = dictFromHeading(heading);
	timestamp_t t = timeStampFromDate(heading.timestamp);
	[self sendHeadingData:data withTime:t];
}

//-------------------------------
// Sensor callbacks
//-------------------------------

-(void)locationManager:(CLLocationManager *)manager
   didUpdateToLocation:(CLLocation *)newLocation
		  fromLocation:(CLLocation *)oldLocation {
	[self pollMotion];		// ensure this still gets updated if app in bg
	[self sendLocation:newLocation];
}

-(void)locationManager:(CLLocationManager *)manager
	   didUpdateHeading:(CLHeading *)newHeading {
	[self pollMotion];		// ensure this still gets updated if app in bg
	[self sendHeading:newHeading];
}

@end
