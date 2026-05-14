// text_inserter.mm — insert transcribed text at cursor via AX, fallback to Cmd+V
#import "text_inserter.h"
#import <Cocoa/Cocoa.h>

// ─── Helpers ──────────────────────────────────────────────────────────────────

static bool is_text_input(AXUIElementRef element) {
    CFTypeRef roleVal = nullptr;
    if (AXUIElementCopyAttributeValue(element, kAXRoleAttribute, &roleVal) != kAXErrorSuccess
        || !roleVal) return false;
    CFStringRef role = (CFStringRef)roleVal;
    bool ok = CFStringCompare(role, kAXTextFieldRole, 0) == kCFCompareEqualTo
           || CFStringCompare(role, kAXTextAreaRole,  0) == kCFCompareEqualTo
           || CFStringCompare(role, kAXComboBoxRole,  0) == kCFCompareEqualTo;
    CFRelease(roleVal);
    return ok;
}

// Write text to clipboard, then simulate Cmd+V into whichever app is currently frontmost.
// We intentionally do NOT re-activate any app — the user is still in the app they
// were dictating into. Forcing activation of a captured app caused pastes to go
// to the wrong window (e.g. Terminal instead of Slack).
static void paste_via_keyboard(const std::string & text) {
    NSString * ns = [NSString stringWithUTF8String:text.c_str()];
    NSPasteboard * pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:ns forType:NSPasteboardTypeString];

    usleep(80000);  // 80 ms — let clipboard settle

    // Use AppleScript via System Events — the only reliable way to post Cmd+V
    // from a background bundle app on macOS 26 without being silently blocked.
    // Requires one-time "Automation" permission prompt for System Events.
    NSString * script = @"tell application \"System Events\" to keystroke \"v\" using command down";
    NSAppleScript * as = [[NSAppleScript alloc] initWithSource:script];
    NSDictionary * err = nil;
    [as executeAndReturnError:&err];
    if (err) {
        NSString * errMsg = err[NSAppleScriptErrorMessage] ?: @"unknown";
        NSNumber * errNum = err[NSAppleScriptErrorNumber];
        FILE * f = fopen("/tmp/heu_insert.log", "a");
        if (f) {
            fprintf(f, "[heu] AppleScript failed: code=%d msg=%s\n",
                    errNum.intValue, errMsg.UTF8String);
            fclose(f);
        }
        fprintf(stderr, "[heu] AppleScript paste failed (code=%d): %s — trying CGEventPost fallback\n",
                errNum.intValue, errMsg.UTF8String);
        fflush(stderr);
        // Last-resort fallback
        CGEventSourceRef src  = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
        CGEventRef       down = CGEventCreateKeyboardEvent(src, (CGKeyCode)9, true);
        CGEventRef       up   = CGEventCreateKeyboardEvent(src, (CGKeyCode)9, false);
        CGEventSetFlags(down, kCGEventFlagMaskCommand);
        CGEventSetFlags(up,   kCGEventFlagMaskCommand);
        CGEventPost(kCGHIDEventTap, down);
        CGEventPost(kCGHIDEventTap, up);
        CFRelease(down); CFRelease(up); CFRelease(src);
    }

    NSRunningApplication * front = [[NSWorkspace sharedWorkspace] frontmostApplication];
    fprintf(stderr, "[heu] pasted via Cmd+V into '%s'\n",
            front.localizedName.UTF8String ?: "unknown");
    fflush(stderr);
}

// ─── Public API ───────────────────────────────────────────────────────────────

void heu_check_ax_permission(void) {
    NSDictionary * opts = @{ (__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES };
    bool trusted = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts);
    if (!trusted) {
        fprintf(stderr,
            "[heu] Accessibility not granted — system prompt shown.\n"
            "       System Settings → Privacy & Security → Accessibility → enable heu, then restart.\n");
    } else {
        fprintf(stderr, "[heu] Accessibility: GRANTED\n");
    }
    fflush(stderr);
}

AXUIElementRef heu_capture_focused_element(void) {
    AXUIElementRef sys = AXUIElementCreateSystemWide();
    if (!sys) {
        fprintf(stderr, "[heu] AXUIElementCreateSystemWide returned nil\n"); fflush(stderr);
        return nullptr;
    }
    CFTypeRef focused = nullptr;
    AXError err = AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute, &focused);
    CFRelease(sys);
    if (err != kAXErrorSuccess || !focused) {
        fprintf(stderr, "[heu] capture_focused_element failed: AXError=%d\n", (int)err); fflush(stderr);
        FILE * f = fopen("/tmp/heu_insert.log", "a");
        if (f) { fprintf(f, "[heu] capture_focused_element AXError=%d\n", (int)err); fclose(f); }
        return nullptr;
    }
    fprintf(stderr, "[heu] captured focused element OK\n"); fflush(stderr);
    return (AXUIElementRef)focused;
}

bool heu_insert_text(AXUIElementRef element, const std::string & text) {
    // Try AX direct write first (works in native AppKit apps)
    if (element && is_text_input(element)) {
        NSString *   ns    = [NSString stringWithUTF8String:text.c_str()];
        CFStringRef  cfStr = (__bridge CFStringRef)ns;
        AXError err = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute, cfStr);
        if (err == kAXErrorSuccess) {
            fprintf(stderr, "[heu] text inserted via AX\n"); fflush(stderr);
            return true;
        }
        fprintf(stderr, "[heu] AX write failed (%d) — falling back to Cmd+V\n", (int)err);
        fflush(stderr);
    }

    // Fallback: clipboard + Cmd+V (works everywhere incl. Electron/Slack/browser)
    paste_via_keyboard(text);
    return false;
}
