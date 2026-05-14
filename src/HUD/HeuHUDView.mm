// HeuHUDView.mm — floating pill HUD, centered near the notch
#import "HeuHUDView.h"
#include <cmath>

static NSColor * stateColor(HeuState s) {
    switch (s) {
        case HeuState::LISTENING:   return [NSColor colorWithRed:0.95 green:0.40 blue:0.40 alpha:0.90];
        case HeuState::PROCESSING:  return [NSColor colorWithRed:0.95 green:0.72 blue:0.35 alpha:0.90];
        default:                    return [NSColor colorWithRed:0.42 green:0.85 blue:0.58 alpha:0.90];
    }
}

@implementation HeuHUDView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) { _hudState = HeuState::DETECTING; _levelBars = @[]; _statusText = @""; }
    return self;
}

- (BOOL)isOpaque { return NO; }
- (BOOL)wantsUpdateLayer { return NO; }

- (void)drawRect:(NSRect)__unused dirty {
    NSRect r = self.bounds;

    BOOL showBars = (self.hudState == HeuState::LISTENING && self.levelBars.count > 0);

    // ── State dot — centred vertically in upper half when bars shown, else full height ──
    CGFloat midY  = showBars ? r.size.height * 0.70 : r.size.height / 2.0;
    CGFloat dotR  = 4.5;
    CGFloat dotX  = r.size.width / 2.0 - dotR;
    CGFloat dotY  = midY - dotR;

    [stateColor(self.hudState) set];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(dotX, dotY, dotR * 2, dotR * 2)] fill];

    // ── Audio bars ────────────────────────────────────────────────────────────
    if (showBars) [self drawBarsInRect:r];
}

- (void)drawBarsInRect:(NSRect)r {
    int     nBars  = (int)self.levelBars.count;
    CGFloat barW   = 4.5;
    CGFloat gap    = 2.5;
    CGFloat totalW = nBars * (barW + gap) - gap;
    CGFloat startX = (r.size.width - totalW) / 2.0;
    CGFloat maxH   = r.size.height * 0.42;
    CGFloat baseY  = 6.0;

    for (int i = 0; i < nBars; i++) {
        float   val = fminf(1.0f, [self.levelBars[i] floatValue] * 9.0f);
        CGFloat h   = 2.0f + val * maxH;
        CGFloat x   = startX + i * (barW + gap);
        NSBezierPath * bar = [NSBezierPath bezierPathWithRoundedRect:
            NSMakeRect(x, baseY, barW, h) xRadius:1.5 yRadius:1.5];
        [[NSColor colorWithWhite:0.9 alpha:0.30f + 0.55f * val] set];
        [bar fill];
    }
}

@end
