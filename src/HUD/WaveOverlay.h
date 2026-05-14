// WaveOverlay.h — full-width wave bar pinned to the top of the screen
//
// Sits above everything (NSScreenSaverWindowLevel).
// Always visible — quiet sine when idle, reactive to audio when speaking.
#pragma once

#import <Cocoa/Cocoa.h>
#include "engine.hpp"

@interface WaveOverlay : NSWindow

// Current app state — drives colour palette
@property (assign) HeuState waveState;

// Raw audio RMS from the ring buffer (normalised 0..1 before passing in).
// The overlay applies its own attack/decay smoothing internally.
@property (assign) float audioLevel;

- (instancetype)init;
- (void)startAnimating;

@end
