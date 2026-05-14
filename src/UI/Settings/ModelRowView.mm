// ModelRowView.mm — 72pt tall model row with meter bars and styled action button
#import "ModelRowView.h"
#import "MeterView.h"

static NSColor * rowHex(uint32_t rgb, CGFloat a) {
    return [NSColor colorWithRed:((rgb>>16)&0xFF)/255.0
                           green:((rgb>>8) &0xFF)/255.0
                            blue:( rgb     &0xFF)/255.0 alpha:a];
}

// The model shown as "RECOMMENDED" when none is active
static NSString * const kRecommendedModelId = @"base.en";

// ── Badge helper view ─────────────────────────────────────────────────────────
@interface BadgeView : NSView
- (instancetype)initWithText:(NSString *)text color:(NSColor *)color;
@end

@implementation BadgeView {
    NSString * _text;
    NSColor  * _bgColor;
}

- (instancetype)initWithText:(NSString *)text color:(NSColor *)color {
    NSFont * f = [NSFont systemFontOfSize:9 weight:NSFontWeightBold];
    NSSize sz  = [text sizeWithAttributes:@{NSFontAttributeName: f}];
    NSRect fr  = NSMakeRect(0, 0, sz.width + 10, 14);
    self = [super initWithFrame:fr];
    _text    = [text copy];
    _bgColor = color;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 3;
    self.layer.masksToBounds = YES;
    return self;
}

- (BOOL)isOpaque { return NO; }

- (void)drawRect:(NSRect __unused)dirty {
    [_bgColor setFill];
    NSRectFill(self.bounds);

    NSFont * f = [NSFont systemFontOfSize:9 weight:NSFontWeightBold];
    NSDictionary * attr = @{
        NSFontAttributeName:            f,
        NSForegroundColorAttributeName: NSColor.whiteColor,
    };
    NSSize sz = [_text sizeWithAttributes:attr];
    NSRect tr = NSMakeRect((self.bounds.size.width - sz.width) / 2.0,
                           (self.bounds.size.height - sz.height) / 2.0,
                           sz.width, sz.height);
    [_text drawInRect:tr withAttributes:attr];
}
@end

// ── ModelRowView ──────────────────────────────────────────────────────────────
@implementation ModelRowView {
    NSTextField          * _nameLabel;
    NSTextField          * _detailLabel;
    NSTextField          * _sizeLabel;
    BadgeView            * _badge;
    MeterView            * _speedMeter;
    MeterView            * _accMeter;
    NSButton             * _actionBtn;
    NSView               * _btnContainer;   // coloured pill behind button
    NSProgressIndicator  * _progress;
    NSTextField          * _speedDlLabel;   // download speed during download
    NSTextField          * _remainLabel;    // bytes remaining during download
}

- (instancetype)initWithModel:(WhisperModel *)model frame:(NSRect)frame {
    self = [super initWithFrame:frame];
    _model = model;

    CGFloat W = frame.size.width;
    CGFloat H = frame.size.height;  // 72pt

    // Name label — left-anchored, right margin grows
    _nameLabel = [NSTextField labelWithString:model.displayName];
    _nameLabel.frame = NSMakeRect(16, H - 26, 240, 17);
    _nameLabel.font  = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    _nameLabel.textColor = [NSColor colorWithWhite:0.90 alpha:1];
    _nameLabel.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
    [self addSubview:_nameLabel];

    // Detail label — left-anchored
    _detailLabel = [NSTextField labelWithString:model.detail];
    _detailLabel.frame = NSMakeRect(16, H - 46, 260, 14);
    _detailLabel.font  = [NSFont systemFontOfSize:10.5 weight:NSFontWeightRegular];
    _detailLabel.textColor = [NSColor colorWithWhite:0.50 alpha:1];
    _detailLabel.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
    [self addSubview:_detailLabel];

    // Speed meter (green) — right-anchored
    NSColor * speedColor = rowHex(0x39D175, 1);
    _speedMeter = [[MeterView alloc]
        initWithFrame:NSMakeRect(W - 320, H - 28, 160, 14)
                label:@"SPEED"
            fillColor:speedColor];
    _speedMeter.fraction  = model.speedFraction;
    _speedMeter.valueText = [NSString stringWithFormat:@"%ldx rt", (long)model.speedRT];
    _speedMeter.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [self addSubview:_speedMeter];

    // Accuracy meter (amber) — right-anchored
    NSColor * accColor = rowHex(0xFF8733, 1);
    _accMeter = [[MeterView alloc]
        initWithFrame:NSMakeRect(W - 320, H - 46, 160, 14)
                label:@"ACC"
            fillColor:accColor];
    _accMeter.fraction  = model.accFraction;
    _accMeter.valueText = [NSString stringWithFormat:@"%d%%", (int)(model.accFraction * 100)];
    _accMeter.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [self addSubview:_accMeter];

    // Size label — right-anchored
    _sizeLabel = [NSTextField labelWithString:@""];
    _sizeLabel.frame     = NSMakeRect(W - 320, H - 62, 160, 13);
    _sizeLabel.font      = [NSFont systemFontOfSize:10 weight:NSFontWeightRegular];
    _sizeLabel.textColor = [NSColor colorWithWhite:0.40 alpha:1];
    _sizeLabel.alignment = NSTextAlignmentRight;
    _sizeLabel.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [self addSubview:_sizeLabel];

    // Action button container — right-anchored
    _btnContainer = [[NSView alloc] initWithFrame:NSMakeRect(W - 96, (H - 28) / 2.0, 82, 28)];
    _btnContainer.wantsLayer        = YES;
    _btnContainer.layer.cornerRadius  = 6;
    _btnContainer.layer.masksToBounds = YES;
    _btnContainer.autoresizingMask  = NSViewMinXMargin;
    [self addSubview:_btnContainer];

    _actionBtn = [NSButton buttonWithTitle:@"" target:self action:@selector(onAction:)];
    _actionBtn.frame                = _btnContainer.bounds;
    _actionBtn.bordered             = NO;
    _actionBtn.font                 = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    _actionBtn.autoresizingMask     = NSViewWidthSizable | NSViewHeightSizable;
    [_btnContainer addSubview:_actionBtn];

    // Progress bar — right-anchored
    _progress = [[NSProgressIndicator alloc]
        initWithFrame:NSMakeRect(W - 160, (H - 4) / 2.0, 146, 4)];
    _progress.style         = NSProgressIndicatorStyleBar;
    _progress.indeterminate = NO;
    _progress.minValue      = 0;
    _progress.maxValue      = 1;
    _progress.hidden        = YES;
    _progress.autoresizingMask = NSViewMinXMargin;
    [self addSubview:_progress];

    _speedDlLabel = [NSTextField labelWithString:@""];
    _speedDlLabel.frame     = NSMakeRect(W - 160, (H - 4) / 2.0 + 8, 146, 12);
    _speedDlLabel.font      = [NSFont systemFontOfSize:9 weight:NSFontWeightRegular];
    _speedDlLabel.textColor = [NSColor colorWithWhite:0.55 alpha:1];
    _speedDlLabel.alignment = NSTextAlignmentRight;
    _speedDlLabel.hidden    = YES;
    _speedDlLabel.autoresizingMask = NSViewMinXMargin;
    [self addSubview:_speedDlLabel];

    _remainLabel = [NSTextField labelWithString:@""];
    _remainLabel.frame     = NSMakeRect(W - 160, (H - 4) / 2.0 - 14, 146, 12);
    _remainLabel.font      = [NSFont systemFontOfSize:9 weight:NSFontWeightRegular];
    _remainLabel.textColor = [NSColor colorWithWhite:0.55 alpha:1];
    _remainLabel.alignment = NSTextAlignmentRight;
    _remainLabel.hidden    = YES;
    _remainLabel.autoresizingMask = NSViewMinXMargin;
    [self addSubview:_remainLabel];

    [self refresh];
    return self;
}

- (void)refresh {
    ModelManager * mm   = [ModelManager shared];
    BOOL downloaded     = [mm isDownloaded:_model];
    BOOL current        = [mm isCurrent:_model];
    BOOL downloading    = [mm isDownloading:_model];

    // Remove existing badge (may change state)
    [_badge removeFromSuperview];
    _badge = nil;

    // Size label
    double mb = _model.sizeBytes / 1e6;
    _sizeLabel.stringValue = mb > 1000
        ? [NSString stringWithFormat:@"%.1f GB", mb / 1000]
        : [NSString stringWithFormat:@"%.0f MB", mb];

    // Badge
    if (current) {
        _badge = [[BadgeView alloc] initWithText:@"ACTIVE" color:rowHex(0xFF3B30, 1)];
    } else if (!downloaded && !downloading &&
               [_model.modelId isEqualToString:kRecommendedModelId]) {
        _badge = [[BadgeView alloc] initWithText:@"RECOMMENDED" color:rowHex(0xFF9500, 1)];
    }
    if (_badge) {
        // Position badge after the name label
        NSFont * nf = _nameLabel.font;
        NSSize  ns  = [_model.displayName sizeWithAttributes:@{NSFontAttributeName: nf}];
        CGFloat H   = self.bounds.size.height;
        _badge.frame = NSMakeRect(16 + ns.width + 6,
                                  H - 26 + (_nameLabel.frame.size.height - _badge.frame.size.height) / 2.0,
                                  _badge.frame.size.width, _badge.frame.size.height);
        [self addSubview:_badge];
    }

    // Button / progress state
    if (downloading) {
        _btnContainer.hidden = YES;
        _progress.hidden     = NO;
        _speedDlLabel.hidden = NO;
        _remainLabel.hidden  = NO;
    } else {
        _btnContainer.hidden = NO;
        _progress.hidden     = YES;
        _speedDlLabel.hidden = YES;
        _remainLabel.hidden  = YES;

        if (current) {
            _btnContainer.layer.backgroundColor = rowHex(0xFF6B35, 1).CGColor;
            _actionBtn.title   = @"In use";
            _actionBtn.enabled = NO;
            _actionBtn.contentTintColor = NSColor.whiteColor;
        } else if (downloaded) {
            _btnContainer.layer.backgroundColor = rowHex(0xFF6B35, 1).CGColor;
            _actionBtn.title   = @"Use";
            _actionBtn.enabled = YES;
            _actionBtn.contentTintColor = NSColor.whiteColor;
        } else {
            _btnContainer.layer.backgroundColor = rowHex(0x2A2A2E, 1).CGColor;
            _actionBtn.title   = @"Download";
            _actionBtn.enabled = YES;
            _actionBtn.contentTintColor = [NSColor colorWithWhite:0.85 alpha:1];
        }
    }
}

- (void)setDownloadFraction:(double)f speedBytesPerSec:(double)speed {
    _btnContainer.hidden = YES;
    _progress.hidden     = NO;
    _progress.doubleValue = f;
    _speedDlLabel.hidden = NO;
    _remainLabel.hidden  = NO;

    if (speed > 0) {
        NSString * speedStr = speed >= 1e6
            ? [NSString stringWithFormat:@"%.1f MB/s", speed / 1e6]
            : [NSString stringWithFormat:@"%.0f KB/s", speed / 1e3];
        _speedDlLabel.stringValue = speedStr;
    }
    if (f > 0 && f < 1) {
        double remaining = _model.sizeBytes * (1.0 - f);
        _remainLabel.stringValue = remaining >= 1e9
            ? [NSString stringWithFormat:@"%.1f GB left", remaining / 1e9]
            : [NSString stringWithFormat:@"%.0f MB left", remaining / 1e6];
    }
}

- (void)onAction:(id __unused)sender {
    ModelManager * mm = [ModelManager shared];
    if (![mm isDownloaded:_model]) {
        [mm downloadModel:_model];
    } else {
        [mm switchToModel:_model];
        _actionBtn.enabled = NO;
        _actionBtn.title   = @"Loading\u2026";
    }
}

- (BOOL)isOpaque { return NO; }

- (void)drawRect:(NSRect __unused)r {
    // Subtle top separator
    [[NSColor colorWithWhite:1 alpha:0.06] setFill];
    NSRectFill(NSMakeRect(0, self.bounds.size.height - 0.5,
                          self.bounds.size.width, 0.5));
}

@end
