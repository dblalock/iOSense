//
//  DropboxUtils.m
//  iOSense
//
//  Created by DB on 1/14/15.
//  Copyright (c) 2015 DB. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "DropboxInfo.h"
#import "FileUtils.h"

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
	// in order to keep my keep secret
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