// hotkey.h — fn key push-to-talk
#pragma once
#import <Cocoa/Cocoa.h>

// on_press:   fn held down → start listening
// on_release: fn released  → stop and transcribe
void hotkey_register(dispatch_block_t on_press, dispatch_block_t on_release);
void hotkey_unregister(void);
