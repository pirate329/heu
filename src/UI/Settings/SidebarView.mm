// SidebarView.mm — dark left navigation sidebar with selectable tabs
#import "SidebarView.h"

static NSColor * sbHex(uint32_t rgb, CGFloat a) {
    return [NSColor colorWithRed:((rgb>>16)&0xFF)/255.0
                           green:((rgb>>8) &0xFF)/255.0
                            blue:( rgb     &0xFF)/255.0 alpha:a];
}

// ── Sidebar item definitions ──────────────────────────────────────────────────
static NSDictionary * itemDef(NSString * label, NSString * symbol) {
    return @{ @"label": label, @"symbol": symbol };
}

static NSArray * sidebarItems(void) {
    return @[
        itemDef(@"Models",     @"square.stack"),
        itemDef(@"Shortcuts",  @"keyboard"),
        itemDef(@"Wake word",  @"waveform"),
        itemDef(@"Audio",      @"mic"),
        itemDef(@"Vocabulary", @"text.book.closed"),
        itemDef(@"Privacy",    @"lock"),
        itemDef(@"About",      @"info.circle"),
    ];
}

// Forward declare selectItemView: so SidebarItemView can call it
@interface SidebarView (Private)
- (void)selectItemView:(id)item;
@end

// ── SidebarItemView ───────────────────────────────────────────────────────────
@interface SidebarItemView : NSView
@property (nonatomic, assign) SettingsTab tag2;
@property (nonatomic, assign) BOOL        selected;
@property (nonatomic, copy)   NSString  * label;
@property (nonatomic, copy)   NSString  * symbolName;
@property (nonatomic, weak)   SidebarView * sidebar;
@end

@implementation SidebarItemView

- (void)setSelected:(BOOL)selected {
    _selected = selected;
    [self setNeedsDisplay:YES];
}

- (BOOL)isOpaque { return NO; }

- (void)drawRect:(NSRect __unused)dirty {
    CGFloat W = self.bounds.size.width;
    CGFloat H = self.bounds.size.height;

    if (_selected) {
        NSBezierPath * pill = [NSBezierPath bezierPathWithRoundedRect:
            NSMakeRect(6, 3, W - 12, H - 6) xRadius:5 yRadius:5];
        [sbHex(0xFF6B35, 1) setFill];
        [pill fill];
    }

    // Icon
    NSImageSymbolConfiguration * cfg = [NSImageSymbolConfiguration
        configurationWithPointSize:12 weight:NSFontWeightMedium];
    NSImage * icon = [NSImage imageWithSystemSymbolName:_symbolName
                               accessibilityDescription:nil];
    icon = [icon imageWithSymbolConfiguration:cfg];
    [icon setTemplate:YES];

    CGFloat iconSize = 14;
    NSRect iconRect  = NSMakeRect(14, (H - iconSize) / 2.0, iconSize, iconSize);
    [NSColor.whiteColor set];
    [icon drawInRect:iconRect fromRect:NSZeroRect
           operation:NSCompositingOperationSourceOver fraction:1
       respectFlipped:YES hints:nil];

    // Label
    NSFont * font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    NSColor * textColor = NSColor.whiteColor;
    NSDictionary * attr = @{
        NSFontAttributeName:            font,
        NSForegroundColorAttributeName: textColor,
    };
    NSSize ts = [_label sizeWithAttributes:attr];
    NSRect textRect = NSMakeRect(34, (H - ts.height) / 2.0,
                                 W - 34 - 8, ts.height);
    [_label drawInRect:textRect withAttributes:attr];
}

- (void)mouseDown:(NSEvent __unused *)event {
    [_sidebar selectItemView:self];
}

@end

// ── SidebarView ───────────────────────────────────────────────────────────────
@implementation SidebarView {
    NSMutableArray<SidebarItemView *> * _items;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    _items = [NSMutableArray array];
    _selectedTab = SettingsTabModels;
    [self buildItems];
    return self;
}

- (void)buildItems {
    NSArray * defs = sidebarItems();
    CGFloat W   = self.bounds.size.width;
    CGFloat itemH = 34;
    // Stack items from top (leave 42pt for titlebar area)
    CGFloat startY = self.bounds.size.height - 42 - itemH;

    for (NSUInteger i = 0; i < defs.count; i++) {
        NSDictionary * def = defs[i];
        SidebarItemView * item = [[SidebarItemView alloc]
            initWithFrame:NSMakeRect(0, startY - i * itemH, W, itemH)];
        item.label           = def[@"label"];
        item.symbolName      = def[@"symbol"];
        item.tag2            = (SettingsTab)i;
        item.sidebar         = self;
        item.selected        = (i == 0);
        item.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
        [self addSubview:item];
        [_items addObject:item];
    }
}

- (void)setSelectedTab:(SettingsTab)tab {
    _selectedTab = tab;
    for (SidebarItemView * item in _items)
        item.selected = (item.tag2 == tab);
}

- (void)selectItemView:(SidebarItemView *)tapped {
    if (tapped.tag2 == _selectedTab) return;
    [self setSelectedTab:tapped.tag2];
    [_delegate sidebarView:self didSelectTab:tapped.tag2];
}

- (BOOL)isOpaque { return NO; }

- (void)drawRect:(NSRect __unused)dirty {
    // Sidebar background
    [sbHex(0x111113, 1) setFill];
    NSRectFill(self.bounds);

    // Right-edge separator
    [[NSColor colorWithWhite:1 alpha:0.07] setFill];
    NSRectFill(NSMakeRect(self.bounds.size.width - 0.5, 0, 0.5, self.bounds.size.height));
}

@end
