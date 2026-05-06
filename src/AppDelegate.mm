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
    self.statusItem = [[NSStatusBar systemStatusBar]
                       statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.toolTip    = @"heu — hold fn to dictate";
    self.statusItem.button.target     = self;
    self.statusItem.button.action     = @selector(onIconClick:);
    self.statusItem.button.title      = @"≋ heu";
    self.statusItem.button.font       = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
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

    // ── Wave overlay (top of screen, always visible) ──────────────────────────
    self.waveOverlay = [[WaveOverlay alloc] init];
    [self.waveOverlay startAnimating];

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
            ws.uiState  = s;
            ws.animTick = 0;
            // [ws updateIcon]; // DISABLED - testing if this is what kills the icon
            ws.waveOverlay.waveState = s;

            // Capture focused element the moment wake word fires (not for manual/fn trigger)
            if (s == HeuState::LISTENING && !g_engine->is_manual_listen.load()) {
                if (ws.capturedElement) { CFRelease(ws.capturedElement); ws.capturedElement = nullptr; }
                ws.capturedElement = heu_capture_focused_element();
            }

            // Disable HUD display during listening/transcription states
            if (s == HeuState::LISTENING || s == HeuState::PROCESSING) {
                // HUD disabled - do nothing
            } else {
                [ws hideHUD];
            }
        });
    };

    g_engine->on_transcription = [](const std::string & text) {
        // Capture text by value for the block
        std::string textCopy = text;
        dispatch_async(dispatch_get_main_queue(), ^{
            // Get delegate directly from NSApp — avoids weak-ref zeroing in C++ lambda
            HeuDelegate * d = (HeuDelegate *)[NSApp delegate];
            if (!d) return;

            NSString * ns = [NSString stringWithUTF8String:textCopy.c_str()];
            d.lastText = ns;
            fprintf(stderr, "[heu] lastText set: '%s'\n", textCopy.c_str());
            fflush(stderr);

            heu_insert_text(d.capturedElement, textCopy);
            if (d.capturedElement) { CFRelease(d.capturedElement); d.capturedElement = nullptr; }

            [d flashDone];
            // [d showTranscriptionInHUD:ns]; // Disabled HUD for transcription
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
    // Icon only updates on state change (on_state_change callback).
    // Repeated button.image= calls cause the status item to vanish on macOS 26.

    // Feed live RMS into the wave overlay (always, regardless of state)
    if (g_engine) {
        auto bars = compute_level_bars(g_engine, 1);   // single bar = overall RMS
        float rms = bars.empty() ? 0.0f : bars[0];
        // Normalise: speech ≈ 0.01–0.10 → map to 0..1 with a gentle curve
        float normalised = fminf(1.0f, rms * 12.0f);
        self.waveOverlay.audioLevel = normalised;
    }

    // Live VU bars for the HUD during LISTENING
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
// Icon drawing
// ─────────────────────────────────────────────────────────────────────────────

- (void)updateIcon {
    NSString * label;
    switch (self.uiState) {
    case HeuState::DETECTING:   label = @"≋ heu"; break;
    case HeuState::LISTENING:   label = @"● heu"; break;
    case HeuState::PROCESSING:  label = @"◉ heu"; break;
    }
    self.statusItem.button.title = label;
}

- (NSImage *)iconForState:(HeuState)state tick:(int)__unused tick {
    const CGFloat sz = 18.0;
    int barCount = 5;
    CGFloat barW = 2.0, gap = 1.5;
    CGFloat totalW = barCount * barW + (barCount - 1) * gap;
    CGFloat heights[] = {0.30f, 0.60f, 1.0f, 0.55f, 0.35f};

    NSColor * color;
    BOOL isTemplate = NO;
    switch (state) {
    case HeuState::DETECTING:
        color = [NSColor colorWithWhite:0.75 alpha:1.0];
        isTemplate = YES;
        break;
    case HeuState::LISTENING:
        color = [NSColor colorWithRed:0.93 green:0.18 blue:0.18 alpha:1.0];
        break;
    case HeuState::PROCESSING:
        color = [NSColor colorWithRed:1.0 green:0.55 blue:0.0 alpha:1.0];
        break;
    }

    NSImage * img = [NSImage imageWithSize:NSMakeSize(sz, sz) flipped:NO
                            drawingHandler:^BOOL(NSRect r) {
        CGFloat cx = NSMidX(r), cy = NSMidY(r);
        CGFloat startX = cx - totalW / 2.0;
        CGFloat h0[] = {0.30f, 0.60f, 1.0f, 0.55f, 0.35f};
        [color set];
        for (int i = 0; i < barCount; i++) {
            CGFloat h = (sz - 4) * h0[i];
            NSRect bar = NSMakeRect(startX + i * (barW + gap), cy - h/2, barW, h);
            [[NSBezierPath bezierPathWithRoundedRect:bar xRadius:1 yRadius:1] fill];
        }
        return YES;
    }];
    [img setTemplate:isTemplate];
    return img;
}

- (void)flashDone {
    __block int n = 0;
    [NSTimer scheduledTimerWithTimeInterval:0.12 repeats:YES block:^(NSTimer * t) {
        if (n >= 6) { [t invalidate]; [self updateIcon]; return; }
        self.statusItem.button.title = (n % 2 == 0) ? @"✓ heu" : @"  heu";
        n++;
    }];
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
