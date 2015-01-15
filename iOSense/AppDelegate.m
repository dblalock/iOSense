//
//  AppDelegate.m
//  DisplayAcc
//
//  Created by D Blalock on 1/2/15.
//  Copyright (c) 2014 D Blalock. All rights reserved.
//

#import "AppDelegate.h"
//#import <PebbleKit/PebbleKit.h>
//#import <DropboxSDK/DropboxSDK.h>

#import "DropBoxInfo.h"

//@interface AppDelegate() <DBSessionDelegate, DBNetworkRequestDelegate> {
//	NSString *relinkUserId;
//}
@interface AppDelegate()

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
//	NSString *root = kDBRootAppFolder;
//	
//	NSString* errorMsg = nil;
//	if ([appKey rangeOfCharacterFromSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]].location != NSNotFound) {
//		errorMsg = @"Make sure you set the app key correctly in DBRouletteAppDelegate.m";
//	} else if ([appSecret rangeOfCharacterFromSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]].location != NSNotFound) {
//		errorMsg = @"Make sure you set the app secret correctly in DBRouletteAppDelegate.m";
//	} else if ([root length] == 0) {
//		errorMsg = @"Set your root to use either App Folder of full Dropbox";
//	} else {
//		NSString *plistPath = [[NSBundle mainBundle] pathForResource:@"Info" ofType:@"plist"];
//		NSData *plistData = [NSData dataWithContentsOfFile:plistPath];
//		NSDictionary *loadedPlist =
//		[NSPropertyListSerialization
//		 propertyListFromData:plistData mutabilityOption:0 format:NULL errorDescription:NULL];
//		NSString *scheme = [[[[loadedPlist objectForKey:@"CFBundleURLTypes"] objectAtIndex:0] objectForKey:@"CFBundleURLSchemes"] objectAtIndex:0];
//		if ([scheme isEqual:@"db-APP_KEY"]) {
//			errorMsg = @"Set your URL scheme correctly in DBRoulette-Info.plist";
//		}
//	}
//	if (errorMsg != nil) {
//		[[[UIAlertView alloc]
//		   initWithTitle:@"Error Configuring Session" message:errorMsg
//		   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil]
//		 show];
//	}
//	
//	
//	DBSession* session =
//		[[DBSession alloc] initWithAppKey:appKey appSecret:appSecret root:kDBRootAppFolder];
//	session.delegate = self; // DBSessionDelegate methods allow you to handle re-authenticating
//	//	[session updateAccessToken:accKey
//	//			 accessTokenSecret:appSecret
//	//					 forUserId:userId];
//	[DBSession setSharedSession:session];
//	[DBRequest setNetworkRequestDelegate:self];
	
    return YES;
}

// this isn't getting called ever, which suggests that maybe
//- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url {
//	NSLog(@"Called handleOpenUrl");
//	if ([[DBSession sharedSession] handleOpenURL:url]) {
//		if ([[DBSession sharedSession] isLinked]) {
//			NSLog(@"DBSession connected!");
////			[navigationController pushViewController:rootViewController.photoViewController animated:YES];
//			NSLog(@"user IDs:");
//			NSLog(@"%@", [[DBSession sharedSession] userIds]);
//		} else {
//			NSLog(@"DBSession not linked...");
//		}
//		return YES;
//	}
//	
//	return NO;
//}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

//#pragma mark -
//#pragma mark DBSessionDelegate methods
//
//- (void)sessionDidReceiveAuthorizationFailure:(DBSession*)session userId:(NSString *)userId {
//	relinkUserId = userId;
//	[[[UIAlertView alloc]
//	   initWithTitle:@"Dropbox Session Ended" message:@"Do you want to relink (won't do anything)?" delegate:self
//	   cancelButtonTitle:@"Cancel" otherButtonTitles:@"Relink", nil]
//	 show];
//}
//
//
//#pragma mark -
//#pragma mark UIAlertViewDelegate methods
//
//- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)index {
////	if (index != alertView.cancelButtonIndex) {
////		[[DBSession sharedSession] linkUserId:relinkUserId fromController:rootViewController];
////	}
//	relinkUserId = nil;
//}
//
//
//#pragma mark -
//#pragma mark DBNetworkRequestDelegate methods
//
//static int outstandingRequests;
//
//- (void)networkRequestStarted {
//	outstandingRequests++;
//	if (outstandingRequests == 1) {
//		[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
//	}
//}
//
//- (void)networkRequestStopped {
//	outstandingRequests--;
//	if (outstandingRequests == 0) {
//		[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
//	}
//}


@end