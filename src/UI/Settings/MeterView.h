// MeterView.h — inline speed/accuracy bar widget
#pragma once
#import <Cocoa/Cocoa.h>

@interface MeterView : NSView
- (instancetype)initWithFrame:(NSRect)frame
                        label:(NSString *)label
                    fillColor:(NSColor *)color;

@property (nonatomic, assign) CGFloat      fraction;   // 0.0–1.0
@property (nonatomic, copy)   NSString   * valueText;  // e.g. "32x rt" or "38%"
@end
