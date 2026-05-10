// AppDelegate.h — HeuDelegate interface
#pragma once

#import <Cocoa/Cocoa.h>
#include "engine.hpp"
#include "HeuHUDView.h"
#import "PillStatusView.h"
#import "text_inserter.h"

@interface HeuDelegate : NSObject <NSApplicationDelegate>

// Status bar
@property (strong) NSStatusItem * statusItem;
@property (strong) NSTimer      * animTimer;
@property (assign) int            animTick;
@property (assign) HeuState       uiState;
@property (copy)   NSString     * lastText;

// Pill state tracking
@property (assign) HeuUIState     pillState;
@property (assign) NSTimeInterval listenStartTime;
@property (assign) NSInteger      lastWordCount;
@property (assign) NSInteger      spinFrame;

// Floating HUD (currently disabled but wired)
@property (strong) NSPanel    * hudPanel;
@property (strong) HeuHUDView * hudView;
@property (assign) BOOL         hudVisible;

// Focused text element captured at wake-word time (manually retained CF object)
@property (assign) AXUIElementRef capturedElement;

// ── Pill icon drawing ─────────────────────────────────────────────────────────
- (void)updatePill;
- (void)flashDone;

// ── HUD management ────────────────────────────────────────────────────────────
- (void)showHUDForState:(HeuState)state;
- (void)hideHUD;
- (void)showTranscriptionInHUD:(NSString *)text;

@end
