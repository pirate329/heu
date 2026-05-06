// SettingsPanel.mm — floating model browser panel
#import "SettingsPanel.h"
#import "ModelManager.h"
#include <cmath>

static NSColor * hex(uint32_t rgb, CGFloat a) {
    return [NSColor colorWithRed:((rgb>>16)&0xFF)/255.0
                           green:((rgb>>8) &0xFF)/255.0
                            blue:( rgb     &0xFF)/255.0 alpha:a];
}

// ── Per-model row view ────────────────────────────────────────────────────────
@interface ModelRowView : NSView
@property (strong) WhisperModel    * model;
@property (strong) NSTextField     * nameLabel;
@property (strong) NSTextField     * detailLabel;
@property (strong) NSTextField     * sizeLabel;
@property (strong) NSTextField     * statusLabel;
@property (strong) NSTextField     * speedLabel;
@property (strong) NSButton        * actionBtn;
@property (strong) NSProgressIndicator * progress;
- (void)refresh;
@end

@implementation ModelRowView
- (instancetype)initWithModel:(WhisperModel *)model frame:(NSRect)frame {
    self = [super initWithFrame:frame];
    _model = model;

    CGFloat h = frame.size.height;
    _nameLabel   = [self label:NSMakeRect(12,h-20,200,16) size:12 weight:NSFontWeightSemibold];
    _detailLabel = [self label:NSMakeRect(12,4,200,13)    size:10.5 weight:NSFontWeightRegular];
    _sizeLabel   = [self label:NSMakeRect(218,h-20,80,14) size:10.5 weight:NSFontWeightRegular];
    _statusLabel = [self label:NSMakeRect(218,4,80,13)    size:10 weight:NSFontWeightMedium];

    _nameLabel.stringValue   = model.displayName;
    _detailLabel.stringValue = model.detail;
    _sizeLabel.alignment     = NSTextAlignmentRight;
    _statusLabel.alignment   = NSTextAlignmentRight;
    _detailLabel.textColor   = [NSColor colorWithWhite:0.55 alpha:1];
    _sizeLabel.textColor     = [NSColor colorWithWhite:0.55 alpha:1];

    _actionBtn = [NSButton buttonWithTitle:@"" target:self action:@selector(onAction:)];
    _actionBtn.frame = NSMakeRect(302, (h-24)/2, 86, 24);
    _actionBtn.bezelStyle = NSBezelStyleRounded;
    _actionBtn.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    [self addSubview:_actionBtn];

    _progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(12, (h-5)/2, 280, 5)];
    _progress.style         = NSProgressIndicatorStyleBar;
    _progress.indeterminate = NO;
    _progress.minValue      = 0;
    _progress.maxValue      = 1;
    _progress.hidden        = YES;
    [self addSubview:_progress];

    _speedLabel = [self label:NSMakeRect(300, (h-13)/2, 88, 13) size:9.5 weight:NSFontWeightRegular];
    _speedLabel.alignment = NSTextAlignmentRight;
    _speedLabel.textColor = [NSColor colorWithWhite:0.55 alpha:1];
    _speedLabel.hidden    = YES;
    [self addSubview:_speedLabel];

    [self refresh];
    return self;
}

- (NSTextField *)label:(NSRect)r size:(CGFloat)sz weight:(NSFontWeight)w {
    NSTextField * f = [NSTextField labelWithString:@""];
    f.frame = r; f.font = [NSFont systemFontOfSize:sz weight:w];
    f.textColor = [NSColor colorWithWhite:0.88 alpha:1];
    [self addSubview:f]; return f;
}

- (void)refresh {
    ModelManager * mm = [ModelManager shared];
    BOOL downloaded   = [mm isDownloaded:_model];
    BOOL current      = [mm isCurrent:_model];
    BOOL downloading  = [mm isDownloading:_model];

    // Size
    double mb = _model.sizeBytes / 1e6;
    _sizeLabel.stringValue = mb > 1000
        ? [NSString stringWithFormat:@"%.1f GB", mb/1000]
        : [NSString stringWithFormat:@"%.0f MB", mb];

    // Status
    if (current) {
        _statusLabel.stringValue = @"In use";
        _statusLabel.textColor   = hex(0x4CD964, 1);
    } else if (downloaded) {
        _statusLabel.stringValue = @"Downloaded";
        _statusLabel.textColor   = [NSColor colorWithWhite:0.55 alpha:1];
    } else {
        _statusLabel.stringValue = @"—";
        _statusLabel.textColor   = [NSColor colorWithWhite:0.35 alpha:1];
    }

    // Action button / progress
    if (downloading) {
        _actionBtn.hidden  = YES;
        _progress.hidden   = NO;
        // speed label shown by setDownloadFraction:speed:
    } else if (current) {
        _actionBtn.hidden  = NO; _progress.hidden = YES; _speedLabel.hidden = YES;
        _actionBtn.title   = @"In Use";
        _actionBtn.enabled = NO;
    } else if (downloaded) {
        _actionBtn.hidden  = NO; _progress.hidden = YES; _speedLabel.hidden = YES;
        _actionBtn.title   = @"Use";
        _actionBtn.enabled = YES;
    } else {
        _actionBtn.hidden  = NO; _progress.hidden = YES; _speedLabel.hidden = YES;
        _actionBtn.title   = @"Download";
        _actionBtn.enabled = YES;
    }
}

- (void)setDownloadFraction:(double)f speedBytesPerSec:(double)speed {
    _actionBtn.hidden = YES;
    _progress.hidden  = NO;
    _progress.doubleValue = f;

    if (speed > 0) {
        NSString * speedStr;
        if (speed >= 1e6)
            speedStr = [NSString stringWithFormat:@"%.1f MB/s", speed / 1e6];
        else
            speedStr = [NSString stringWithFormat:@"%.0f KB/s", speed / 1e3];
        _speedLabel.stringValue = speedStr;
        _speedLabel.hidden = NO;
    }
    // Also update sizeLabel to show bytes remaining
    if (f > 0 && f < 1) {
        double remaining = _model.sizeBytes * (1.0 - f);
        NSString * remStr = remaining >= 1e9
            ? [NSString stringWithFormat:@"%.1f GB left", remaining / 1e9]
            : [NSString stringWithFormat:@"%.0f MB left", remaining / 1e6];
        _statusLabel.stringValue = remStr;
        _statusLabel.textColor   = [NSColor colorWithWhite:0.55 alpha:1];
    }
}

- (void)onAction:(id)__unused sender {
    ModelManager * mm = [ModelManager shared];
    if (![mm isDownloaded:_model]) {
        [mm downloadModel:_model];
    } else {
        [mm switchToModel:_model];
        _actionBtn.enabled = NO;
        _actionBtn.title   = @"Loading…";
    }
}

- (BOOL)isOpaque { return NO; }
- (void)drawRect:(NSRect)__unused r {
    // Subtle separator
    [[NSColor colorWithWhite:1 alpha:0.06] setFill];
    NSRectFill(NSMakeRect(0, 0, self.bounds.size.width, 0.5));
}
@end

// ── SettingsPanel ─────────────────────────────────────────────────────────────
@interface SettingsPanel () <ModelManagerDelegate>
@property (strong) NSPanel                    * panel;
@property (strong) NSMutableArray<ModelRowView*> * rows;
@end

@implementation SettingsPanel

+ (instancetype)shared {
    static SettingsPanel * s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [[SettingsPanel alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    _rows = [NSMutableArray array];
    [ModelManager shared].delegate = self;
    return self;
}

- (void)show {
    if (!_panel) [self buildPanel];
    [self refreshAll];
    [_panel makeKeyAndOrderFront:nil];
    [_panel center];
}

- (void)buildPanel {
    CGFloat rowH = 52, padX = 0, headerH = 64, footerH = 36;
    NSArray * models = [ModelManager shared].models;
    CGFloat panelH = headerH + models.count * rowH + footerH;

    _panel = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(0,0,400,panelH)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                            NSWindowStyleMaskFullSizeContentView
                    backing:NSBackingStoreBuffered defer:NO];
    _panel.title             = @"heu · Models";
    _panel.titlebarAppearsTransparent = YES;
    _panel.movableByWindowBackground  = YES;
    _panel.backgroundColor   = hex(0x161618, 1);
    _panel.level             = NSFloatingWindowLevel;
    _panel.hidesOnDeactivate = NO;

    NSView * cv = _panel.contentView;

    // Header
    NSTextField * header = [NSTextField labelWithString:@"Speech-to-Text Models"];
    header.frame = NSMakeRect(16, panelH - 32, 300, 18);
    header.font  = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    header.textColor = [NSColor colorWithWhite:0.9 alpha:1];
    [cv addSubview:header];

    NSString * dir = [[ModelManager shared] modelsDirectory];
    NSTextField * sub = [NSTextField labelWithString:dir];
    sub.frame = NSMakeRect(16, panelH - 50, 370, 13);
    sub.font  = [NSFont monospacedSystemFontOfSize:9.5 weight:NSFontWeightRegular];
    sub.textColor = [NSColor colorWithWhite:0.4 alpha:1];
    [cv addSubview:sub];

    // Model rows
    for (NSUInteger i = 0; i < models.count; i++) {
        CGFloat y = footerH + (models.count - 1 - i) * rowH;
        ModelRowView * row = [[ModelRowView alloc]
            initWithModel:models[i]
                    frame:NSMakeRect(padX, y, 400-padX*2, rowH)];
        [cv addSubview:row];
        [_rows addObject:row];
    }

    // Footer note
    NSTextField * note = [NSTextField labelWithString:
        @"Models download from huggingface.co/ggerganov/whisper.cpp"];
    note.frame = NSMakeRect(16, 10, 370, 13);
    note.font  = [NSFont systemFontOfSize:9.5 weight:NSFontWeightRegular];
    note.textColor = [NSColor colorWithWhite:0.3 alpha:1];
    [cv addSubview:note];
}

- (void)refreshAll {
    for (ModelRowView * r in _rows) [r refresh];
}

// ── ModelManagerDelegate ──────────────────────────────────────────────────────
- (void)modelDownloadProgress:(WhisperModel *)model fraction:(double)f speedBytesPerSec:(double)speed {
    for (ModelRowView * r in _rows)
        if ([r.model.modelId isEqualToString:model.modelId])
            [r setDownloadFraction:f speedBytesPerSec:speed];
}

- (void)modelDownloadFinished:(WhisperModel *)model error:(NSError *)error {
    [self refreshAll];
    if (error && !([error.domain isEqualToString:NSURLErrorDomain] &&
                   error.code == NSURLErrorCancelled)) {
        NSAlert * a = [[NSAlert alloc] init];
        a.messageText     = @"Download failed";
        a.informativeText = error.localizedDescription;
        [a runModal];
    }
}

- (void)modelSwitchFinished:(WhisperModel *)model error:(NSError *)error {
    [self refreshAll];
    if (error) {
        NSAlert * a = [[NSAlert alloc] init];
        a.messageText     = [NSString stringWithFormat:@"Could not switch to %@", model.displayName];
        a.informativeText = error.localizedDescription;
        [a runModal];
    }
}

@end
