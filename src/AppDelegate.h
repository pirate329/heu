// AppDelegate.h — HeuDelegate interface
#pragma once

#import <Cocoa/Cocoa.h>
#include "engine.hpp"
#include "HeuHUDView.h"
#import "WaveOverlay.h"
#import "text_inserter.h"

@interface HeuDelegate : NSObject <NSApplicationDelegate>

// Status bar
@property (strong) NSStatusItem * statusItem;
@property (strong) NSTimer      * animTimer;
@property (assign) int            animTick;
@property (assign) HeuState       uiState;
@property (copy)   NSString     * lastText;

// Floating HUD
@property (strong) NSPanel    * hudPanel;
@property (strong) HeuHUDView * hudView;
@property (assign) BOOL         hudVisible;

// Top-of-screen wave overlay
@property (strong) WaveOverlay * waveOverlay;

// Focused text element captured at wake-word time (manually retained CF object)
@property (assign) AXUIElementRef capturedElement;

// ── Icon drawing (implemented in AppDelegate.mm) ──────────────────────────────
- (NSImage *)iconForState:(HeuState)state tick:(int)tick;
- (void)updateIcon;
- (void)flashDone;

// ── HUD management ────────────────────────────────────────────────────────────
- (void)showHUDForState:(HeuState)state;
- (void)hideHUD;
- (void)showTranscriptionInHUD:(NSString *)text;

@end
