#import "RKDiscoveryView.h"
#import "RKAgentCardView.h"

@interface RKDiscoveryCell : NSTableCellView
@property (nonatomic) NSTextField *name;
@property (nonatomic) NSTextField *metadata;
@property (nonatomic, copy) NSString *paneID;
- (instancetype)initWithDelegate:(id<RKSidebarDelegate>)delegate;
@end

@implementation RKDiscoveryCell
- (instancetype)initWithDelegate:(id<RKSidebarDelegate>)delegate {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    NSStackView *row = RKRow(4);
    NSStackView *identity = RKColumn(2);
    _name = RKLabel(@"", 13, NSFontWeightMedium);
    _metadata = RKDetail(@"");
    RKAddFullWidth(identity, _name);
    RKAddFullWidth(identity, _metadata);
    [row addArrangedSubview:identity];
    row.distribution = NSStackViewDistributionFill;
    [identity setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    __weak typeof(self) weak = self;
    __weak id<RKSidebarDelegate> receiver = delegate;
    [row addArrangedSubview:[RKActionButton title:@"" symbol:@"eye" help:@"Preview last screenful" tint:RKTintMuted action:^{
        [receiver previewPane:weak.paneID];
    }]];
    [row addArrangedSubview:[RKActionButton title:@"Capture" symbol:@"plus" help:@"Capture in a dedicated RK session" tint:RKTintBlue action:^{
        [receiver capturePane:weak.paneID];
    }]];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:7],
        [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-7],
        [row.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
    ]];
    return self;
}
@end

@interface RKDiscoveryView () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, weak) id<RKSidebarDelegate> actionDelegate;
@property (nonatomic) NSTableView *table;
@property (nonatomic) NSArray<NSDictionary *> *panes;
@property (nonatomic) NSLayoutConstraint *tableHeight;
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
    scroll.wantsLayer = YES;
    scroll.layer.cornerRadius = 8;
    scroll.layer.masksToBounds = YES;
    [self addSubview:scroll];
    _table = [[NSTableView alloc] initWithFrame:NSMakeRect(0,0,350,150)];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"pane"];
    column.width = 350;
    column.minWidth = 1;
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_table addTableColumn:column];
    _table.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    _table.headerView = nil;
    _table.style = NSTableViewStyleFullWidth;
    _table.backgroundColor = RKSurface();
    _table.gridStyleMask = NSTableViewSolidHorizontalGridLineMask;
    _table.gridColor = [NSColor colorWithWhite:.2 alpha:.6];
    _table.intercellSpacing = NSZeroSize;
    _table.rowHeight = 48;
    _table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    _table.delegate = self;
    _table.dataSource = self;
    scroll.documentView = _table;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
    _tableHeight = [self.heightAnchor constraintEqualToConstant:48];
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
    NSDictionary *pane = self.panes[row];
    cell.paneID = pane[@"id"];
    NSStackView *rowView = (NSStackView *)cell.subviews.firstObject;
    [(NSButton *)rowView.arrangedSubviews[1] setAccessibilityIdentifier:[@"preview-" stringByAppendingString:cell.paneID]];
    [(NSButton *)rowView.arrangedSubviews[2] setAccessibilityIdentifier:[@"capture-" stringByAppendingString:cell.paneID]];
    cell.name.stringValue = [NSString stringWithFormat:@"%@  /  %@", pane[@"session"], pane[@"window"]];
    cell.name.toolTip = cell.name.stringValue;
    NSString *path = [pane[@"path"] stringByAbbreviatingWithTildeInPath] ?: @"";
    cell.metadata.stringValue = [NSString stringWithFormat:@"%@%@   ·   %@", [pane[@"focused"] boolValue] ? @"●  " : @"", pane[@"command"] ?: @"", path];
    cell.metadata.toolTip = cell.metadata.stringValue;
    return cell;
}

- (void)displayPanes:(NSArray<NSDictionary *> *)panes {
    NSArray *fields = @[@"id", @"session", @"window", @"path", @"command", @"focused"];
    NSMutableArray *visible = [NSMutableArray arrayWithCapacity:panes.count];
    for (NSDictionary *pane in panes) [visible addObject:[pane dictionaryWithValuesForKeys:fields]];
    if ([self.panes isEqual:visible]) return;
    self.panes = visible;
    self.tableHeight.constant = MIN(MAX(self.panes.count, 1), 8) * self.table.rowHeight;
    [self.table reloadData];
}
@end
