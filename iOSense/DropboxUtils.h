//
//  DropBoxUtils.h
//  iOSense
//
//  Created by DB on 1/14/15.
//  Copyright (c) 2015 DB. All rights reserved.
//

#ifndef iOSense_DropboxUtils_h
#define iOSense_DropboxUtils_h

void uploadTextFile(NSString* localPath, NSString* dropboxPath,
					 void (^responseHandler)(NSURLResponse *response,
							  id responseObject,
							  NSError *error));

#endif