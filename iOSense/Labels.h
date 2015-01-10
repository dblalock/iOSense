//
//  Labels.h
//  DisplayAcc
//
//  Created by DB on 1/6/15.
//

#ifndef DisplayAcc_Labels_h
#define DisplayAcc_Labels_h

#import <Foundation/Foundation.h>

//@interface DBLabel : NSObject
//
//+(id)labelFromString:(NSString*)str;
//-(id)initWithString:(NSString*)str;
//
//@property(nonatomic) NSString *str;
//@property(nonatomic) BOOL active;
//
//@end

NSMutableArray* getTopLevelLabelNames();
NSMutableArray* getTopLevelLabels();
NSDictionary* createLabelNamesDict();

#endif
