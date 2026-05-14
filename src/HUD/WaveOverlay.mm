// WaveOverlay.mm — animated wave bar at the very top of the screen
//
// Layout (full screen width × 54 pt tall):
//   Three layered sine waves fill downward from the top edge.
//   Amplitude is driven by the smoothed audio level.
//   Phase advances continuously so the wave is always in motion.
//   Colour palette shifts with HeuState.

#import "WaveOverlay.h"
#include <cmath>

// ─────────────────────────────────────────────────────────────────────────────
// WaveView — the drawing surface
// ─────────────────────────────────────────────────────────────────────────────

@interface WaveView : NSView
@property (assign) HeuState waveState;
@property (assign) float    level;   // smoothed 0..1
@property (assign) float    phase;
@end

@implementation WaveView

- (BOOL)isOpaque { return NO; }
- (BOOL)wantsUpdateLayer { return NO; }

- (void)drawRect:(NSRect)__unused dirty {
    NSRect  r  = self.bounds;
    CGFloat w  = r.size.width;
    CGFloat h  = r.size.height;

    [[NSColor clearColor] set];
    NSRectFill(r);

    float lv = self.level;

    // ── Colour palette ────────────────────────────────────────────────────────
    // Each state has three (front, mid, back) RGBA colours.
    struct { CGFloat r, g, b, a; } pal[3];
    switch (self.waveState) {
        case HeuState::LISTENING:
            pal[0] = {1.00, 0.22, 0.22, 0.82};
            pal[1] = {1.00, 0.10, 0.45, 0.55};
            pal[2] = {0.85, 0.05, 0.60, 0.32};
            break;
        case HeuState::PROCESSING:
            pal[0] = {1.00, 0.62, 0.00, 0.78};
            pal[1] = {1.00, 0.45, 0.00, 0.52};
            pal[2] = {0.95, 0.28, 0.00, 0.30};
            break;
        default: // DETECTING — cool indigo, always slightly visible
            pal[0] = {0.35, 0.55, 1.00, 0.38};
            pal[1] = {0.25, 0.42, 0.95, 0.24};
            pal[2] = {0.18, 0.30, 0.88, 0.13};
            break;
    }

    // ── Wave parameters ───────────────────────────────────────────────────────
    // Minimum amplitude so the bar is never completely flat.
    CGFloat minAmp  = h * 0.12f;
    CGFloat maxAmp  = h * 0.72f;
    CGFloat amp     = minAmp + lv * (maxAmp - minAmp);

    // Wave centre hangs at ~55% from the bottom of the overlay.
    // Because the overlay is at the screen top, this means the wave
    // "pours" downward from the screen edge.
    CGFloat centre  = h * 0.55f;

    // Three layers: slightly different frequencies and phase offsets for depth.
    float freqs[3]     = { 0.0110f, 0.0160f, 0.0085f };
    float phaseOff[3]  = { 0.0f,    2.09f,   4.19f   };  // 0, 2π/3, 4π/3
    float ampScale[3]  = { 1.0f,    0.75f,   0.55f   };

    for (int i = 0; i < 3; i++) {
        float p = self.phase * (1.0f + i * 0.15f) + phaseOff[i];
        float f = freqs[i];
        float a = amp * ampScale[i];

        NSBezierPath * path = [NSBezierPath bezierPath];

        // Trace the wave across the bottom of the fill region
        CGFloat y0 = centre + a * sinf(0 * f + p);
        [path moveToPoint:NSMakePoint(0, y0)];

        for (CGFloat x = 1.5; x <= w; x += 1.5) {
            CGFloat y = centre + a * sinf(x * f + p);
            [path lineToPoint:NSMakePoint(x, y)];
        }

        // Close up through the top of the view (screen edge)
        [path lineToPoint:NSMakePoint(w, h)];
        [path lineToPoint:NSMakePoint(0, h)];
        [path closePath];

        [[NSColor colorWithRed:pal[i].r green:pal[i].g
                          blue:pal[i].b alpha:pal[i].a] set];
        [path fill];
    }
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// WaveOverlay — the window
// ─────────────────────────────────────────────────────────────────────────────

static const CGFloat kOverlayHeight = 54.0;

@interface WaveOverlay ()
@property (strong) WaveView * waveView;
@property (strong) NSTimer  * animTimer;
@property (assign) float      phase;
@property (assign) float      smoothed;   // exponentially smoothed audioLevel
@end

@implementation WaveOverlay
@synthesize waveState = _waveState;

- (instancetype)init {
    NSRect screen = [NSScreen mainScreen].frame;  // full frame, includes menu bar
    NSRect frame  = NSMakeRect(0,
                               screen.size.height - kOverlayHeight,
                               screen.size.width,
                               kOverlayHeight);

    self = [super initWithContentRect:frame
                             styleMask:NSWindowStyleMaskBorderless
                               backing:NSBackingStoreBuffered
                                 defer:NO];
    if (!self) return nil;

    self.backgroundColor    = NSColor.clearColor;
    self.opaque             = NO;
    self.hasShadow          = NO;
    self.level              = NSScreenSaverWindowLevel;  // above everything incl. menu bar
    self.ignoresMouseEvents = YES;
    self.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
                            | NSWindowCollectionBehaviorStationary
                            | NSWindowCollectionBehaviorIgnoresCycle;

    _waveView            = [[WaveView alloc] initWithFrame:
                            NSMakeRect(0, 0, frame.size.width, kOverlayHeight)];
    _waveView.waveState  = HeuState::DETECTING;
    _waveView.level      = 0;
    _waveView.phase      = 0;
    self.contentView     = _waveView;

    _waveState = HeuState::DETECTING;
    _audioLevel = 0;
    _smoothed   = 0;

    return self;
}

- (HeuState)waveState { return _waveState; }
- (void)setWaveState:(HeuState)s {
    _waveState           = s;
    _waveView.waveState  = s;
}

- (void)startAnimating {
    if (self.animTimer) return;
    // 60 fps timer on the common run loop so it keeps firing during menu tracking
    self.animTimer = [NSTimer timerWithTimeInterval:(1.0 / 60.0)
                                             target:self
                                           selector:@selector(tick:)
                                           userInfo:nil
                                            repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.animTimer
                              forMode:NSRunLoopCommonModes];
    [self orderFrontRegardless];
}

- (void)tick:(NSTimer *)__unused t {
    // Exponential smoothing: fast attack, slow decay
    float target = self.audioLevel;
    float k      = (target > _smoothed) ? 0.35f : 0.06f;
    _smoothed   += (target - _smoothed) * k;

    // Phase speed scales with level — wave accelerates as voice gets louder
    float speed  = 0.025f + _smoothed * 0.10f;
    _phase      += speed;

    _waveView.level = _smoothed;
    _waveView.phase = _phase;
    [_waveView setNeedsDisplay:YES];
}

@end
