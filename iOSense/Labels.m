//
//  Labels.m
//  DisplayAcc
//
//  Created by DB on 1/6/15.
//  Copyright (c) 2015 D Blalock. All rights reserved.
//

// Notes:
//	-So we don't actually use the DBLabel class; ended up just using
// dicts of strings, since using DBLabels as keys sucks since their
// "active" field is mutable
//	-createLabelNamesDict() at the bottom of this file is probably
// what you want to change

#import "Labels.h"

#import <Foundation/Foundation.h>

//#import "DBLabel.h"
//@implementation DBLabel : NSObject
//
//+(id)labelFromString:(NSString*)str {
//	return [[DBLabel alloc] initWithString:str];
//}
//
//NSMutableArray* labelsFromStrings(NSArray* strs) {
//	NSMutableArray* labels = [NSMutableArray arrayWithArray:strs];
//	for (int i = 0; i < [labels count]; i++) {
//		labels[i] = [DBLabel labelFromString:[strs objectAtIndex:i]];
//	}
//	return labels;
//}
//// abbreviation for the above to make initializations prettier
//NSMutableArray* lbls(NSArray* strs) {
//	return labelsFromStrings(strs);
//}
//
//-(id) initWithString:(NSString*)str {
//	if (self = [super init]) {
//		self.str = str;
//		self.active = NO;
//	}
//	return self;
//}
//
//// needed to make the app not die...not sure why
//-(id) copyWithZone:(NSZone *)zone {
//	DBLabel *copy = [[DBLabel allocWithZone: zone] init];
//	copy.str = self.str;
//	copy.active = self.active;
//	return copy;
//}
//
//@end
//
//NSMutableArray* getTestTopLevelLabels() {
//	return lbls(getTestTopLevelLabelNames());
//}
//
//NSMutableArray* getTopLevelLabels() {
//	return lbls(getTopLevelLabelNames());
//}

NSMutableArray* getTestTopLevelLabelNames() {
	return [@[ @"a", @"b" ] mutableCopy];
}

// this dictionary needs to be flat or we end up with a recursive mess
NSDictionary* createTestLabelNamesDict() {
	NSArray *testLabels0  = getTestTopLevelLabelNames();
	NSArray *testLabels1a = @[ @"1a0", @"1a1", @"1a2" ];
	NSArray *testLabels1b = @[ @"1b0", @"1b1", @"1b2" ];
	NSArray *testLables1  = @[testLabels1a, testLabels1b];
	NSDictionary* dict = [NSDictionary dictionaryWithObjects:testLables1 forKeys:testLabels0];
	return dict;
}

NSMutableArray* getTopLevelLabelNames() {
	return [[createLabelNamesDict() allKeys] mutableCopy];
}

NSDictionary* createLabelNamesDict() {
	NSDictionary* dict =
		@{
			@"Working": @[@"Coding", @"Papers", @"Thinking", @"Meeting"],
			@"Lifting": @[@"Squat", @"Deadlift", @"Bench Press"],
			@"Moving": @[@"Sitting", @"Standing", @"Walking", @"Jogging", @"Bus", @"Train", @"Car"],
			@"Health": @[@"Washing Hands", @"Taking Pills", @"Bathroom"],
			@"Eating": @[@"Pizza", @"Candy", @"Ice Cream", @"Hamburger", @"Hot Dog", @"Meat", @"Vegetables", @"Soup", @"Orange", @"Banana", @"Apple", @"Roll"],
			@"Drinking": @[@"Can", @"Bottle", @"Cup"]
		  };
	return dict;
}