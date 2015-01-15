//
//  FileUtils.m
//  cB-OLP425
//
//  Created by DB on 3/25/14.
//  Copyright (c) 2014 connectBlue. All rights reserved.
//

#import "FileUtils.h"

static const NSStringEncoding kENCODING = NSUTF8StringEncoding;

@implementation FileUtils

+(NSString*) wrapStr:(const char*)str {
	return [NSString stringWithUTF8String:str];
}

+(NSString*) docsDirectory {
	return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
}

+(NSString*) getFullFileName:(NSString*)fileName {
	if ([fileName rangeOfString:[FileUtils docsDirectory]].location == 0) return fileName;
	if ([fileName length]) {
		return [[FileUtils docsDirectory] stringByAppendingPathComponent:fileName];
	}
	return [FileUtils docsDirectory];
}

+(void) ensureFileExists:(NSString*)fileName {
	if (![[NSFileManager defaultManager] fileExistsAtPath:fileName]) {
		NSLog(@"file %@ didn't exist, creating it", fileName);
        [[NSFileManager defaultManager] createFileAtPath:fileName contents:nil attributes:nil];
    }
}

+(void) ensureDirExists:(NSString*)fileName {
	if (![[NSFileManager defaultManager] fileExistsAtPath:fileName]) {
		NSLog(@"directory %@ didn't exist, creating it", fileName);
		[[NSFileManager defaultManager] createDirectoryAtPath:fileName withIntermediateDirectories:YES attributes:nil error:nil];
	}
}

+(void) deleteFile:(NSString*)fileName {
	if ([[NSFileManager defaultManager] fileExistsAtPath:fileName]) {
		NSLog(@"deleting file %@", fileName);
		[[NSFileManager defaultManager] removeItemAtPath:fileName error:nil];
	}
}

+(void) writeString:(NSString*)str toFile:(NSString*)fileName {
	NSString* fullFileName = [FileUtils getFullFileName:fileName];
	[FileUtils ensureFileExists:fullFileName];
	NSLog(@"trying to write string: \"%@\"", str);
	[[str dataUsingEncoding:kENCODING] writeToFile:fullFileName atomically:NO];
}

+(void) writeUTF8String:(const char*)str toFile:(const char*)fileName {
	NSString* s = [FileUtils wrapStr:str];
	NSString* f = [FileUtils wrapStr:fileName];
	[FileUtils writeString:s toFile:f];
}

+(void) appendString:(NSString*)str toFile:(NSString*)fileName {
	NSString* fullFileName = [FileUtils getFullFileName:fileName];
	[FileUtils ensureFileExists:fullFileName];
	
	NSFileHandle *fHandle = [NSFileHandle fileHandleForUpdatingAtPath:fullFileName ];
	[fHandle seekToEndOfFile];
	[fHandle writeData:  [str dataUsingEncoding:kENCODING]];
	[fHandle closeFile];
}
+(void) appendUTF8String:(const char*)str toFile:(const char*)fileName {
	NSString* s = [FileUtils wrapStr:str];
	NSString* f = [FileUtils wrapStr:fileName];
	[FileUtils appendString:s toFile:f];
}

+(NSString*) readStringFromFile:(NSString*)fileName {
	NSString* fullFileName = [FileUtils getFullFileName:fileName];
	return [[NSString alloc] initWithData:[NSData dataWithContentsOfFile:fullFileName] encoding:kENCODING];
}

+(BOOL) fileEmpty:(NSString*)path {
	NSFileManager *manager = [NSFileManager defaultManager];
	if ([manager fileExistsAtPath:path]) {
		NSDictionary *attributes = [manager attributesOfItemAtPath:path error:nil];
		unsigned long long size = [attributes fileSize];
		if (attributes && size == 0) {
			return YES;
		}
	}
	return NO;
}

@end
