// HeuHUDView.h — floating panel content view
#pragma once

#import <Cocoa/Cocoa.h>
#include "engine.hpp"   // HeuState

// A dark rounded view that shows state label + live audio level bars.
// Updated by HeuDelegate's animation timer (80ms interval).
@interface HeuHUDView : NSView

@property (assign) HeuState              hudState;
@property (copy)   NSArray<NSNumber *> * levelBars;   // floats 0..1, one per bar
@property (copy)   NSString *            statusText;

@end
