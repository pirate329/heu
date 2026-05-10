// PillStatusView.h — pill image generator for the menu bar status item
#pragma once
#import <Cocoa/Cocoa.h>

// UI-only state (superset of HeuState — adds DONE which has no engine equivalent)
typedef NS_ENUM(NSInteger, HeuUIState) {
    HeuUIStateIdle         = 0,   // engine: DETECTING
    HeuUIStateListening    = 1,   // engine: LISTENING
    HeuUIStateTranscribing = 2,   // engine: PROCESSING
    HeuUIStateDone         = 3,   // transient: shown for 2.5s after transcription
};

// Generate the NSImage for the menu bar pill.
// elapsedSeconds — only used in HeuUIStateListening (shows "Xs" label)
// wordCount      — only used in HeuUIStateDone (shows "· Nw")
// spinFrame      — only used in HeuUIStateTranscribing (0-3, rotates spinner 90° each)
NSImage * HeuPillImage(HeuUIState state,
                        NSInteger  elapsedSeconds,
                        NSInteger  wordCount,
                        NSInteger  spinFrame);
