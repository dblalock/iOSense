//
//  DropboxUploader.m
//  iOSense
//
//  Created by DB on 1/16/15.
//  Copyright (c) 2015 DB. All rights reserved.
//

#import "DropboxUploader.h"

#import "DropboxInfo.h"
#import "FileUtils.h"	//for fileEmpty()

// assumes you're uploading a text file, but really you could just pass in the
// content type as another arg and it should work with anything
void uploadTextFile(NSString* localPath, NSString* dropboxPath, void(^responseHandler)(NSURLResponse *response, id responseObject, NSError *error)) {
	static NSString *const kDropBoxPutUrl = @"https://api-content.dropbox.com/1/files_put/auto";
	
	// just return if local file empty
	if ([FileUtils fileEmpty:localPath]) {
		NSLog(@"uploadFile(): local file %@ empty, not uploading", localPath);
		return;
	}
	// read local file
	NSData* data = [[NSFileManager defaultManager] contentsAtPath:localPath];
	
	// ensure there's exactly one slash separating url components
	if (! [dropboxPath hasPrefix:@"/"]) {
		dropboxPath = [@"/" stringByAppendingString:dropboxPath];
	}
	
	// create http request
	NSString * destUrlStr = [kDropBoxPutUrl stringByAppendingString:dropboxPath];
	NSURL *URL = [NSURL URLWithString:destUrlStr];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
	
	// configure http request; note that this assumes there's a "getK()"
	// method that returns your generated access key (a huge string) in a file
	// called DropBoxInfo.h. I deliberatly didn't check this into this repo
	// in order to keep my key secret
	[request setHTTPMethod:@"PUT"];		// necessary for it to work with files_put
	[request setHTTPBody:data];
	[request setValue:[NSString stringWithFormat:@"%lu",(unsigned long)[data length]] forHTTPHeaderField:@"Content-Length"];
	[request setValue:@"text/plain" forHTTPHeaderField:@"Content-Type"];
	NSString* auth = [NSString stringWithFormat:@"Bearer %@", getK()];	//just a const
	[request setValue:auth forHTTPHeaderField:@"Authorization"];
	
	// not at all the right way to initialize an operation queue
	static NSOperationQueue* queue = nil;
	if (!queue) {
		queue = [[NSOperationQueue alloc] init];
	}
	
	[NSURLConnection sendAsynchronousRequest:request queue:queue completionHandler:^(NSURLResponse *response, id responseObject, NSError *error) {
		if (error) {
			NSLog(@"Upload file: Error: %@", error);
		} else {
			//			NSLog(@"Upload file: Success: %@ %@", response, [[NSString alloc] initWithData:responseObject
			//																	 encoding:NSUTF8StringEncoding]);
		}
		if (responseHandler) {
			responseHandler(response, responseObject, error);
		}
	}];
}

// ================================================================
// Upload struct
// ================================================================
// wow, this is a lot of boilerplate to just bundle two strings together...

@interface Upload : NSObject
@property(strong, nonatomic) NSString* localPath;
@property(strong, nonatomic) NSString* dropboxPath;
@end

@implementation Upload

- (BOOL)isEqualToUpload:(Upload *)other {
	if (!other) return NO;

	BOOL localEq = (!_localPath && !other.localPath) || [_localPath isEqualToString:other.localPath];
	BOOL remoteEq = (!_dropboxPath && !other.dropboxPath) || [_dropboxPath isEqualToString:other.dropboxPath];
	return localEq && remoteEq;
}

- (BOOL)isEqual:(id)object {
	if (self == object) return YES;
	
	if (![object isKindOfClass:[Upload class]]) {
		return NO;
	}
	
	return [self isEqualToUpload:(Upload *)object];
}

- (NSUInteger)hash {
	return [self.localPath hash] ^ [self.dropboxPath hash];
}

@end

Upload* createUpload(NSString* localPath, NSString* dropboxPath) {
	Upload* upload = [[Upload alloc] init];
	upload.localPath = localPath;
	upload.dropboxPath = dropboxPath;
	return upload;
}

// ================================================================
// Dropbox Uploader
// ================================================================

static const double kTryUploadEveryNSecs = 2*60;	// 2min

@interface DropboxUploader ()
@property(strong, atomic) NSMutableSet* filesToUpload;
@property(strong, nonatomic) NSTimer* tryUploadTimer;
//@property (nonatomic, copy) void (^onUploadResult)(NSURLResponse *response,
//	id responseObject,
//	NSError *error);
@end

@implementation DropboxUploader

+ (id)sharedUploader {
	static DropboxUploader *sharedInstance = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedInstance = [[self alloc] init];
	});
	return sharedInstance;
}

-(instancetype) init {
	if (self = [super init]) {
		_filesToUpload = [NSMutableSet set];
		_tryUploadTimer = [NSTimer scheduledTimerWithTimeInterval:kTryUploadEveryNSecs
												  target:self
												selector:@selector(tryUploadingFiles)
												userInfo:nil
												 repeats:YES];
	}
	return self;
}

-(void) addFileToUpload:(NSString*)localPath toPath:(NSString*)dropboxPath {
	[_filesToUpload addObject:createUpload(localPath, dropboxPath)];
}

-(void) removeUpload:(Upload*)upload {
	[_filesToUpload removeObject:upload];
}

-(void) removeFileToUpload:(NSString*)localPath toPath:(NSString*)dropboxPath {
	[self removeUpload:createUpload(localPath, dropboxPath)];
}

-(void) removeFileToUpload:(NSString*)localPath {
	@synchronized(_filesToUpload) {
		NSSet* nonMatches = [_filesToUpload objectsPassingTest:^BOOL(id obj, BOOL *stop) {
			Upload* upload = (Upload*) obj;
			BOOL equal = [upload.localPath isEqualToString:localPath];
			return !equal;
		}];
		_filesToUpload = [nonMatches mutableCopy];
	}
}

-(void) tryUploadingFiles {
	NSLog(@"Uploader: trying to upload files...");
	NSFileManager* mgr = [NSFileManager defaultManager];
	for (Upload* u in [_filesToUpload copy]) {
		NSString* local = u.localPath;
		
		// if the local file exists, try to upload it to dropbox; if this
		// succeeds, delete it
		if ([mgr fileExistsAtPath:local]) {
			// try the upload asynchronously in the background
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^(void) {
				uploadTextFile(local, u.dropboxPath, ^(NSURLResponse *response,
													   id responseObject, NSError *error) {
					if (! error) {
						[self removeUpload:u];
						[mgr removeItemAtPath:local error:nil];
					}
				});
			});
		// the file doens't exist, so remove it from our list
		} else {
			[self removeUpload:u];
		}
	}
	
}

//_tapTimer = [NSTimer scheduledTimerWithTimeInterval:kTryUploadEveryNSecs
//											 target:self
//										   selector:@selector(tapTimerFired:)
//										   userInfo:info
//											repeats:NO];

@end
