//
//  DropboxUploader.h
//  iOSense
//
//  Created by DB on 1/16/15.
//  Copyright (c) 2015 DB. All rights reserved.
//

#import <Foundation/Foundation.h>

void uploadTextFile(NSString* localPath, NSString* dropboxPath,
					void (^responseHandler)(NSURLResponse *response,
											id responseObject,
											NSError *error));

@interface DropboxUploader : NSObject

+(id) sharedUploader;

-(void) addFileToUpload:(NSString*)localPath toPath:(NSString*)dropboxPath;
-(void) removeFileToUpload:(NSString*)localPath toPath:(NSString*)dropboxPath;
//-(void) removeFileToUpload:(NSString*)localPath;

-(void) tryUploadingFiles;

//TODO possibly add callback property for what to do when a file is uploaded

@end
