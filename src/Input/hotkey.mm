// hotkey.mm — fn key push-to-talk via NSEvent global monitor
//
// Hold fn → start listening (on_press called)
// Release fn → stop and transcribe (on_release called)

#import "hotkey.h"

static id s_monitor      = nil;
static dispatch_block_t s_on_press   = nil;
static dispatch_block_t s_on_release = nil;
static bool s_fn_was_down = false;

void hotkey_register(dispatch_block_t on_press, dispatch_block_t on_release) {
    s_on_press   = [on_press   copy];
    s_on_release = [on_release copy];
    s_fn_was_down = false;

    s_monitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskFlagsChanged
                                                       handler:^(NSEvent * event) {
        bool fnDown = (event.modifierFlags & NSEventModifierFlagFunction) != 0;

        fprintf(stderr, "[hotkey] flags=0x%lx  fn=%s\n",
                (unsigned long)event.modifierFlags, fnDown ? "DOWN" : "up");
        fflush(stderr);

        if (fnDown && !s_fn_was_down) {
            s_fn_was_down = true;
            if (s_on_press) s_on_press();
        } else if (!fnDown && s_fn_was_down) {
            s_fn_was_down = false;
            if (s_on_release) s_on_release();
        }
    }];

    if (!s_monitor) {
        fprintf(stderr,
            "[heu] WARNING: could not register fn key monitor.\n"
            "       Grant Input Monitoring: System Settings → Privacy & Security → Input Monitoring\n");
    } else {
        fprintf(stderr, "[heu] push-to-talk registered: hold fn to dictate\n");
    }
    fflush(stderr);
}

void hotkey_unregister(void) {
    if (s_monitor) {
        [NSEvent removeMonitor:s_monitor];
        s_monitor = nil;
    }
    s_on_press   = nil;
    s_on_release = nil;
}
