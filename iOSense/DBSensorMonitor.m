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

// TODO option to only log significant changes from last thing that was logged
	//have to store last thing that was logged

#import "DBSensorMonitor.h"

#import <CoreMotion/CoreMotion.h>
#import <CoreLocation/CoreLocation.h>
#import "TimeUtils.h"

#define ANONYMIZE

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
// Constants
//================================================================

// utility consts
static const double RADS_PER_DEGREE = M_2_PI / 360.0;
static const double METERS_PER_DEGREE_LAT = 111130;	// approx, depends on lat
static const double DEGREES_PER_METER = 1.0 / METERS_PER_DEGREE_LAT;

// general thresholds
static const double THRESH_DEGREES_ANGLE = 15.0;
static const double THRESH_RADS_ANGLE = THRESH_DEGREES_ANGLE * RADS_PER_DEGREE;

// motion thresholds
static const double THRESH_GRAV = (1.0 / 32);	// g
static const double THRESH_ATTITUDE = 15;		// deg
static const double THRESH_GYRO = (1.0 / 32);	// rad/s	//TODO
static const double THRESH_MAG = 15;			// unknown unit

// location thresholds
static const double THRESH_LATLON = 3 * DEGREES_PER_METER;	// deg
static const double THRESH_ALTITUDE = 3;					// m
static const double THRESH_SPEED = .25;						// m/s

// heading thresholds
static const double THRESH_MAG_HEADING = 5;		// uTesla	//TODOs

// sampling rate (don't ask why this is the only one following
// the objc naming convention...)
static const float kMotionSamplingPeriod = .05;	//20Hz

//-------------------------------
// Data keys
//-------------------------------

// motion
NSString *const KEY_GRAV_X = @"gravX";	// accel due to gravity, g
NSString *const KEY_GRAV_Y = @"gravY";	// accel due to gravity, g
NSString *const KEY_GRAV_Z = @"gravZ";	// accel due to gravity, g
NSString *const KEY_USR_X = @"usrX";	// accel due to user, g
NSString *const KEY_USR_Y = @"usrX";	// accel due to user, g
NSString *const KEY_USR_Z = @"usrX";	// accel due to user, g
NSString *const KEY_ROLL  = @"roll";	// rad
NSString *const KEY_PITCH = @"pitch";	// rad
NSString *const KEY_YAW	  = @"yaw";		// rad
NSString *const KEY_GYRO_X = @"gyroX";	// rad/s
NSString *const KEY_GYRO_Y = @"gyroY";	// rad/s
NSString *const KEY_GYRO_Z = @"gyroZ";	// rad/s
NSString *const KEY_MAG_ACC = @"magAcc";// {uncalibrated, low, med, high}
NSString *const KEY_MAG_X = @"magX";	// (undocumented unit, perhaps degrees)
NSString *const KEY_MAG_Y = @"magY";	// (undocumented unit, perhaps degrees)
NSString *const KEY_MAG_Z = @"magZ";	// (undocumented unit, perhaps degrees)
NSString *const KEY_MOTION_UPDATE_HASH = @"motHash"; // 0-999 value identifying an update

// location
NSString *const KEY_LATITUDE  = @"lat";					// deg
NSString *const KEY_LONGITUDE = @"lon";					// deg
NSString *const KEY_ALTITUDE = @"alt";					// m
NSString *const KEY_HORIZONTAL_ACC = @"horzAcc";		// m
NSString *const KEY_VERTICAL_ACC   = @"vertAcc";		// m
NSString *const KEY_BUILDING_FLOOR = @"floor";			// int, floor number
NSString *const KEY_COURSE = @"course";					// deg
NSString *const KEY_SPEED = @"speed";					// m/s
NSString *const KEY_LOCATION_UPDATE_HASH = @"locHash";	// 0-999 value identifying an update

// heading
NSString *const KEY_HEADING_ACC = @"headAcc";	// deg
NSString *const KEY_MAG_HEADING  = @"magHead";	// deg
NSString *const KEY_TRUE_HEADING = @"truHead";	// deg
NSString *const KEY_HEADING_X = @"headX";		// (uTesla)
NSString *const KEY_HEADING_Y = @"headY";		// (uTesla)
NSString *const KEY_HEADING_Z = @"headZ";		// (uTesla)
NSString *const KEY_HEADING_UPDATE_HASH  = @"headHash";	// 0-999 value identifying an update

//================================================================
// Utility funcs
//================================================================

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

int hashTimeStamp(timestamp_t t) {
	return t % 1000;
}

static BOOL changeAboveThresh(double old, double new, double thresh) {
	return fabs(old - new) >= thresh;
}

//================================================================
// Dictionary creation funcs
//================================================================

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
				KEY_MOTION_UPDATE_HASH: DBINVALID_HASH};
//				@"motionUpdateTimestamp": DBINVALID_TIMESTAMP};
}

NSDictionary* defaultsDictLocation() {
	return @{	KEY_LATITUDE : DBINVALID_ANGLE,
				KEY_LONGITUDE: DBINVALID_ANGLE,
				KEY_ALTITUDE : DBINVALID_DISTANCE,
				KEY_HORIZONTAL_ACC: DBINVALID_ACCURACY_LOC,
				KEY_VERTICAL_ACC: DBINVALID_ACCURACY_LOC,
				KEY_BUILDING_FLOOR: DBINVALID_FLOOR,
				KEY_COURSE: DBINVALID_ANGLE,
				KEY_SPEED: DBINVALID_SPEED,
				KEY_LOCATION_UPDATE_HASH: DBINVALID_HASH};
//				@"locationUpdateTimestamp": DBINVALID_TIMESTAMP};
}

NSDictionary* defaultsDictHeading() {
	return @{	KEY_HEADING_ACC:  DBINVALID_ACCURACY_HEADING,
				KEY_MAG_HEADING:  DBINVALID_ANGLE,	//to magnetic north
				KEY_TRUE_HEADING: DBINVALID_ANGLE,	//to true north
				KEY_HEADING_X: DBINVALID_HEADING,
				KEY_HEADING_Y: DBINVALID_HEADING,
				KEY_HEADING_Z: DBINVALID_HEADING,
				KEY_HEADING_UPDATE_HASH: DBINVALID_HASH};
//				@"headingUpdateTimestamp": DBINVALID_TIMESTAMP};
}

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
				KEY_MOTION_UPDATE_HASH: @(hashTimeStamp(currentTimeStampMs()))};
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
				KEY_BUILDING_FLOOR: @(floor),
				KEY_COURSE: @(location.course),
				KEY_SPEED: @(location.speed),
				KEY_LOCATION_UPDATE_HASH: @(hashTimeStamp(timeStampFromDate(location.timestamp)))};
//				@"locationUpdateTimestamp": @(timeStampFromDate(location.timestamp))};
}

NSDictionary* dictFromHeading(CLHeading* heading) {
	if (! headingValid(heading) ) {
		return defaultsDictHeading();
	}
	double trueHeading = heading.trueHeading;
#ifdef ANONYMIZE
	trueHeading = NAN;
#endif
	return @{	KEY_HEADING_ACC:  @((int)heading.headingAccuracy),
				KEY_MAG_HEADING: @((int)heading.magneticHeading),	//to magnetic north
				KEY_TRUE_HEADING:@((int)trueHeading),				//to true north
				KEY_HEADING_X: @((int)heading.x),
				KEY_HEADING_Y: @((int)heading.y),
				KEY_HEADING_Z: @((int)heading.z),
				KEY_HEADING_UPDATE_HASH: @(hashTimeStamp(timeStampFromDate(heading.timestamp)))};
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
		[self initSensing];
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
	[_locationManager startUpdatingHeading];

	_queue = [[NSOperationQueue alloc] init];
	_motionManager = [[CMMotionManager alloc] init];

	_motionManager.deviceMotionUpdateInterval = kMotionSamplingPeriod;
	[_motionManager startDeviceMotionUpdatesToQueue:_queue
	withHandler:^(CMDeviceMotion *motion, NSError *error) {
		NSDictionary* data = dictFromMotion(motion);
		timestamp_t t = timeStampFromCoreMotionTimeStamp(motion.timestamp);
		[self sendData:data withTime:t];
   }];
}

//-------------------------------
// polling
//-------------------------------

-(void) pollLocation {
	NSMutableDictionary* data = [NSMutableDictionary dictionary];
	if (locationValid(_locationManager.location)) {
		[data addEntriesFromDictionary:dictFromLocation(_locationManager.location)];
	}
	if (headingValid(_locationManager.heading)) {
		[data addEntriesFromDictionary:dictFromHeading(_locationManager.heading)];
	}
	if ([data count]) {
		[self sendData:data withTime:currentTimeStampMs()];
	}
}

-(void) pollMotion {
	timestamp_t t = currentTimeStampMs();
	NSDictionary* data = dictFromMotion(_motionManager.deviceMotion);
	[self sendData:data withTime:t];
}

-(void) poll {
	[self pollLocation];
	[self pollMotion];
}

//--------------------------------------------------------------
// private methods
//--------------------------------------------------------------

-(void) sendData:(NSDictionary*)data withTime:(timestamp_t)t {
	if (_onDataReceived) {
		_onDataReceived(data, t);
	}
}

//-------------------------------
// Sensor callbacks
//-------------------------------

-(void)locationManager:(CLLocationManager *)manager
   didUpdateToLocation:(CLLocation *)newLocation
		  fromLocation:(CLLocation *)oldLocation{
	NSDictionary* data = dictFromLocation(newLocation);
	timestamp_t t = timeStampFromDate(newLocation.timestamp);
	[self pollMotion];		// ensure this still gets updated if app in bg
	[self sendData:data withTime:t];
}

-(void)locationManager:(CLLocationManager *)manager
	   didUpdateHeading:(CLHeading *)newHeading {
	NSDictionary* data = dictFromHeading(newHeading);
	timestamp_t t = timeStampFromDate(newHeading.timestamp);
	[self pollMotion];		// ensure this still gets updated if app in bg
	[self sendData:data withTime:t];
}

@end
