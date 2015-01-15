//
//  ViewController.m
//  DisplayAcc
//
//  Created by D Blalock on 1/2/15.
//  Copyright (c) 2014 D Blalock. All rights reserved.
//

#import "ViewController.h"

#import <MessageUI/MessageUI.h>

#import "SHCTableViewCell.h"
#import "Labels.h"
#import "DBDataLogger.h"
#import "DBSensorMonitor.h"
#import "GraphView.h"
#import "FileUtils.h"
#import "TimeUtils.h"

// not string consts since it's irrelevant what type they are, and nothing
// should assume that they're strings (plus I've already typed this)
#define KEY_WATCH_X @"pebbleX (g)"
#define KEY_WATCH_Y @"pebbleY (g)"
#define KEY_WATCH_Z @"pebbleZ (g)"
#define KEY_USER_ID	@"userId"
#define KEY_TAGS	@"labels"
#define DEFAULT_VALUE_ACCEL DBINVALID_ACCEL
#define DEFAULT_VALUE_USER @"users/__UNKNOWN__"
#define DEFAULT_VALUE_TAGS @"None"

#define ALL_LOCAL_KEYS (@[KEY_WATCH_X, KEY_WATCH_Y, KEY_WATCH_Z, KEY_USER_ID, KEY_TAGS]);
#define ALL_LOCAL_DEFAULT_VALUES (@[DEFAULT_VALUE_ACCEL, DEFAULT_VALUE_ACCEL, DEFAULT_VALUE_ACCEL, DEFAULT_VALUE_USER, DEFAULT_VALUE_TAGS]);

static const NSUInteger PEBBLE_ACCEL_HZ = 20;
static const NSUInteger PEBBLE_ACCEL_PERIOD = 1000 / PEBBLE_ACCEL_HZ;

static const NSUInteger DATALOGGING_HZ = 20;
static const NSUInteger DATALOGGING_PERIOD_MS = 1000 / DATALOGGING_HZ;

//static const uint8_t KEY_TRANSACTION_ID = 0x1;
static const uint8_t KEY_NUM_BYTES		= 0x2;
static const uint8_t KEY_DATA           = 0x3;

NSDictionary* combinedDefaultsDict() {
	NSArray* localKeys = ALL_LOCAL_KEYS;
	NSArray* localVals = ALL_LOCAL_DEFAULT_VALUES;
	NSMutableDictionary* dict = [NSMutableDictionary
									  dictionaryWithObjects:localVals
									  forKeys:localKeys];
	[dict addEntriesFromDictionary:allSensorDefaultsDict()];
	return dict;
}

NSArray* allDataKeys() {
	// sort stuff for consistency across runs
	return [[combinedDefaultsDict() allKeys] sortedArrayUsingSelector: @selector(compare:)];
}

NSArray* allDataDefaultValues() {
	NSDictionary* dict = combinedDefaultsDict();
	NSMutableArray* values = [NSMutableArray array];
	for (id key in allDataKeys()) {
		[values addObject:[dict valueForKey:key]];
	}
	return values;
}


//===============================================================
//===============================================================
// Interface
//===============================================================
//===============================================================
@interface ViewController () <PBPebbleCentralDelegate, UITextFieldDelegate,
	UITableViewDataSource, UITableViewDelegate>

//--------------------------------
// Non-View properties
//--------------------------------

@property (strong, nonatomic) PBWatch *myWatch;
@property (strong, nonatomic) NSString *savePath;
@property (strong, nonatomic) NSOutputStream *stream;

@property (strong, nonatomic) NSDictionary *labelsDict;
@property (strong, nonatomic) NSMutableSet *activeLabels;
@property (strong, nonatomic) NSMutableArray *currentLabels0;
@property (strong, nonatomic) NSMutableArray *currentLabels1;
@property (strong, nonatomic) NSIndexPath *selectedLabelIdx0;

@property (strong, nonatomic) NSTimer *tapTimer;	//for double taps

@property (strong, nonatomic) DBDataLogger* dataLogger;
@property (strong, nonatomic) DBSensorMonitor* sensorMonitor;

@property (readwrite) BOOL launchedApp;
@property (readwrite) BOOL recording;

//--------------------------------
// View properties
//--------------------------------

@property (weak, nonatomic) IBOutlet UITextField *userIdText;

@property (weak, nonatomic) IBOutlet UILabel *activeLabelsLbl;

@property (weak, nonatomic) IBOutlet UITextField *customText;
@property (weak, nonatomic) IBOutlet UISwitch *customSwitch;

@property (weak, nonatomic) IBOutlet UIScrollView *tablesScrollView;
@property (weak, nonatomic) IBOutlet UITableView *labelTable0;
@property (weak, nonatomic) IBOutlet UITableView *labelTable1;
@property (weak, nonatomic) IBOutlet UITableView *labelTable2;

//@property (strong, nonatomic) IBOutlet UIStepper *actionNumberStepper;
//@property (strong, nonatomic) IBOutlet UITextField *actionNumberText;

@property (nonatomic, strong) IBOutlet GraphView *dataGraph;

@property (nonatomic, strong) IBOutlet UIButton *startButton;
@property (nonatomic, strong) IBOutlet UIButton *stopButton;
@property (nonatomic, strong) IBOutlet UIButton *deleteButton;

@end


//===============================================================
//===============================================================
// Implementation
//===============================================================
//===============================================================
@implementation ViewController

//===============================================================
#pragma mark View Controller
//===============================================================

- (void)viewDidLoad {
    [super viewDidLoad];
	
	// background img
//	self.view.backgroundColor = [UIColor colorWithPatternImage: [UIImage imageNamed:@"inflicted.png"]];
	self.view.backgroundColor = [UIColor colorWithPatternImage: [UIImage imageNamed:@"light_honeycomb.png"]];
	
	// not-as-hideous tableview cells
	for (UITableView* table in @[_labelTable0, _labelTable1, _labelTable2]) {
		[table registerClass:[SHCTableViewCell class] forCellReuseIdentifier:@"gradientCell"];
		table.layer.cornerRadius = 4;
	}
	
	// make it actually scroll
	_tablesScrollView.contentSize = CGSizeMake(480, 150);
	
	// state flags
	_launchedApp = NO;
	_recording = NO;
	
	// labels for time periods
	_activeLabels = [NSMutableSet set];
	_labelsDict = createLabelNamesDict();
	_currentLabels0 = getTopLevelLabelNames();
	_currentLabels1 = [NSMutableArray array];
	
	// data logging
	_dataLogger = [[DBDataLogger alloc] initWithSignalNames:allDataKeys()
											  defaultValues:allDataDefaultValues()
											   samplePeriod:DATALOGGING_PERIOD_MS];
	_dataLogger.autoFlushLagMs = 2000;	//write every 2s
	_dataLogger.logSubdir = [self userIdOrDefaultValue];
	_sensorMonitor = [[DBSensorMonitor alloc] initWithDataReceivedHandler:^
		void(NSDictionary *data, timestamp_t timestamp) {
			dispatch_async(dispatch_get_main_queue(), ^{	//main thread
				[_dataLogger logData:data withTimeStamp:timestamp];
			});
		}
	];

	// pebble connection + callbacks
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		[self setupPebble];
	});
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
	[self.view endEditing:YES];
}

//===============================================================
#pragma mark Logging Stuff
//===============================================================

- (void)plotAccelX:(int8_t)x Y:(int8_t)y Z:(int8_t)z {
	[_dataGraph addX:(x/64.0) y:(y/64.0) z:(z/64.0)];
}

- (NSString*)generateFileName {
	NSString* fileName = [NSString stringWithFormat:@"%@_%@_%@",
						  [_userIdText text],
						  [_customText text],
						  currentTimeStr()];
//						  [_actionNumberText text],
//						  currentTimeMs()];
	return [FileUtils getFullFileName:fileName];
}

//- (void)openDataStream {
//	_savePath = [self generateFileName];
//	_stream = [[NSOutputStream alloc] initToFileAtPath:_savePath append:NO];
//	[_stream open];
//}
//
//- (void)closeDataStream {
//	[_stream close];
//}
//
//- (void)writeAccelX:(int8_t)x Y:(int8_t)y Z:(int8_t)z {
//	NSString* xyz = [NSString stringWithFormat:@"%hhd %hhd %hhd\n", x, y, z];
//	NSData *data = [xyz dataUsingEncoding:NSUTF8StringEncoding];
//	[_stream write:data.bytes maxLength:data.length];
//}

-(void) logAccelX:(int8_t)x Y:(int8_t)y Z:(int8_t)z timeStamp:(timestamp_t)sampleTime {
	NSDictionary* kvPairs = @{KEY_WATCH_X: @(x / 64.0),
							  KEY_WATCH_Y: @(y / 64.0),
							  KEY_WATCH_Z: @(z / 64.0)};
	[_dataLogger logData:kvPairs withTimeStamp:sampleTime];
}

-(void) logTags:(NSString*)tags andUser:(NSString*)userId timeStamp:(timestamp_t)sampleTime {
	NSDictionary* kvPairs = @{KEY_TAGS:		[tags length] ? tags : DEFAULT_VALUE_TAGS,
							  KEY_USER_ID:	[userId length] ? userId : DEFAULT_VALUE_USER};
	[_dataLogger logData:kvPairs withTimeStamp:sampleTime];
}

-(void) logCurrentTagsAndUser:(timestamp_t)timestamp {
	NSString* tags = [self sanitizedActiveLabelsAsCsvStr];
	NSString* userId = [self readUserId];
	[self logTags:tags andUser:userId timeStamp:timestamp];
}

-(void) logCurrentTagsAndUser {
	[self logCurrentTagsAndUser:currentTimeStampMs()];
}

- (BOOL)logUpdate:(NSDictionary*)update fromWatch:(PBWatch*)watch {
	if (! _recording) return NO;

//	int transactionId = (int) [[update objectForKey:@(KEY_TRANSACTION_ID)] integerValue];
	int numBytes = (int) [[update objectForKey:@(KEY_NUM_BYTES)] integerValue];
	NSData* accelData = [update objectForKey:@(KEY_DATA)];
	const int8_t* dataAr = (const int8_t*) [accelData bytes];

	// compute start time of this buffer
	uint numSamples = numBytes / 3;
	uint bufferDuration = (numSamples - 1) * PEBBLE_ACCEL_PERIOD;
	timestamp_t startTime = currentTimeStampMs() - bufferDuration;
	
	// ensure tags / user are up to date (shouldn't be necessary
	// here, but might as well)
	[self logCurrentTagsAndUser:startTime];

	int8_t x, y, z;
	timestamp_t sampleTime;
	for (int i = 0; i < numBytes; i += 3) {
		x = dataAr[i];
		y = dataAr[i+1];
		z = dataAr[i+2];
		
		// logging
		sampleTime = startTime + i * PEBBLE_ACCEL_PERIOD;
		[self logAccelX:x Y:y Z:z timeStamp:sampleTime];

		//displaying
		[self plotAccelX:x Y:y Z:z];
	}
	return YES;
}

//===============================================================
#pragma mark State management
//===============================================================

//--------------------------------
// action number
//--------------------------------

//- (NSInteger)readActionNumber {
//	return round([_actionNumberStepper value]);
//}
//
//- (void)setActionNumber:(NSInteger)num {
//	NSString* valueStr = [NSString stringWithFormat:@"%d", num];
//	[_actionNumberText setText:valueStr];
//}
//
//- (void)refreshActionNumber {
//	[self setActionNumber:[self readActionNumber]];
//}

//--------------------------------
// text fields
//--------------------------------

NSString* sanitizeTagForCsv(NSString* str) {
	NSString* s = [str stringByReplacingOccurrencesOfString:@" " withString:@"-"];
	return [s stringByReplacingOccurrencesOfString:@"," withString:@";"];
}

NSArray* sanitizeTagsForCsv(NSArray* ar) {
	NSMutableArray* sanitized = [NSMutableArray arrayWithArray:ar];
	for (int i = 0; i < [ar count]; i++) {
		sanitized[i] = sanitizeTagForCsv(ar[i]);
	}
	return sanitized;
}

- (NSString*) userIdOrDefaultValue {
	NSString* userId = [self readUserId];
	return [userId length] ? userId : DEFAULT_VALUE_USER;
}

- (NSString*) readUserId {
	return sanitizeTagForCsv([[self userIdText] text]);
}

//sanitized for csv
- (NSString*) readCustomLabel {
	NSString* txt = [[self customText] text];
	return [txt stringByReplacingOccurrencesOfString:@"," withString:@";"];
}

//--------------------------------
// Active labels data model
//--------------------------------

- (BOOL) isLabelActive:(NSString*)label {
	return [_activeLabels containsObject:label];
}

- (void) setLabelActive:(NSString*)label {
	[_activeLabels addObject:label];
	[self showActiveLabels];
}

- (void) setLabelInactive:(NSString*)label {
	[_activeLabels removeObject:label];
	[self showActiveLabels];
}

-(void) toggleLabelActive:(NSString*)lbl {
	if ([self isLabelActive:lbl]) {
		[self setLabelInactive:lbl];
	} else {
		[self setLabelActive:lbl];
	}
}

//--------------------------------
// Active labels UI
//--------------------------------

-(NSArray*) sanitizedActiveLabels {
	return sanitizeTagsForCsv([_activeLabels allObjects]);
}

-(NSString*) sanitizedActiveLabelsAsCsvStr {
	NSArray* sanitized = [self sanitizedActiveLabels];
	NSArray* sorted = [sanitized sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
	return [sorted componentsJoinedByString:@" "];
}

-(void) showActiveLabels {
	NSString* txt = [self sanitizedActiveLabelsAsCsvStr];
	if (! txt) {
		txt = @"None";
	}
	[_activeLabelsLbl setText:txt];
}

#define ACTIVE_COLOR ([UIColor greenColor])
#define INACTIVE_COLOR ([UIColor lightGrayColor])
void setCellActive(UITableViewCell* cell) {
	[cell setBackgroundColor:ACTIVE_COLOR];
	cell.textLabel.textColor = [UIColor whiteColor];
//	UIImage* img = [UIImage imageNamed:@"green_checkmark.png"];
//	cell.imageView.image = img;
	[cell setSelected:NO];
//	cell.accessoryType = UITableViewCellAccessoryCheckmark;
}

void setCellInActive(UITableViewCell* cell) {
	[cell setBackgroundColor:INACTIVE_COLOR];
	cell.textLabel.textColor = [UIColor blackColor];
//	cell.imageView.image = nil;
	[cell setSelected:NO];
//		cell.accessoryType = UITableViewCellAccessoryNone;
}

-(void) updateAppearanceOfCell:(UITableViewCell*)cell withLabel:(NSString*)lbl {
	if ([self isLabelActive:lbl]) {
		setCellActive(cell);
	} else {
		setCellInActive(cell);
	}
}

//===============================================================
#pragma mark IBActions
//===============================================================

//--------------------------------
// data recording
//--------------------------------

- (IBAction)startRecordingData:(id)sender {
	_recording = YES;
	[_dataGraph reset];
	if (! _launchedApp) {
		[self startWatchApp];
	}
	[_dataLogger startLog];
	[self logCurrentTagsAndUser];
	[_sensorMonitor poll];			// try to update location, etc
	[_startButton setEnabled:NO];
	[_stopButton setEnabled:YES];
	[_deleteButton setEnabled:NO];
	NSLog(@"Started recording.");
}

- (IBAction)stopRecordingData:(id)sender {
	_recording = NO;
	[_dataLogger endLog];
	[_startButton setEnabled:YES];
	[_stopButton setEnabled:NO];
	[_deleteButton setEnabled:YES];
	NSLog(@"Stopped recording.");
//	[[self actionNumberStepper] setValue:([self readActionNumber] + 1)];
//	[self refreshActionNumber];
}

- (IBAction)deleteLastFile:(id)sender {
	if (! _recording) {
		[_dataLogger deleteLog];
//		[FileUtils deleteFile:_savePath];
		[_dataGraph reset];
	}
	[_deleteButton setEnabled:NO];
}

//--------------------------------
// action number
//--------------------------------

//-(IBAction)actionNumberChanged:(id)sender {
//	[self refreshActionNumber];
//}

//--------------------------------
// custom labels
//--------------------------------

- (IBAction)toggleCustomLabel:(id)sender {
	if ([sender isOn]) {
		[self setLabelActive:[self readCustomLabel]];
		[self logCurrentTagsAndUser];
	} else {
		[self setLabelInactive:[self readCustomLabel]];
	}
}


//===============================================================
#pragma mark Pebble
//===============================================================

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
	[self setPebbleUUID:@"00674CB5-AFEE-464D-B791-5CDBA233EA93"];
	self.myWatch = [[PBPebbleCentral defaultCentral] lastConnectedWatch];
	NSLog(@"Last connected watch: %@", self.myWatch);
}

- (void)startWatchApp {
	if (_launchedApp) return;	//only do this once
	_launchedApp = YES;

	[self.myWatch appMessagesLaunch:^(PBWatch *watch, NSError *error) {
		if (!error) {
			NSLog(@"Successfully launched app.");
		} else {
			NSLog(@"Error launching app - Error: %@", error);
		}
	}];
	
	__block int counter = 0;
	[self.myWatch appMessagesAddReceiveUpdateHandler:^BOOL(PBWatch *watch, NSDictionary *update) {
		counter++;
		return [self logUpdate:update fromWatch:watch];
		return YES;
	}];
}

- (void)stopWatchApp {
	[self stopRecordingData:nil];
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
    
    NSLog(@"Pebble connected: %@", [watch name]);
    self.myWatch = watch;
	[self startWatchApp];
}

- (void)pebbleCentral:(PBPebbleCentral*)central watchDidDisconnect:(PBWatch*)watch {
    [[[UIAlertView alloc] initWithTitle:@"Disconnected!"
								message:[watch name]
							   delegate:nil
					  cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    
    NSLog(@"Pebble disconnected: %@", [watch name]);
    
    if (self.myWatch == watch || [watch isEqual:self.myWatch]) {
        self.myWatch = nil;
    }
}

//===============================================================
#pragma mark UITextFieldDelegate
//===============================================================

// have "return" close the keyboard
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[textField resignFirstResponder];
	return NO;
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
	if (textField != _userIdText || ! [[self readUserId] length]) return YES;
	
	// state machine to get this to start editing once the user goes thru
	// the alert and hits yes; this flag gets set once the user dismisses
	// the dialog
	static BOOL shouldEdit = NO;
	if (shouldEdit) {
		shouldEdit = NO;
		return YES;
	}
	
	UIAlertController * alert = [UIAlertController
								  alertControllerWithTitle:@"Really change ID?"
								  message:@"Changing User ID if you're not a different person will ruin everything ever."
								  preferredStyle:UIAlertControllerStyleAlert];

	UIAlertAction* ok = [UIAlertAction
						 actionWithTitle:@"Yes"
						 style:UIAlertActionStyleDefault
						 handler:^(UIAlertAction * action) {
							 shouldEdit = YES;
							 [alert dismissViewControllerAnimated:YES completion:nil];
							 [_userIdText becomeFirstResponder];	//call this func again
						 }];
	UIAlertAction* cancel = [UIAlertAction
							 actionWithTitle:@"No"
							 style:UIAlertActionStyleDefault
							 handler:^(UIAlertAction * action) {
								 shouldEdit = NO;
								 [alert dismissViewControllerAnimated:YES completion:nil];
							 }];
	[alert addAction:ok];
	[alert addAction:cancel];
	
	[self presentViewController:alert animated:YES completion:nil];
	return NO;	//returns immediately, so retval can't be set by alert directly
}

-(void) textFieldDidEndEditing:(UITextField *)textField {
	if (textField == _userIdText) {
		[_dataLogger setLogSubdir:[self userIdOrDefaultValue]];
	}
}

//===============================================================
#pragma mark UITableViewDataSource
//===============================================================

// so the basic setup is that the left table is a category and the
// right table is the subcategory; you can select something in the
// left table and it'll change what's shown in the right half;
// separate from this, you can double tap on anything to add it to
// the current set of labels; if you add something in the right
// table, whatever category it's in in the left table automatically
// gets added, and if you unselect something in the left table,
// everything in the right table gets unselected

//- (NSArray*) getSelectedLabelsAtLevel:(NSUInteger)lvl {
//	NSMutableArray* lbls = [NSMutableArray array];
//	if (lvl == 0) {
//		NSArray* selectedIdxs = [_labelTable0 indexPathsForSelectedRows];
//		NSArray* values = [self getPossibleLabelsAtLevel:lvl];
//		for (NSIndexSet* idx in selectedIdxs) {
//			[lbls addObject:[values objectsAtIndexes:idx]];
//		}
//	}
//	return lbls;
//}

//- (NSArray*) getPossibleLabelsAtLevel:(NSUInteger)lvl {
//	if (lvl == 0) {
//		return getTopLevelLabels();
//	}
//	// the labels
//	NSMutableArray* lbls = [NSMutableArray array];
//	for (NSString* lbl in [self getActiveLabelsAtLevel:(lvl-1)]) {
//		[lbls addObjectsFromArray:[_labelsDict objectForKey:lbl]];
//	}
//	return lbls;
//}

//- (NSMutableArray*) getActiveLabelsAtLevel:(NSUInteger)lvl {
//	NSMutableArray* lbls = [NSMutableArray array];
//	if (lvl == 0) {
//		for (NSString* key in [_labelsDict allKeys]) {
//			if (key.active) {
//				[lbls addObject:key];
//			}
//		}
//		return lbls;
//	}
//	for (NSString* key in [self getActiveLabelsAtLevel:(lvl-1)]) {
//		if (key.active) {
//			NSString* lbl = [_labelsDict objectForKey:key];
//			if (lbl.active) {
//				[lbls addObject:lbl];
//			}
//		}
//	}
//	return lbls;
//}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
//	return 0;
//	NSLog(@"called numberOfRows");
	if (tableView == _labelTable0) {
//		NSLog(@"numberOfRows: called for table0");
		return [_currentLabels0 count];
	} else if (tableView == _labelTable1) {
//		NSLog(@"numberOfRows: called for table1 (# = %d", [_currentLabels1 count]);
		return [_currentLabels1 count];
	}
	return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	
	static NSString *simpleTableIdentifier = @"gradientCell";
//	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:simpleTableIdentifier];
	SHCTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:simpleTableIdentifier forIndexPath:indexPath];
	cell.textLabel.backgroundColor = [UIColor clearColor];
	if (cell == nil) {
//		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:simpleTableIdentifier];
		cell = [[SHCTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:simpleTableIdentifier];
	}
	
	NSString * lbl;
	if (tableView == _labelTable0) {
//		NSLog(@"cellRowForIndex: called for table1");
		lbl = [_currentLabels0 objectAtIndex:indexPath.row];
//		cell.textLabel.text = [lbl stringByAppendingString:@" >"];
		cell.textLabel.text = lbl;
	} else if (tableView == _labelTable1) {
//		NSLog(@"cellRowForIndex: called for table1");
		lbl = [_currentLabels1 objectAtIndex:indexPath.row];
		cell.textLabel.text = lbl;
	}

	[self updateAppearanceOfCell:cell withLabel:lbl];
//	cell.selectionStyle = UITableViewCellSelectionStyleGray;
	[cell setSelectionStyle:UITableViewCellSelectionStyleBlue];
	[cell setBackgroundColor:[UIColor lightGrayColor]];	//setting bg of anything IB seems feckless
	
//	cell.textLabel.text = [NSString stringWithFormat:@"%d", indexPath.row];
//	cell.imageView.image = [UIImage imageNamed:@"green_checkmark.png"];
	return cell;
}

//===============================================================
#pragma mark UITableViewDelegate
//===============================================================

-(id) getLabelInTableView:(UITableView *)tableView atIdxPath:(NSIndexPath *)indexPath {
	if (tableView == _labelTable0) {
		return [_currentLabels0 objectAtIndex:indexPath.row];
	} else if (tableView == _labelTable1) {
		return [_currentLabels1 objectAtIndex:indexPath.row];
	}
	return nil;
}

//--------------------------------
// logic for single and double taps (not real delegate methods)
//--------------------------------

// happens immediately
- (void)tableView:(UITableView *)tableView didAnyTapAtIndexPath:(NSIndexPath *)indexPath {
	if (tableView == _labelTable0) {
		NSString* key = [_currentLabels0 objectAtIndex:indexPath.row];
		_selectedLabelIdx0 = indexPath;
		_currentLabels1 = [_labelsDict objectForKey:key];
		[_labelTable1 reloadData];
	}
}

// happens after like .25s, when we're sure it wasn't a double tap
- (void)tableView:(UITableView *)tableView didSingleTapAtIndexPath:(NSIndexPath *)indexPath {
//	if (tableView == _labelTable0) {
//		NSString* key = [_currentLabels0 objectAtIndex:indexPath.row];
//		_selectedLabelIdx0 = indexPath;
//		_currentLabels1 = [_labelsDict objectForKey:key];
//		[_labelTable1 reloadData];
//	}
}

- (void)tableView:(UITableView *)tableView didDoubleTapAtIndexPath:(NSIndexPath *)indexPath {
	NSString* lbl = [self getLabelInTableView:tableView atIdxPath:indexPath];
	[self toggleLabelActive:lbl];
	UITableViewCell* cell = [tableView cellForRowAtIndexPath:indexPath];
	[self updateAppearanceOfCell:cell withLabel:lbl];

	// if label in first table turned off, also turn off it's children in
	// the second table
	if (tableView == _labelTable0 && ! [self isLabelActive:lbl]) {
		for (NSString* child in [_labelsDict objectForKey:lbl]) {
			[self setLabelInactive:child];
		}
		[_labelTable1 reloadData];
	} else if (tableView == _labelTable1) {
		NSString* parentLbl = [_currentLabels0 objectAtIndex:_selectedLabelIdx0.row];
		if (! [self isLabelActive:parentLbl]) {
			[self setLabelActive:parentLbl];
			setCellActive([_labelTable0 cellForRowAtIndexPath:_selectedLabelIdx0]);
		}
	}
}

//--------------------------------
// crap to get it to do double taps
//--------------------------------

#define KEY_TABLE_VIEW @"tableView"
#define KEY_INDEX_PATH @"indexPath"
static const float kDoubleTapTime = .25;
static NSInteger tappedRow = -1;
static NSInteger tapCount = 0;

- (void)tapTimerFired:(NSTimer *)aTimer{
	//timer fired, so there was a single tap
	if(_tapTimer != nil) {
		tapCount = 0;
		tappedRow = -1;
		
		NSDictionary* info = [aTimer userInfo];
		[self tableView:[info objectForKey:KEY_TABLE_VIEW] didSingleTapAtIndexPath:[info objectForKey:KEY_INDEX_PATH]];
	}
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[self tableView:tableView didAnyTapAtIndexPath:indexPath];
	
	//checking for double taps here
	if(tapCount == 1 && _tapTimer != nil && tappedRow == indexPath.row) {
		//double tap - Put your double tap code here
		[_tapTimer invalidate];
		_tapTimer = nil;
		tapCount = 0;
		tappedRow = -1;
		[self tableView:tableView didDoubleTapAtIndexPath:indexPath];
	}
	else if(tapCount == 0){
		//This is the first tap. If there is no tap till tapTimer is fired, it is a single tap
		tapCount = tapCount + 1;
		tappedRow = indexPath.row;
		NSDictionary* info = @{KEY_TABLE_VIEW: tableView, KEY_INDEX_PATH: indexPath};
		_tapTimer = [NSTimer scheduledTimerWithTimeInterval:kDoubleTapTime
													 target:self
												   selector:@selector(tapTimerFired:)
												   userInfo:info
													repeats:NO];
	}
	else if(tappedRow != indexPath.row) {
		//tap on new row
		tapCount = 0;
		if(_tapTimer != nil) {
			[_tapTimer invalidate];
			[self setTapTimer:nil];
		}
	}
}

//-(UIColor*)colorForIndex:(NSInteger) index {
//	NSUInteger itemCount = _toDoItems.count - 1;
//	float val = ((float)index / (float)itemCount) * 0.6;
//	return [UIColor colorWithRed: 1.0 green:val blue: 0.0 alpha:1.0];
//}

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return 40.0f;
}

//-(void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
//	cell.backgroundColor = [self colorForIndex:indexPath.row];
//}


//===============================================================
//#pragma mark MFMailComposeViewControllerDelegate
//===============================================================

//- (IBAction)sendEmailButtonClicked :(id)sender {
//	[self composeEmailWithDebugAttachment];
//}

//- (void)composeEmailWithDebugAttachment {
//	if ([MFMailComposeViewController canSendMail]) {
//		
//		MFMailComposeViewController *mailViewController = [[MFMailComposeViewController alloc] init];
//		mailViewController.mailComposeDelegate = self;
//		
//		NSDictionary* files = [self errorLogData];
//		for (NSString* filename in files) {
//			NSMutableData *errorLogData = [NSMutableData data];
//			[errorLogData appendData:files[filename]];
//			[mailViewController addAttachmentData:errorLogData mimeType:@"text/csv" fileName:filename];
//		}
//		
//		[mailViewController setSubject:@"Data Files"];
//		[self presentModalViewController:mailViewController animated:YES];
//	} else {
//		NSString *message;
//		
//		message = @"Sorry, your issue can't be reported right now. This is most likely because no mail accounts are set up on your device.";
//		[[[UIAlertView alloc] initWithTitle:nil message:message delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", @"") otherButtonTitles: nil] show];
//	}
//}

//- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error {
//	[controller dismissModalViewControllerAnimated:YES];
//}

@end
