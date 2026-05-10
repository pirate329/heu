// PillStatusView.mm — draws the per-state pill NSImage for the menu bar
#import "PillStatusView.h"
#import <math.h>

// ── Helpers ────────────────────────────────────────────────────────────────────

static NSColor * bgColor(void) {
    return [NSColor colorWithRed:0.07 green:0.08 blue:0.10 alpha:1.0];
}

static void drawPillBackground(NSRect r, NSColor * border) {
    CGFloat radius = r.size.height / 2.0;
    NSBezierPath * pill = [NSBezierPath bezierPathWithRoundedRect:r
                                                         xRadius:radius
                                                         yRadius:radius];
    [bgColor() setFill];
    [pill fill];

    if (border) {
        [border setStroke];
        pill.lineWidth = 1.5;
        [pill stroke];
    }
}

static void drawWaveBars(CGFloat cx, CGFloat cy, NSColor * color) {
    CGFloat heights[] = {0.45f, 0.75f, 1.0f, 0.65f};
    int n = 4;
    CGFloat barW = 1.5, gap = 1.0;
    CGFloat totalW = n * barW + (n - 1) * gap;
    CGFloat maxH = 8.0;
    CGFloat startX = cx - totalW / 2.0;
    [color setFill];
    for (int i = 0; i < n; i++) {
        CGFloat h = maxH * heights[i];
        NSRect bar = NSMakeRect(startX + i * (barW + gap), cy - h / 2.0, barW, h);
        [[NSBezierPath bezierPathWithRoundedRect:bar xRadius:0.75 yRadius:0.75] fill];
    }
}

static void drawSpinner(CGFloat cx, CGFloat cy, NSInteger spinFrame, NSColor * color) {
    CGFloat r = 4.5;
    CGFloat startAngle = 90.0 - spinFrame * 90.0;
    CGFloat endAngle   = startAngle - 270.0;

    NSBezierPath * arc = [NSBezierPath bezierPath];
    [arc appendBezierPathWithArcWithCenter:NSMakePoint(cx, cy)
                                    radius:r
                                startAngle:startAngle
                                  endAngle:endAngle
                                 clockwise:YES];
    [color setStroke];
    arc.lineWidth = 1.8;
    arc.lineCapStyle = NSLineCapStyleRound;
    [arc stroke];
}

// ── Public function ────────────────────────────────────────────────────────────

NSImage * HeuPillImage(HeuUIState state,
                        NSInteger  elapsedSeconds,
                        NSInteger  wordCount,
                        NSInteger  spinFrame)
{
    CGFloat h = 18.0;
    CGFloat w;
    switch (state) {
        case HeuUIStateListening:    w =  90.0; break;
        case HeuUIStateTranscribing: w = 124.0; break;
        case HeuUIStateDone:         w = 124.0; break;
        default:                     w =  56.0; break;
    }

    NSImage * img = [NSImage imageWithSize:NSMakeSize(w, h)
                                   flipped:NO
                            drawingHandler:^BOOL(NSRect r) {
        CGFloat cy = NSMidY(r);

        // ── Background + border ───────────────────────────────────────────────
        NSColor * border = nil;
        switch (state) {
            case HeuUIStateListening:
                border = [NSColor colorWithRed:0.90 green:0.43 blue:0.16 alpha:1.0];
                break;
            case HeuUIStateTranscribing:
                border = [NSColor colorWithRed:0.86 green:0.67 blue:0.16 alpha:1.0];
                break;
            case HeuUIStateDone:
                border = [NSColor colorWithRed:0.24 green:0.78 blue:0.31 alpha:1.0];
                break;
            default: border = nil; break;
        }
        drawPillBackground(NSInsetRect(r, 0.75, 0.75), border);

        // ── Content by state ──────────────────────────────────────────────────

        if (state == HeuUIStateIdle) {
            NSFont * script = [NSFont fontWithName:@"SnellRoundhand" size:11.0];
            if (!script) script = [[NSFontManager sharedFontManager]
                                    convertFont:[NSFont systemFontOfSize:11.0]
                                    toHaveTrait:NSItalicFontMask];
            NSDictionary * attrs = @{
                NSFontAttributeName: script,
                NSForegroundColorAttributeName: [NSColor colorWithWhite:0.9 alpha:0.85]
            };
            NSString * label = @"heu";
            NSSize ts = [label sizeWithAttributes:attrs];
            [label drawAtPoint:NSMakePoint(8.0, cy - ts.height / 2.0) withAttributes:attrs];
            // Gray dot on right
            [[NSColor colorWithWhite:0.55 alpha:0.8] setFill];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(w - 13.0, cy - 2.5, 5.0, 5.0)] fill];
        }

        else if (state == HeuUIStateListening) {
            CGFloat x = 8.0;
            // Red record dot
            [[NSColor colorWithRed:0.86 green:0.20 blue:0.20 alpha:1.0] setFill];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x, cy - 3.0, 6.0, 6.0)] fill];
            x += 11.0;
            // Waveform bars
            drawWaveBars(x + 8.0, cy,
                         [NSColor colorWithRed:0.90 green:0.43 blue:0.16 alpha:1.0]);
            x += 19.0;
            // Elapsed time label
            NSString * timeLabel = [NSString stringWithFormat:@"%.0fs", (double)elapsedSeconds];
            NSFont * font = [NSFont systemFontOfSize:10.0 weight:NSFontWeightMedium];
            NSDictionary * attrs = @{
                NSFontAttributeName: font,
                NSForegroundColorAttributeName: [NSColor colorWithRed:0.90 green:0.43 blue:0.16 alpha:1.0]
            };
            NSSize ts = [timeLabel sizeWithAttributes:attrs];
            [timeLabel drawAtPoint:NSMakePoint(x, cy - ts.height / 2.0) withAttributes:attrs];
        }

        else if (state == HeuUIStateTranscribing) {
            CGFloat x = 11.0;
            NSColor * amber = [NSColor colorWithRed:0.86 green:0.67 blue:0.16 alpha:1.0];
            drawSpinner(x, cy, spinFrame, amber);
            x += 13.0;
            NSFont * font = [NSFont systemFontOfSize:10.0 weight:NSFontWeightRegular];
            NSDictionary * attrs = @{
                NSFontAttributeName: font,
                NSForegroundColorAttributeName: [NSColor colorWithWhite:0.85 alpha:1.0]
            };
            NSString * label = @"transcribing...";
            NSSize ts = [label sizeWithAttributes:attrs];
            [label drawAtPoint:NSMakePoint(x, cy - ts.height / 2.0) withAttributes:attrs];
        }

        else if (state == HeuUIStateDone) {
            CGFloat x = 8.0;
            NSColor * green = [NSColor colorWithRed:0.24 green:0.78 blue:0.31 alpha:1.0];
            [green setFill];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x, cy - 3.0, 6.0, 6.0)] fill];
            x += 11.0;
            NSString * label = [NSString stringWithFormat:@"\u2713 pasted \u00b7 %ldw", (long)wordCount];
            NSFont * font = [NSFont systemFontOfSize:10.0 weight:NSFontWeightRegular];
            NSDictionary * attrs = @{
                NSFontAttributeName: font,
                NSForegroundColorAttributeName: [NSColor colorWithWhite:0.90 alpha:1.0]
            };
            NSSize ts = [label sizeWithAttributes:attrs];
            [label drawAtPoint:NSMakePoint(x, cy - ts.height / 2.0) withAttributes:attrs];
        }

        return YES;
    }];

    [img setTemplate:NO];
    return img;
}
