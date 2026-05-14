// AppDelegate.mm — status bar icon, HUD, and engine callback wiring
#import "AppDelegate.h"
#import "hotkey.h"
#import "ModelManager.h"
#import "SettingsPanel.h"
#include "engine.hpp"
#include "processing_loop.hpp"
#include "whisper.h"
#include <cmath>

@implementation HeuDelegate

// ─────────────────────────────────────────────────────────────────────────────
// Lifecycle
// ─────────────────────────────────────────────────────────────────────────────

- (void)applicationDidFinishLaunching:(NSNotification *)__unused note {
    self.uiState        = HeuState::DETECTING;
    self.capturedElement = nullptr;
    heu_check_ax_permission();

    // ── Status bar item ───────────────────────────────────────────────────────
    self.pillState     = HeuUIStateIdle;
    self.lastWordCount = 0;
    self.spinFrame     = 0;

    self.statusItem = [[NSStatusBar systemStatusBar]
                       statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.toolTip     = @"heu — hold fn to dictate";
    self.statusItem.button.target      = self;
    self.statusItem.button.action      = @selector(onIconClick:);
    self.statusItem.button.imageScaling = NSImageScaleProportionallyDown;
    [self updatePill];
    fprintf(stderr, "[heu] status item created\n"); fflush(stderr);

    NSMenu * menu = [[NSMenu alloc] init];
    NSMenuItem * title = [menu addItemWithTitle:@"heu — voice to text"
                                         action:nil keyEquivalent:@""];
    title.enabled = NO;
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem * copy = [[NSMenuItem alloc]
                         initWithTitle:@"Copy last transcription"
                         action:@selector(copyLast:) keyEquivalent:@"c"];
    copy.target = self;
    [menu addItem:copy];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem * settings = [[NSMenuItem alloc]
                              initWithTitle:@"Models & Settings…"
                              action:@selector(openSettings:) keyEquivalent:@","];
    settings.target = self;
    [menu addItem:settings];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    self.statusItem.menu = menu;

    // updateIcon removed — title set above is sufficient for initial state

    // ── Animation timer (80 ms — drives icon pulse and live VU bars) ──────────
    self.animTimer = [NSTimer scheduledTimerWithTimeInterval:0.08
                                                      target:self
                                                    selector:@selector(onAnimTick:)
                                                    userInfo:nil
                                                     repeats:YES];

    // ── First-run: auto-open Settings so user can download a model ───────────
    if (g_first_run) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [[SettingsPanel shared] show];
        });
    }

    // ── fn push-to-talk ───────────────────────────────────────────────────────
    __weak typeof(self) ws2 = self;
    hotkey_register(
        // fn pressed → start listening
        ^{
            if (!g_engine) return;
            if (g_engine->state.load() != HeuState::DETECTING) return;

            // Capture focused element at the moment fn is pressed
            if (ws2.capturedElement) { CFRelease(ws2.capturedElement); ws2.capturedElement = nullptr; }
            ws2.capturedElement = heu_capture_focused_element();

            g_engine->manual_trigger.store(true, std::memory_order_release);
            fprintf(stderr, "[heu] fn pressed — listening\n"); fflush(stderr);
        },
        // fn released → stop listening immediately
        ^{
            if (!g_engine) return;
            if (g_engine->state.load() != HeuState::LISTENING) return;
            g_engine->force_stop.store(true, std::memory_order_release);
            fprintf(stderr, "[heu] fn released — stopping\n"); fflush(stderr);
        }
    );

    // ── Wire engine callbacks (dispatched to main thread) ─────────────────────
    __weak typeof(self) ws = self;

    g_engine->on_state_change = [ws](HeuState s) {
        dispatch_async(dispatch_get_main_queue(), ^{
            ws.uiState   = s;
            ws.animTick  = 0;
            ws.spinFrame = 0;

            switch (s) {
                case HeuState::DETECTING:
                    if (ws.pillState != HeuUIStateDone) {
                        ws.pillState = HeuUIStateIdle;
                        [ws updatePill];
                    }
                    break;
                case HeuState::LISTENING:
                    ws.pillState       = HeuUIStateListening;
                    ws.listenStartTime = CFAbsoluteTimeGetCurrent();
                    [ws updatePill];
                    break;
                case HeuState::PROCESSING:
                    ws.pillState = HeuUIStateTranscribing;
                    [ws updatePill];
                    break;
            }

            // Capture focused element the moment wake word fires (not for manual/fn trigger)
            if (s == HeuState::LISTENING && !g_engine->is_manual_listen.load()) {
                if (ws.capturedElement) { CFRelease(ws.capturedElement); ws.capturedElement = nullptr; }
                ws.capturedElement = heu_capture_focused_element();
            }

            // HUD (currently disabled — kept wired for future use)
            if (s == HeuState::LISTENING || s == HeuState::PROCESSING) {
                // HUD disabled - do nothing
            } else {
                [ws hideHUD];
            }
        });
    };

    g_engine->on_transcription = [](const std::string & text) {
        std::string textCopy = text;
        dispatch_async(dispatch_get_main_queue(), ^{
            HeuDelegate * d = (HeuDelegate *)[NSApp delegate];
            if (!d) return;

            NSString * ns = [NSString stringWithUTF8String:textCopy.c_str()];
            d.lastText = ns;
            fprintf(stderr, "[heu] lastText set: '%s'\n", textCopy.c_str());
            fflush(stderr);

            // Count words for done pill
            NSArray * parts = [ns componentsSeparatedByCharactersInSet:
                               [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSInteger wc = 0;
            for (NSString * w in parts) { if (w.length > 0) wc++; }
            d.lastWordCount = wc;

            heu_insert_text(d.capturedElement, textCopy);
            if (d.capturedElement) { CFRelease(d.capturedElement); d.capturedElement = nullptr; }

            [d flashDone];
        });
    };
}

- (void)applicationWillTerminate:(NSNotification *)__unused note {
    hotkey_unregister();
    if (self.capturedElement) { CFRelease(self.capturedElement); self.capturedElement = nullptr; }
    if (g_engine) {
        g_engine->running.store(false);
        if (g_engine->proc_thread.joinable()) g_engine->proc_thread.join();
        if (g_engine->ma_ok) {
            ma_device_stop (&g_engine->ma_dev);
            ma_device_uninit(&g_engine->ma_dev);
        }
        if (g_engine->wctx) whisper_free(g_engine->wctx);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animation timer
// ─────────────────────────────────────────────────────────────────────────────

- (void)onAnimTick:(NSTimer *)__unused t {
    self.animTick++;

    // During LISTENING: refresh elapsed time display ~once per second
    if (self.pillState == HeuUIStateListening && (self.animTick % 13) == 0) {
        [self updatePill];
    }

    // During PROCESSING: advance spinner frame ~3x per second
    if (self.pillState == HeuUIStateTranscribing && (self.animTick % 4) == 0) {
        self.spinFrame = (self.spinFrame + 1) % 4;
        [self updatePill];
    }

    // Live VU bars for the HUD during LISTENING (currently disabled but wired)
    if (self.uiState == HeuState::LISTENING && self.hudVisible && g_engine) {
        auto levels = compute_level_bars(g_engine, 14);
        NSMutableArray * bars = [NSMutableArray arrayWithCapacity:14];
        for (float v : levels) [bars addObject:@(v)];
        self.hudView.levelBars = bars;
        [self.hudView setNeedsDisplay:YES];
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// HUD management
// ─────────────────────────────────────────────────────────────────────────────

- (NSPoint)hudOriginForPanelSize:(NSSize)sz {
    // Centred horizontally, just below the wave overlay (54 pt) + small gap
    NSRect screen = [NSScreen mainScreen].frame;
    CGFloat x = (screen.size.width  - sz.width)  / 2.0;
    CGFloat y =  screen.size.height - 54.0 - sz.height - 8.0;
    return NSMakePoint(x, y);
}

- (void)buildHUDPanel {
    NSSize sz = NSMakeSize(260, 52);
    self.hudPanel = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, sz.width, sz.height)
                  styleMask:NSWindowStyleMaskBorderless
                    backing:NSBackingStoreBuffered
                      defer:NO];
    self.hudPanel.backgroundColor    = NSColor.clearColor;
    self.hudPanel.opaque             = NO;
    self.hudPanel.hasShadow          = YES;
    self.hudPanel.level              = NSStatusWindowLevel + 1;
    self.hudPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                       NSWindowCollectionBehaviorTransient;
    self.hudPanel.hidesOnDeactivate  = NO;
    self.hudPanel.alphaValue         = 0;

    HeuHUDView * v = [[HeuHUDView alloc] initWithFrame:NSMakeRect(0, 0, sz.width, sz.height)];
    self.hudPanel.contentView = v;
    self.hudView = v;
}

- (void)showHUDForState:(HeuState)state {
    if (!self.hudPanel) [self buildHUDPanel];

    self.hudView.hudState   = state;
    self.hudView.levelBars  = @[];
    self.hudView.statusText = (state == HeuState::LISTENING) ? @"Listening..."
                                                              : @"Transcribing...";
    [self.hudView setNeedsDisplay:YES];

    NSPoint origin = [self hudOriginForPanelSize:self.hudPanel.frame.size];
    [self.hudPanel setFrameOrigin:origin];

    if (!self.hudVisible) {
        self.hudVisible = YES;
        self.hudPanel.alphaValue = 0;
        [self.hudPanel orderFrontRegardless];
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext * ctx) {
            ctx.duration = 0.15;
            self.hudPanel.animator.alphaValue = 1.0;
        }];
    }
}

- (void)hideHUD {
    if (!self.hudVisible) return;
    self.hudVisible = NO;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * ctx) {
        ctx.duration = 0.22;
        self.hudPanel.animator.alphaValue = 0;
    } completionHandler:^{
        if (!self.hudVisible) [self.hudPanel orderOut:nil];
    }];
}

- (void)showTranscriptionInHUD:(NSString *)text {
    if (!self.hudPanel) [self buildHUDPanel];

    if (!text) text = @"";
    NSString * display = text.length > 36
        ? [[text substringToIndex:33] stringByAppendingString:@"..."]
        : text;
    self.hudView.hudState   = HeuState::DETECTING;   // green colour
    self.hudView.levelBars  = @[];
    self.hudView.statusText = [@"✓ " stringByAppendingString:display];
    [self.hudView setNeedsDisplay:YES];

    NSPoint origin = [self hudOriginForPanelSize:self.hudPanel.frame.size];
    [self.hudPanel setFrameOrigin:origin];
    self.hudPanel.alphaValue = 1.0;
    self.hudVisible = YES;
    [self.hudPanel orderFrontRegardless];

    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [ws hideHUD]; });
}

// ─────────────────────────────────────────────────────────────────────────────
// Pill image management
// ─────────────────────────────────────────────────────────────────────────────

- (void)updatePill {
    NSInteger elapsed = 0;
    if (self.pillState == HeuUIStateListening) {
        elapsed = (NSInteger)(CFAbsoluteTimeGetCurrent() - self.listenStartTime);
    }
    NSImage * img = HeuPillImage(self.pillState,
                                  elapsed,
                                  self.lastWordCount,
                                  self.spinFrame);
    self.statusItem.button.image = img;
    self.statusItem.button.title = @"";
}

- (void)flashDone {
    self.pillState = HeuUIStateDone;
    [self updatePill];

    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!ws) return;
        if (ws.pillState == HeuUIStateDone) {
            ws.pillState = HeuUIStateIdle;
            [ws updatePill];
        }
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// Actions
// ─────────────────────────────────────────────────────────────────────────────

- (void)openSettings:(id)__unused sender {
    [[SettingsPanel shared] show];
}

- (void)onIconClick:(id)__unused sender {
    if (!self.lastText) return;
    NSAlert * a = [[NSAlert alloc] init];
    a.messageText     = @"Last transcription";
    a.informativeText = self.lastText;
    [a addButtonWithTitle:@"OK"];
    [a runModal];
}

- (void)copyLast:(id)__unused sender {
    if (!self.lastText) {
        NSAlert * a = [[NSAlert alloc] init];
        a.messageText     = @"Nothing to copy yet";
        a.informativeText = @"Say \"hey heu\" followed by your dictation.\nThe transcription will be copied automatically.";
        [a addButtonWithTitle:@"OK"];
        [a runModal];
        return;
    }
    NSPasteboard * pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:self.lastText forType:NSPasteboardTypeString];
}


@end
