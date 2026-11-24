#import "RKSidebar.h"
#import "RKAgentCardView.h"
#import "RKDiscoveryView.h"
#import "RKSpawnView.h"

@interface RKFlippedDocument : NSView
@end
@implementation RKFlippedDocument
- (BOOL)isFlipped { return YES; }
@end

@interface RKSidebar ()
@property (nonatomic, weak) id<RKSidebarDelegate> actions;
@property (nonatomic) NSScrollView *scroll;
@property (nonatomic) NSStackView *content;
@property (nonatomic) NSTextField *connection;
@property (nonatomic) NSTextField *feedback;
@property (nonatomic) RKActionButton *pin;
@property (nonatomic) RKSpawnView *launcher;
@property (nonatomic) NSStackView *agentBody;
@property (nonatomic) NSStackView *attentionBody;
@property (nonatomic) NSTextField *agentCount;
@property (nonatomic) NSTextField *requestCount;
@property (nonatomic) NSTextField *otherCount;
@property (nonatomic) NSTextField *noAgents;
@property (nonatomic) NSTextField *noRequests;
@property (nonatomic) NSTextField *noOther;
@property (nonatomic) RKDiscoveryView *discovery;
@property (nonatomic) RKPanelView *preview;
@property (nonatomic) NSTextField *previewTitle;
@property (nonatomic) NSTextField *previewText;
@property (nonatomic, copy) NSString *previewID;
@property (nonatomic) NSMutableDictionary<NSString *, RKAgentCardView *> *cards;
@property (nonatomic) NSDictionary<NSString *, NSDictionary *> *paneByID;
@property (nonatomic) NSDictionary<NSString *, NSDictionary *> *requests;
@property (nonatomic) NSArray *attentionSnapshot;
@end

@implementation RKSidebar
- (instancetype)initWithDelegate:(id<RKSidebarDelegate>)delegate {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,420,780)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    if (!(self = [super initWithWindow:window])) return nil;
    _actions = delegate;
    _cards = [NSMutableDictionary dictionary];
    window.title = @"RK";
    window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    window.backgroundColor = [NSColor colorWithSRGBRed:.047 green:.051 blue:.065 alpha:1];
    window.contentMinSize = NSMakeSize(370, 390);
    if (![window setFrameUsingName:@"RKSidebarPlacement"]) {
        NSRect available = NSScreen.mainScreen.visibleFrame;
        NSRect frame = window.frame;
        frame.size.height = MIN(available.size.height - 16, frame.size.height);
        frame.origin = NSMakePoint(NSMinX(available) + 8, NSMaxY(available) - frame.size.height - 8);
        [window setFrame:frame display:NO];
    }
    [window setFrameAutosaveName:@"RKSidebarPlacement"];
    [self buildLayout];
    [self displayPanes:@[] attention:@{}];
    [self setPinned:[NSUserDefaults.standardUserDefaults boolForKey:@"RKKeepOnTop"]];
    return self;
}

- (void)buildLayout {
    NSStackView *frame = RKColumn(0);
    frame.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *root = [NSView new];
    root.wantsLayer = YES;
    root.layer.backgroundColor = self.window.backgroundColor.CGColor;
    self.window.contentView = root;
    [root addSubview:frame];
    [NSLayoutConstraint activateConstraints:@[
        [frame.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [frame.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [frame.topAnchor constraintEqualToAnchor:root.topAnchor],
        [frame.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
    ]];
    RKAddFullWidth(frame, RKInset([self buildHeader], NSEdgeInsetsMake(10,15,12,15)));
    NSBox *line = [NSBox new];
    line.boxType = NSBoxSeparator;
    RKAddFullWidth(frame, line);
    self.scroll = [NSScrollView new];
    self.scroll.hasVerticalScroller = YES;
    self.scroll.autohidesScrollers = YES;
    self.scroll.drawsBackground = NO;
    [self.scroll setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
    RKAddFullWidth(frame, self.scroll);
    RKFlippedDocument *doc = [RKFlippedDocument new];
    doc.translatesAutoresizingMaskIntoConstraints = NO;
    self.scroll.documentView = doc;
    self.content = RKColumn(12);
    self.content.translatesAutoresizingMaskIntoConstraints = NO;
    [doc addSubview:self.content];
    [NSLayoutConstraint activateConstraints:@[
        [doc.widthAnchor constraintEqualToAnchor:self.scroll.contentView.widthAnchor],
        [doc.leadingAnchor constraintEqualToAnchor:self.scroll.contentView.leadingAnchor],
        [doc.topAnchor constraintEqualToAnchor:self.scroll.contentView.topAnchor],
        [self.content.leadingAnchor constraintEqualToAnchor:doc.leadingAnchor constant:14],
        [self.content.trailingAnchor constraintEqualToAnchor:doc.trailingAnchor constant:-14],
        [self.content.topAnchor constraintEqualToAnchor:doc.topAnchor constant:13],
        [self.content.bottomAnchor constraintEqualToAnchor:doc.bottomAnchor constant:-16],
    ]];
    self.launcher = [[RKSpawnView alloc] initWithDelegate:self.actions];
    self.launcher.hidden = YES;
    RKAddFullWidth(self.content, self.launcher);
    [self buildSections];
}

- (NSView *)buildHeader {
    __weak typeof(self) weak = self;
    NSStackView *column = RKColumn(7);
    NSStackView *top = RKRow(7);
    [top addArrangedSubview:RKLabel(@"Agent Control", 22, NSFontWeightBold)];
    [top addArrangedSubview:RKSpring()];
    self.pin = [RKActionButton title:@"" symbol:@"pin" help:@"Keep on Top" tint:RKTintMuted action:^{
        [weak setPinned:weak.window.level != NSFloatingWindowLevel];
    }];
    [top addArrangedSubview:self.pin];
    [top addArrangedSubview:[RKActionButton title:@"Spawn Agent" symbol:@"plus" help:@"Spawn Agent" tint:RKTintViolet action:^{
        if (weak.launcher.hidden) [weak showSpawn]; else weak.launcher.hidden = YES;
    }]];
    RKAddFullWidth(column, top);
    self.connection = RKDetail(@"Connecting to local tmux…");
    RKAddFullWidth(column, self.connection);
    self.feedback = RKDetail(@"");
    self.feedback.maximumNumberOfLines = 3;
    self.feedback.lineBreakMode = NSLineBreakByWordWrapping;
    self.feedback.hidden = YES;
    self.feedback.textColor = RKTintColor(RKTintAmber);
    RKAddFullWidth(column, self.feedback);
    return column;
}

- (void)setPinned:(BOOL)pinned {
    self.window.level = pinned ? NSFloatingWindowLevel : NSNormalWindowLevel;
    self.pin.image = [NSImage imageWithSystemSymbolName:pinned ? @"pin.fill" : @"pin" accessibilityDescription:nil];
    self.pin.contentTintColor = RKTintColor(pinned ? RKTintViolet : RKTintMuted);
    self.pin.toolTip = pinned ? @"Turn off Keep on Top" : @"Keep on Top";
    [NSUserDefaults.standardUserDefaults setBool:pinned forKey:@"RKKeepOnTop"];
}

- (NSTextField *)section:(NSString *)title symbol:(NSString *)symbol tint:(RKTint)tint action:(NSButton *)action {
    NSStackView *row = RKRow(6);
    NSImageView *icon = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil]];
    icon.contentTintColor = RKTintColor(tint);
    [row addArrangedSubview:icon];
    [row addArrangedSubview:RKLabel(title, 14, NSFontWeightSemibold)];
    NSTextField *count = RKDetail(@"");
    [row addArrangedSubview:count];
    [row addArrangedSubview:RKSpring()];
    if (action) [row addArrangedSubview:action];
    RKAddFullWidth(self.content,row);
    return count;
}

- (void)buildSections {
    self.agentCount = [self section:@"Captured agents" symbol:@"terminal" tint:RKTintMint action:nil];
    self.agentBody = RKColumn(6);
    RKAddFullWidth(self.content, self.agentBody);
    self.noAgents = RKDetail(@"Spawn an agent or capture a tmux pane to start.");
    RKAddFullWidth(self.content, self.noAgents);
    self.requestCount = [self section:@"Needs attention" symbol:@"bolt.fill" tint:RKTintAmber action:nil];
    self.attentionBody = RKColumn(5);
    RKAddFullWidth(self.content, self.attentionBody);
    self.noRequests = RKDetail(@"No requests waiting.");
    RKAddFullWidth(self.content, self.noRequests);
    __weak typeof(self) weak = self;
    RKActionButton *sort = [RKActionButton title:@"Sort by activity" symbol:@"arrow.up.arrow.down" help:@"Sort other panes by current activity" tint:RKTintMuted action:^{
        [weak.actions sortPanesByActivity];
    }];
    self.otherCount = [self section:@"Other tmux panes" symbol:@"rectangle.on.rectangle" tint:RKTintBlue action:sort];
    [self buildPreview];
    self.discovery = [[RKDiscoveryView alloc] initWithDelegate:self.actions];
    RKAddFullWidth(self.content, self.discovery);
    self.noOther = RKDetail(@"No uncaptured panes.");
    RKAddFullWidth(self.content, self.noOther);
}

- (void)buildPreview {
    self.preview = [[RKPanelView alloc] initWithTint:RKTintBlue];
    self.previewTitle = RKLabel(@"Pane preview", 13, NSFontWeightSemibold);
    NSStackView *head = RKRow(5);
    [head addArrangedSubview:self.previewTitle];
    [head addArrangedSubview:RKSpring()];
    __weak typeof(self) weak = self;
    [head addArrangedSubview:[RKActionButton title:@"Capture" symbol:@"plus" help:@"Capture previewed pane" tint:RKTintBlue action:^{
        if (weak.previewID) [weak.actions capturePane:weak.previewID];
    }]];
    [head addArrangedSubview:[RKActionButton title:@"" symbol:@"xmark" help:@"Close preview" tint:RKTintMuted action:^{
        weak.preview.hidden = YES;
        weak.previewID = nil;
    }]];
    RKAddFullWidth(self.preview.body, head);
    self.previewText = RKLabel(@"", 12.5, NSFontWeightRegular);
    self.previewText.usesSingleLineMode = NO;
    self.previewText.lineBreakMode = NSLineBreakByWordWrapping;
    self.previewText.selectable = YES;
    RKAddFullWidth(self.preview.body, self.previewText);
    self.preview.hidden = YES;
    RKAddFullWidth(self.content, self.preview);
}

- (void)displayPanes:(NSArray<NSDictionary *> *)panes attention:(NSDictionary<NSString *,NSDictionary *> *)attention {
    NSMutableDictionary *index = [NSMutableDictionary dictionary];
    NSMutableArray *managed = [NSMutableArray array], *others = [NSMutableArray array];
    NSMutableSet *sessions = [NSMutableSet set];
    for (NSDictionary *pane in panes) {
        if (![pane[@"id"] length]) continue;
        index[pane[@"id"]] = pane;
        if (pane[@"session"]) [sessions addObject:pane[@"session"]];
        [([pane[@"managed"] boolValue] ? managed : others) addObject:pane];
    }
    self.paneByID = index;
    self.requests = attention.copy;
    self.connection.stringValue = [NSString stringWithFormat:@"Local tmux   ·   %lu session%@   ·   %lu pane%@", (unsigned long)sessions.count, sessions.count == 1 ? @"" : @"s", (unsigned long)panes.count, panes.count == 1 ? @"" : @"s"];
    self.connection.textColor = RKTintColor(panes.count ? RKTintMint : RKTintMuted);
    [self updateCards:managed];
    [self updateAttention:managed];
    self.otherCount.stringValue = [@(others.count) stringValue];
    self.discovery.hidden = !others.count;
    self.noOther.hidden = others.count > 0;
    [self.discovery displayPanes:others];
    if (self.previewID && (!index[self.previewID] || [index[self.previewID][@"managed"] boolValue])) {
        self.preview.hidden = YES;
        self.previewID = nil;
    }
}

- (void)updateCards:(NSArray *)managed {
    NSMutableArray *visible = [NSMutableArray array];
    NSMutableSet *ids = [NSMutableSet set];
    for (NSDictionary *pane in managed) {
        NSString *paneID = pane[@"id"];
        [ids addObject:paneID];
        RKAgentCardView *card = self.cards[paneID];
        NSString *identity = pane[@"target"] ?: paneID;
        if (card && ![card.identifier isEqual:identity]) card = nil;
        if (!card) {
            card = [[RKAgentCardView alloc] initWithPaneID:paneID delegate:self.actions];
            __weak typeof(self) weak = self;
            card.identifier = identity;
            card.requestEnd = ^{ [weak confirmEnd:paneID]; };
            card.openCard = ^{ [weak revealPane:paneID]; };
            self.cards[paneID] = card;
        }
        [card updatePane:pane request:self.requests[paneID]];
        [visible addObject:card];
    }
    for (NSString *paneID in self.cards.allKeys) {
        if (![ids containsObject:paneID]) [self.cards removeObjectForKey:paneID];
    }
    RKReplaceChildren(self.agentBody, visible);
    self.agentCount.stringValue = [@(visible.count) stringValue];
    self.noAgents.hidden = visible.count > 0;
    self.agentBody.hidden = !visible.count;
}

- (void)updateAttention:(NSArray *)managed {
    NSMutableArray *snapshot = [NSMutableArray array];
    for (NSDictionary *pane in managed) {
        NSDictionary *request = self.requests[pane[@"id"]];
        if (!request) continue;
        [snapshot addObject:@[pane[@"id"],RKPaneTitle(pane),RKRequestKind(request),request[@"summary"] ?: @"",request[@"kind"] ?: @""]];
    }
    if ([snapshot isEqual:self.attentionSnapshot]) return;
    self.attentionSnapshot = snapshot;
    NSMutableArray *rows = [NSMutableArray array];
    for (NSArray *entry in snapshot) [rows addObject:[self attentionRow:entry]];
    RKReplaceChildren(self.attentionBody, rows);
    self.requestCount.stringValue = [@(rows.count) stringValue];
    self.attentionBody.hidden = !rows.count;
    self.noRequests.hidden = rows.count > 0;
}

- (NSView *)attentionRow:(NSArray *)entry {
    NSString *paneID = entry[0];
    RKTint tint = RKRequestTint(@{@"kind":entry[4]});
    RKPanelView *row = [[RKPanelView alloc] initWithTint:tint];
    NSStackView *heading = RKRow(5);
    [heading addArrangedSubview:RKLabel(entry[1],13,NSFontWeightMedium)];
    [heading addArrangedSubview:RKSpring()];
    __weak typeof(self) weak = self;
    [heading addArrangedSubview:[RKActionButton title:entry[2] symbol:@"chevron.right" help:[NSString stringWithFormat:@"Open %@ for %@",entry[2],entry[1]] tint:tint action:^{
        [weak revealPane:paneID];
    }]];
    RKAddFullWidth(row.body, heading);
    NSTextField *summary = RKDetail(entry[3]);
    summary.toolTip = summary.stringValue;
    RKAddFullWidth(row.body, summary);
    return row;
}

- (void)confirmEnd:(NSString *)paneID {
    NSDictionary *pane = self.paneByID[paneID];
    if (!pane) return;
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = [NSString stringWithFormat:@"End %@?", RKPaneTitle(pane)];
    alert.informativeText = [NSString stringWithFormat:@"RK will send two interrupts and close the tmux session “%@”.",pane[@"session"]];
    [alert addButtonWithTitle:@"Cancel"];
    NSButton *end = [alert addButtonWithTitle:@"End Session"];
    end.hasDestructiveAction = YES;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSAlertSecondButtonReturn) return;
        if (![pane[@"target"] isEqual:self.paneByID[paneID][@"target"]]) {
            [self showStatus:@"The session changed while confirmation was open."];
            return;
        }
        [self.actions endPane:paneID];
    }];
}

- (void)showStatus:(NSString *)message {
    self.feedback.stringValue = message ?: @"";
    self.feedback.toolTip = message;
    self.feedback.hidden = !message.length;
}

- (void)showPreview:(NSString *)text forPane:(NSString *)paneID {
    if (!self.paneByID[paneID] || [self.paneByID[paneID][@"managed"] boolValue]) return;
    self.previewID = paneID;
    self.previewTitle.stringValue = RKPaneTitle(self.paneByID[paneID]);
    self.previewText.stringValue = text;
    self.preview.hidden = NO;
    [self scrollTo:self.preview];
}

- (void)showSpawnInProject:(NSString *)directory {
    [self.launcher chooseProject:directory];
    [self showSpawn];
}

- (void)showSpawn {
    self.launcher.hidden = NO;
    [self scrollTo:self.launcher];
}

- (void)revealPane:(NSString *)paneID {
    RKAgentCardView *card = self.cards[paneID];
    if (!card) return;
    card.expanded = YES;
    [self scrollTo:card];
    NSDictionary *request = self.requests[paneID];
    if ([request[@"kind"] isEqual:@"complete"] && [request[@"fingerprint"] length]) {
        [self.actions readAttentionForPane:paneID fingerprint:request[@"fingerprint"]];
    }
}

- (void)scrollTo:(NSView *)view {
    [self.window.contentView layoutSubtreeIfNeeded];
    [view scrollRectToVisible:view.bounds];
}

- (NSTextView *)focusedPromptEditor {
    if (!self.window.isKeyWindow) return nil;
    NSResponder *responder = self.window.firstResponder;
    if (![responder isKindOfClass:NSTextView.class]) return nil;
    NSTextView *editor = (NSTextView *)responder;
    for (NSView *parent = editor; parent; parent = parent.superview) {
        if ([parent isKindOfClass:RKPromptView.class] && !parent.hiddenOrHasHiddenAncestor) return editor;
    }
    return nil;
}

- (void)didSendText:(NSString *)text forPane:(NSString *)paneID { [self.cards[paneID] acknowledgeText:text]; }
- (void)didSpawnWithPrompt:(NSString *)prompt { [self.launcher acknowledgePrompt:prompt]; }
@end
