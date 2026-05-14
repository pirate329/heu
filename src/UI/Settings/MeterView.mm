// MeterView.mm — draws a labelled filled bar in a single NSView
#import "MeterView.h"

// Layout constants (view is 190×14pt)
static const CGFloat kLabelW  = 36.0;  // "SPEED"/"ACC" column width
static const CGFloat kPadding =  8.0;  // gap between label / track / value
static const CGFloat kValueW  = 40.0;  // trailing value text column
static const CGFloat kBarH    =  3.0;  // track height
// trackW = 190 - kLabelW - kPadding - kPadding - kValueW = 98pt

@implementation MeterView {
    NSString * _label;
    NSColor  * _fillColor;
}

- (instancetype)initWithFrame:(NSRect)frame
                        label:(NSString *)label
                    fillColor:(NSColor *)color {
    self = [super initWithFrame:frame];
    _label     = [label copy];
    _fillColor = color;
    _fraction  = 0.0;
    _valueText = @"";
    return self;
}

- (void)setFraction:(CGFloat)fraction {
    _fraction = fraction;
    [self setNeedsDisplay:YES];
}

- (void)setValueText:(NSString *)valueText {
    _valueText = [valueText copy];
    [self setNeedsDisplay:YES];
}

- (BOOL)isOpaque { return NO; }

- (void)drawRect:(NSRect __unused)dirty {
    CGFloat W = self.bounds.size.width;
    CGFloat H = self.bounds.size.height;
    CGFloat trackW = W - kLabelW - kPadding - kPadding - kValueW;
    CGFloat barY   = (H - kBarH) / 2.0;

    NSFont * font = [NSFont monospacedSystemFontOfSize:9 weight:NSFontWeightRegular];

    // Category label (left-aligned in its column)
    NSDictionary * dimAttr = @{
        NSFontAttributeName:            font,
        NSForegroundColorAttributeName: [NSColor colorWithWhite:1 alpha:0.35],
    };
    NSString * catText = _label;
    NSRect catRect = NSMakeRect(0, (H - 11) / 2.0, kLabelW, 11);
    [catText drawWithRect:catRect
                  options:0
               attributes:dimAttr
                  context:nil];

    // Track background
    CGFloat trackX = kLabelW + kPadding;
    NSRect trackRect = NSMakeRect(trackX, barY, trackW, kBarH);
    NSBezierPath * trackPath = [NSBezierPath bezierPathWithRoundedRect:trackRect
                                                               xRadius:1.5 yRadius:1.5];
    [[NSColor colorWithWhite:1 alpha:0.10] setFill];
    [trackPath fill];

    // Filled portion
    CGFloat fillW = MAX(0, MIN(trackW, trackW * _fraction));
    if (fillW > 0) {
        NSRect fillRect = NSMakeRect(trackX, barY, fillW, kBarH);
        NSBezierPath * fillPath = [NSBezierPath bezierPathWithRoundedRect:fillRect
                                                                   xRadius:1.5 yRadius:1.5];
        [_fillColor setFill];
        [fillPath fill];
    }

    // Value text (right-aligned in trailing column)
    NSDictionary * valAttr = @{
        NSFontAttributeName:            font,
        NSForegroundColorAttributeName: [NSColor colorWithWhite:1 alpha:0.55],
    };
    CGFloat valueX = trackX + trackW + kPadding;
    NSRect valueRect = NSMakeRect(valueX, (H - 11) / 2.0, kValueW, 11);
    [_valueText drawWithRect:valueRect
                     options:NSStringDrawingUsesLineFragmentOrigin
                  attributes:valAttr
                     context:nil];
}

@end
