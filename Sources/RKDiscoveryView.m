#import "RKDiscoveryView.h"
#import "RKSidebarViews.h"
#import <QuartzCore/QuartzCore.h>

@interface RKDiscoveryCell : NSTableCellView
@property(nonatomic) NSView *dot;
@property(nonatomic) NSTextField *name;
@property(nonatomic) NSTextField *metadata;
@property(nonatomic) NSButton *preview;
@property(nonatomic) NSButton *capture;
@property(nonatomic, copy) NSString *paneID;
- (instancetype)initWithDelegate:(id<RKSidebarDelegate>)delegate;
- (void)displayPane:(NSDictionary *)pane;
@end

@implementation RKDiscoveryCell
- (instancetype)initWithDelegate:(id<RKSidebarDelegate>)delegate {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _dot = [NSView new];
    _dot.wantsLayer = YES;
    _dot.layer.cornerRadius = 4.5;
    _dot.layer.borderWidth = .65;
    _dot.layer.borderColor = [NSColor colorWithWhite:1 alpha:.32].CGColor;
    _name = RKLabel(@"", 13.5, NSFontWeightSemibold);
    _metadata = RKLabel(@"", 11.5, NSFontWeightRegular);
    _metadata.textColor = [NSColor colorWithSRGBRed:.72 green:.76 blue:.82 alpha:1];

    NSStackView *identity = RKColumn(1);
    RKAddFullWidth(identity, _name);
    RKAddFullWidth(identity, _metadata);
    __weak typeof(self) weak = self;
    __weak id<RKSidebarDelegate> actions = delegate;
    _preview = [RKActionButton title:@"" symbol:@"eye" help:@"Preview pane" tint:RKTintMuted action:^{
        if (weak.paneID) [actions previewPane:weak.paneID];
    }];
    _preview.bordered = NO;
    _preview.contentTintColor = [NSColor colorWithSRGBRed:.66 green:.71 blue:.79 alpha:1];
    _capture = [RKActionButton title:@"Capture" symbol:@"square.on.square" help:@"Capture pane" tint:RKTintMuted action:^{
        if (weak.paneID) [actions capturePane:weak.paneID];
    }];
    _capture.bordered = NO;
    _capture.wantsLayer = YES;
    _capture.layer.cornerRadius = 6;
    _capture.layer.borderWidth = 1;
    _capture.layer.backgroundColor = [NSColor colorWithSRGBRed:.109 green:.122 blue:.153 alpha:1].CGColor;
    _capture.layer.borderColor = [NSColor colorWithSRGBRed:.38 green:.42 blue:.49 alpha:1].CGColor;
    _capture.contentTintColor = [NSColor colorWithWhite:.94 alpha:1];
    _capture.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];

    for (NSView *child in @[_dot, identity, _preview, _capture]) {
        child.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:child];
        [child.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
    }
    [_dot setAccessibilityElement:NO];
    [NSLayoutConstraint activateConstraints:@[
        [_dot.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [_dot.widthAnchor constraintEqualToConstant:9],
        [_dot.heightAnchor constraintEqualToConstant:9],
        [identity.leadingAnchor constraintEqualToAnchor:_dot.trailingAnchor constant:10],
        [identity.trailingAnchor constraintEqualToAnchor:_preview.leadingAnchor constant:-4],
        [_preview.widthAnchor constraintEqualToConstant:23],
        [_preview.heightAnchor constraintEqualToConstant:24],
        [_preview.trailingAnchor constraintEqualToAnchor:_capture.leadingAnchor constant:-5],
        [_capture.widthAnchor constraintEqualToConstant:76],
        [_capture.heightAnchor constraintEqualToConstant:24],
        [_capture.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
    ]];
    return self;
}
- (void)drawRect:(NSRect)dirtyRect {
    NSRect rect = NSInsetRect(self.bounds, .5, 2);
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:7 yRadius:7];
    [[NSColor colorWithSRGBRed:.076 green:.088 blue:.110 alpha:1] setFill];
    [shape fill];
    [[NSColor colorWithSRGBRed:.24 green:.27 blue:.33 alpha:1] setStroke];
    [shape stroke];
}
- (void)displayPane:(NSDictionary *)pane {
    self.paneID = pane[@"id"];
    NSString *name = [NSString stringWithFormat:@"%@:%@", pane[@"session"], pane[@"window"]];
    NSString *path = [pane[@"path"] stringByAbbreviatingWithTildeInPath];
    NSString *command = pane[@"command"];
    NSMutableArray *details = [NSMutableArray arrayWithObject:[@"tmux " stringByAppendingString:self.paneID]];
    if (command.length) [details addObject:command];
    if (path.length) [details addObject:path];
    self.name.stringValue = name;
    self.name.toolTip = name;
    self.metadata.stringValue = [details componentsJoinedByString:@"  ·  "];
    self.metadata.toolTip = self.metadata.stringValue;
    BOOL focused = [pane[@"focused"] boolValue];
    self.dot.layer.backgroundColor = (focused ? RKTintColor(RKTintMint) : [NSColor colorWithSRGBRed:.68 green:.72 blue:.78 alpha:1]).CGColor;
    self.dot.toolTip = focused ? @"This pane has terminal focus" : nil;
    NSString *preview = [NSString stringWithFormat:@"Preview %@",name];
    NSString *capture = [NSString stringWithFormat:@"Capture %@",name];
    [self.preview setAccessibilityIdentifier:[@"preview-" stringByAppendingString:self.paneID]];
    [self.capture setAccessibilityIdentifier:[@"capture-" stringByAppendingString:self.paneID]];
    [self.preview setAccessibilityLabel:preview];
    [self.capture setAccessibilityLabel:capture];
    [self.name setAccessibilityLabel:focused ? [name stringByAppendingString:@", focused pane"] : name];
    self.preview.toolTip = preview;
    self.capture.toolTip = [capture stringByAppendingString:@" in a dedicated RK session"];
}
@end

@interface RKDiscoveryView () <NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic, weak) id<RKSidebarDelegate> actionDelegate;
@property(nonatomic) NSTableView *table;
@property(nonatomic) NSArray<NSDictionary *> *panes;
@property(nonatomic) NSLayoutConstraint *tableHeight;
@end

@implementation RKDiscoveryView
- (instancetype)initWithDelegate:(id<RKSidebarDelegate>)delegate {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _actionDelegate = delegate;
    NSScrollView *scroll = [NSScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = NO;
    [self addSubview:scroll];
    _table = [[NSTableView alloc] initWithFrame:NSMakeRect(0,0,350,130)];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"pane"];
    column.width = 350;
    column.minWidth = 1;
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_table addTableColumn:column];
    _table.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    _table.headerView = nil;
    _table.style = NSTableViewStyleFullWidth;
    _table.backgroundColor = NSColor.clearColor;
    _table.gridStyleMask = NSTableViewGridNone;
    _table.intercellSpacing = NSZeroSize;
    _table.rowHeight = 42;
    _table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    _table.delegate = self;
    _table.dataSource = self;
    [_table setAccessibilityLabel:@"Other tmux panes"];
    scroll.documentView = _table;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
    _tableHeight = [self.heightAnchor constraintEqualToConstant:42];
    _tableHeight.active = YES;
    return self;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.panes.count; }
- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row { return NO; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    RKDiscoveryCell *cell = [tableView makeViewWithIdentifier:@"paneRow" owner:self];
    if (!cell) {
        cell = [[RKDiscoveryCell alloc] initWithDelegate:self.actionDelegate];
        cell.identifier = @"paneRow";
    }
    [cell displayPane:self.panes[row]];
    return cell;
}

- (void)displayPanes:(NSArray<NSDictionary *> *)panes {
    // Activity timestamps change constantly. Only changes to the fields a cell
    // displays should touch its controls while the person is trying to click.
    NSMutableArray *next = [NSMutableArray arrayWithCapacity:panes.count];
    for (NSDictionary *pane in panes) {
        [next addObject:@{@"id":pane[@"id"], @"session":pane[@"session"] ?: @"", @"window":pane[@"window"] ?: @"",
            @"path":pane[@"path"] ?: @"", @"command":pane[@"command"] ?: @"", @"focused":pane[@"focused"] ?: @NO}];
    }
    if ([self.panes isEqual:next]) return;
    NSArray *previous = self.panes ?: @[];
    NSArray *oldIDs = [previous valueForKey:@"id"], *newIDs = [next valueForKey:@"id"];
    self.panes = next;
    self.tableHeight.constant = MIN(MAX(next.count, 1), 3) * self.table.rowHeight;
    if ([oldIDs isEqual:newIDs]) {
        NSRange visible = [self.table rowsInRect:self.table.visibleRect];
        for (NSUInteger i = visible.location; i < MIN(NSMaxRange(visible), next.count); i++) {
            if ([previous[i] isEqual:next[i]]) continue;
            RKDiscoveryCell *cell = [self.table viewAtColumn:0 row:(NSInteger)i makeIfNecessary:NO];
            [cell displayPane:next[i]];
        }
        return;
    }
    [self.table reloadData];
    if (oldIDs.count && newIDs.count && [[NSSet setWithArray:oldIDs] isEqual:[NSSet setWithArray:newIDs]]) {
        [self.table scrollRowToVisible:0];
    }
}
@end
