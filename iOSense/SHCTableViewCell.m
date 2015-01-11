//
//  SHCTableViewCell.m
//  iOSense
//
//  Created by DB on 1/10/15.
//  Copyright (c) 2015 Rafael Aguayo. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "SHCTableViewCell.h"

@implementation SHCTableViewCell
{
	CAGradientLayer* _gradientLayer;
}

-(id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		// add a layer that overlays the cell adding a subtle gradient effect
		_gradientLayer = [CAGradientLayer layer];
		_gradientLayer.frame = self.bounds;
		// original
//		_gradientLayer.colors = @[(id)[[UIColor colorWithWhite:1.0f alpha:0.2f] CGColor],
//								  (id)[[UIColor colorWithWhite:1.0f alpha:0.1f] CGColor],
//								  (id)[[UIColor clearColor] CGColor],
//								  (id)[[UIColor colorWithWhite:0.0f alpha:0.1f] CGColor]];
//		_gradientLayer.locations = @[@0.00f, @0.01f, @0.95f, @1.00f];
		_gradientLayer.colors = @[(id)[[UIColor colorWithWhite:1.0f alpha:0.3f] CGColor],
								  (id)[[UIColor colorWithWhite:1.0f alpha:0.2f] CGColor],
								  (id)[[UIColor clearColor] CGColor],
								  (id)[[UIColor colorWithWhite:0.0f alpha:0.2f] CGColor]];
		_gradientLayer.locations = @[@0.00f, @0.01f, @0.95f, @1.00f];
		[self.layer insertSublayer:_gradientLayer atIndex:0];
	}
	return self;
}

-(void) layoutSubviews {
	[super layoutSubviews];
	// ensure the gradient layers occupies the full bounds
	_gradientLayer.frame = self.bounds;
}

@end