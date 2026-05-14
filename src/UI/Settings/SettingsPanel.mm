// SettingsPanel.mm — resizable, full-screen-capable settings window with sidebar
#import "SettingsPanel.h"
#import "ModelManager.h"
#import "ModelRowView.h"
#import "SidebarView.h"

static const CGFloat kSidebarWidth = 130.0;
static const CGFloat kMinWindowW   = 460.0;
static const CGFloat kMinWindowH   = 360.0;
static const CGFloat kHeaderH      =  76.0;
static const CGFloat kRowH         =  72.0;
static const CGFloat kSectionH     =  28.0;

static NSColor * spHex(uint32_t rgb, CGFloat a) {
    return [NSColor colorWithRed:((rgb>>16)&0xFF)/255.0
                           green:((rgb>>8) &0xFF)/255.0
                            blue:( rgb     &0xFF)/255.0 alpha:a];
}

// ── SettingsPanel ─────────────────────────────────────────────────────────────
@interface SettingsPanel () <ModelManagerDelegate, SidebarViewDelegate, NSWindowDelegate>
@property (strong) NSWindow                      * window;
@property (strong) SidebarView                   * sidebar;
@property (strong) NSView                        * modelsContentView;
@property (strong) NSView                        * placeholderView;
@property (strong) NSTextField                   * diskLabel;
@property (strong) NSScrollView                  * scrollView;
@property (strong) NSView                        * docView;
@property (strong) NSMutableArray<ModelRowView *> * rows;
@property (strong) NSMutableArray<NSView *>       * sectionBgs;
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
    _rows       = [NSMutableArray array];
    _sectionBgs = [NSMutableArray array];
    [ModelManager shared].delegate = self;
    return self;
}


- (void)show {
    if (!_window) [self buildWindow];
    [self refreshAll];
    [_window makeKeyAndOrderFront:nil];
    [_window center];
}

// ── Window construction ───────────────────────────────────────────────────────
- (void)buildWindow {
    const CGFloat W = 680, H = 520;

    _window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, W, H)
                  styleMask:NSWindowStyleMaskTitled
                           | NSWindowStyleMaskClosable
                           | NSWindowStyleMaskMiniaturizable
                           | NSWindowStyleMaskResizable
                           | NSWindowStyleMaskFullSizeContentView
                    backing:NSBackingStoreBuffered defer:NO];
    _window.title                      = @"heu";
    _window.titlebarAppearsTransparent = YES;
    _window.movableByWindowBackground  = YES;
    _window.backgroundColor            = spHex(0x161618, 1);
    _window.minSize                    = NSMakeSize(kMinWindowW, kMinWindowH);
    _window.delegate                   = self;
    _window.collectionBehavior         = NSWindowCollectionBehaviorFullScreenPrimary
                                       | NSWindowCollectionBehaviorManaged;

    NSView * cv = _window.contentView;
    cv.autoresizesSubviews = YES;

    // ── Sidebar ───────────────────────────────────────────────────────────────
    _sidebar = [[SidebarView alloc] initWithFrame:NSMakeRect(0, 0, kSidebarWidth, H)];
    _sidebar.autoresizingMask = NSViewHeightSizable;
    _sidebar.delegate = self;
    [cv addSubview:_sidebar];

    CGFloat cX = kSidebarWidth;
    CGFloat cW = W - kSidebarWidth;

    // ── Models content view ───────────────────────────────────────────────────
    _modelsContentView = [[NSView alloc] initWithFrame:NSMakeRect(cX, 0, cW, H)];
    _modelsContentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _modelsContentView.autoresizesSubviews = YES;

    NSTextField * titleLbl = [NSTextField labelWithString:@"Speech-to-Text Models"];
    titleLbl.frame            = NSMakeRect(20, H - 48, 340, 20);
    titleLbl.font             = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
    titleLbl.textColor        = [NSColor colorWithWhite:0.92 alpha:1];
    titleLbl.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
    [_modelsContentView addSubview:titleLbl];

    NSTextField * dirLabel = [NSTextField labelWithString:[[ModelManager shared] modelsDirectory]];
    dirLabel.frame            = NSMakeRect(20, H - 66, 360, 13);
    dirLabel.font             = [NSFont monospacedSystemFontOfSize:9.5 weight:NSFontWeightRegular];
    dirLabel.textColor        = [NSColor colorWithWhite:0.35 alpha:1];
    dirLabel.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
    [_modelsContentView addSubview:dirLabel];

    _diskLabel = [NSTextField labelWithString:@""];
    _diskLabel.frame            = NSMakeRect(cW - 160, H - 48, 140, 14);
    _diskLabel.font             = [NSFont systemFontOfSize:10.5 weight:NSFontWeightRegular];
    _diskLabel.textColor        = [NSColor colorWithWhite:0.40 alpha:1];
    _diskLabel.alignment        = NSTextAlignmentRight;
    _diskLabel.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [_modelsContentView addSubview:_diskLabel];

    // ── Scroll view ───────────────────────────────────────────────────────────
    CGFloat scrollH = H - kHeaderH - 8;
    _scrollView = [[NSScrollView alloc]
        initWithFrame:NSMakeRect(0, 8, cW, scrollH)];
    _scrollView.hasVerticalScroller   = YES;
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.borderType            = NSNoBorder;
    _scrollView.drawsBackground       = NO;
    _scrollView.autohidesScrollers    = YES;
    _scrollView.autoresizingMask      = NSViewWidthSizable | NSViewHeightSizable;
    [_modelsContentView addSubview:_scrollView];

    [self buildDocView:cW];

    [cv addSubview:_modelsContentView];

    // ── Placeholder (other tabs) ───────────────────────────────────────────────
    _placeholderView = [[NSView alloc] initWithFrame:NSMakeRect(cX, 0, cW, H)];
    _placeholderView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _placeholderView.hidden = YES;

    NSTextField * cs = [NSTextField labelWithString:@"Coming soon"];
    cs.frame            = NSMakeRect(0, (H - 20) / 2.0, cW, 20);
    cs.font             = [NSFont systemFontOfSize:14 weight:NSFontWeightRegular];
    cs.textColor        = [NSColor colorWithWhite:0.40 alpha:1];
    cs.alignment        = NSTextAlignmentCenter;
    cs.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [_placeholderView addSubview:cs];

    [cv addSubview:_placeholderView];
}

// Build (or rebuild) the document view at a given content width.
- (void)buildDocView:(CGFloat)contentW {
    NSArray<WhisperModel *> * allModels = [ModelManager shared].models;
    NSArray<NSString *>     * tierOrder = @[@"FAST", @"BALANCED", @"ACCURATE"];

    NSMutableDictionary<NSString *, NSMutableArray *> * grouped = [NSMutableDictionary dictionary];
    for (NSString * t in tierOrder) grouped[t] = [NSMutableArray array];
    for (WhisperModel * m in allModels) {
        NSMutableArray * b = grouped[m.tierGroup];
        if (b) [b addObject:m];
    }

    CGFloat totalDocH = 0;
    for (NSString * t in tierOrder)
        totalDocH += kSectionH + ((NSArray *)grouped[t]).count * kRowH;

    _docView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, contentW, totalDocH)];
    _docView.autoresizingMask = NSViewWidthSizable;

    [_rows removeAllObjects];
    [_sectionBgs removeAllObjects];

    CGFloat yOffset = totalDocH;
    for (NSString * tier in tierOrder) {
        NSArray<WhisperModel *> * tierModels = grouped[tier];
        if (tierModels.count == 0) continue;

        yOffset -= kSectionH;
        NSView * hdrBg = [[NSView alloc]
            initWithFrame:NSMakeRect(0, yOffset, contentW, kSectionH)];
        hdrBg.wantsLayer = YES;
        hdrBg.layer.backgroundColor = spHex(0x1C1C1E, 1).CGColor;
        hdrBg.autoresizingMask = NSViewWidthSizable;
        [_docView addSubview:hdrBg];
        [_sectionBgs addObject:hdrBg];

        NSTextField * hdrLbl = [NSTextField labelWithString:tier];
        hdrLbl.frame            = NSMakeRect(20, (kSectionH - 13) / 2.0, 200, 13);
        hdrLbl.font             = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightBold];
        hdrLbl.textColor        = [NSColor colorWithWhite:1 alpha:0.30];
        hdrLbl.autoresizingMask = NSViewMaxXMargin;
        [hdrBg addSubview:hdrLbl];

        for (WhisperModel * m in tierModels) {
            yOffset -= kRowH;
            ModelRowView * row = [[ModelRowView alloc]
                initWithModel:m frame:NSMakeRect(0, yOffset, contentW, kRowH)];
            row.autoresizingMask = NSViewWidthSizable;
            [_docView addSubview:row];
            [_rows addObject:row];
        }
    }

    _scrollView.documentView = _docView;
    [_docView scrollPoint:NSMakePoint(0, _docView.frame.size.height)];
}

// ── Relayout on resize ────────────────────────────────────────────────────────
// Called by windowDidResize: — updates disk label and scroll view for new width.
- (void)relayoutContentSubviews {
    CGFloat   cW = _modelsContentView.bounds.size.width;
    CGFloat   cH = _modelsContentView.bounds.size.height;

    // Disk label: stays right-anchored (autoresize handles it, but keep frame consistent)
    _diskLabel.frame = NSMakeRect(cW - 160, cH - 48, 140, 14);

    // Scroll view fills content area below header (autoresize handles it too)
    _scrollView.frame = NSMakeRect(0, 8, cW, cH - kHeaderH - 8);

    // docView width must match scroll view width for rows to fill horizontally
    NSRect df = _docView.frame;
    if (fabs(df.size.width - cW) > 0.5) {
        _docView.frame = NSMakeRect(df.origin.x, df.origin.y, cW, df.size.height);
        // Section header backgrounds also need width update (they have NSViewWidthSizable
        // but docView isn't managed by NSScrollView's layout pass automatically)
        for (NSView * bg in _sectionBgs)
            bg.frame = NSMakeRect(bg.frame.origin.x, bg.frame.origin.y,
                                  cW, bg.frame.size.height);
        for (ModelRowView * row in _rows)
            row.frame = NSMakeRect(0, row.frame.origin.y, cW, kRowH);
    }
}

// ── NSWindowDelegate ──────────────────────────────────────────────────────────
- (void)windowDidResize:(NSNotification __unused *)note {
    [self relayoutContentSubviews];
}

- (void)windowDidEnterFullScreen:(NSNotification __unused *)note {
    [self relayoutContentSubviews];
}

// ── Refresh ───────────────────────────────────────────────────────────────────
- (void)refreshAll {
    for (ModelRowView * r in _rows) [r refresh];
    [self updateDiskLabel];
}

- (void)updateDiskLabel {
    long long bytes = [[ModelManager shared] totalDiskUsageBytes];
    if (bytes == 0) { _diskLabel.stringValue = @""; return; }
    double mb = bytes / 1e6;
    _diskLabel.stringValue = mb > 1000
        ? [NSString stringWithFormat:@"%.1f GB on disk", mb / 1000]
        : [NSString stringWithFormat:@"%.0f MB on disk", mb];
}

// ── SidebarViewDelegate ───────────────────────────────────────────────────────
- (void)sidebarView:(SidebarView __unused *)sb didSelectTab:(SettingsTab)tab {
    _modelsContentView.hidden = (tab != SettingsTabModels);
    _placeholderView.hidden   = (tab == SettingsTabModels);
}

// ── ModelManagerDelegate ──────────────────────────────────────────────────────
- (void)modelDownloadProgress:(WhisperModel *)model
                      fraction:(double)f
             speedBytesPerSec:(double)speed {
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
        a.messageText     = [NSString stringWithFormat:@"Could not switch to %@",
                             model.displayName];
        a.informativeText = error.localizedDescription;
        [a runModal];
    }
}

@end
