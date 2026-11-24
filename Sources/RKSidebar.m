#import "RKSidebar.h"
#import "RKAgentCardView.h"
#import "RKAttentionRowView.h"
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
@property (nonatomic, copy) NSString *hostID;
@property (nonatomic) NSUInteger hostGeneration;
@property (nonatomic) RKWorkspaceView *workspace;
@property (nonatomic) NSPopUpButton *hostPicker;
@property (nonatomic) RKActionButton *retry;
@property (nonatomic) NSStackView *offlineDetails;
@property (nonatomic) NSTextField *lastSeen;
@property (nonatomic) RKPanelView *attentionPanel;
@property (nonatomic) NSStackView *content;
@property (nonatomic) RKBadgeView *connection;
@property (nonatomic) NSTextField *feedback;
@property (nonatomic) RKPanelView *deliveryPanel;
@property (nonatomic) NSTextField *deliveryText;
@property (nonatomic) RKActionButton *pin;
@property (nonatomic) RKSpawnView *launcher;
@property (nonatomic) NSStackView *agentBody;
@property (nonatomic) NSStackView *attentionBody;
@property (nonatomic) RKBadgeView *requestCount;
@property (nonatomic) NSTextField *otherCount;
@property (nonatomic) NSTextField *noAgents;
@property (nonatomic) NSTextField *noRequests;
@property (nonatomic) NSTextField *noOther;
@property (nonatomic) RKDiscoveryView *discovery;
@property (nonatomic) RKPanelView *preview;
@property (nonatomic) NSTextField *previewTitle;
@property (nonatomic) NSTextField *previewText;
@property (nonatomic, copy) NSString *previewID;
@property (nonatomic, copy) NSString *previewTarget;
@property (nonatomic) NSMutableDictionary<NSString *, RKAgentCardView *> *cards;
@property (nonatomic) NSDictionary<NSString *, NSDictionary *> *paneByID;
@property (nonatomic) NSDictionary<NSString *, NSDictionary *> *requests;
@property (nonatomic) NSArray *attentionSnapshot;
@property (nonatomic) NSDictionary<NSArray *, NSView *> *attentionViews;
@end

@implementation RKSidebar
- (instancetype)initWithDelegate:(id<RKSidebarDelegate>)delegate {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,462,828)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    if (!(self = [super initWithWindow:window])) return nil;
    _actions = delegate;
    _hostID = @"local";
    _cards = [NSMutableDictionary dictionary];
    window.title = @"FauxRK";
    window.titlebarAppearsTransparent = YES;
    window.titleVisibility = NSWindowTitleHidden;
    window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    window.backgroundColor = [NSColor colorWithSRGBRed:.029 green:.038 blue:.052 alpha:1];
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
    self.workspace = [RKWorkspaceView new];
    NSView *root = self.workspace;
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
    RKAddFullWidth(frame, RKInset([self buildHeader], NSEdgeInsetsMake(3,16,8,16)));
    self.scroll = [NSScrollView new];
    self.scroll.hasVerticalScroller = YES;
    self.scroll.autohidesScrollers = YES;
    self.scroll.drawsBackground = NO;
    [self.scroll setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
    RKAddFullWidth(frame, self.scroll);
    RKFlippedDocument *doc = [RKFlippedDocument new];
    doc.translatesAutoresizingMaskIntoConstraints = NO;
    self.scroll.documentView = doc;
    self.content = RKColumn(13);
    self.content.translatesAutoresizingMaskIntoConstraints = NO;
    [doc addSubview:self.content];
    [NSLayoutConstraint activateConstraints:@[
        [doc.widthAnchor constraintEqualToAnchor:self.scroll.contentView.widthAnchor],
        [doc.leadingAnchor constraintEqualToAnchor:self.scroll.contentView.leadingAnchor],
        [doc.topAnchor constraintEqualToAnchor:self.scroll.contentView.topAnchor],
        [self.content.leadingAnchor constraintEqualToAnchor:doc.leadingAnchor constant:14],
        [self.content.trailingAnchor constraintEqualToAnchor:doc.trailingAnchor constant:-14],
        [self.content.topAnchor constraintEqualToAnchor:doc.topAnchor constant:3],
        [self.content.bottomAnchor constraintEqualToAnchor:doc.bottomAnchor constant:-16],
    ]];
    self.launcher = [[RKSpawnView alloc] initWithDelegate:self.actions remote:[self.hostID isEqual:@"debra"]];
    self.launcher.hidden = YES;
    RKAddFullWidth(self.content, self.launcher);
    [self buildSections];
}

- (NSView *)buildHeader {
    __weak typeof(self) weak = self;
    NSStackView *column = RKColumn(7);
    NSStackView *top = RKRow(7);
    [top addArrangedSubview:RKLabel(@"Agent Control", 25, NSFontWeightBold)];
    [top addArrangedSubview:RKSpring()];
    self.pin = [RKActionButton title:@"" symbol:@"pin" help:@"Keep on Top" tint:RKTintMuted action:^{
        [weak setPinned:weak.window.level != NSFloatingWindowLevel];
    }];
    self.pin.availableOffline = YES;
    RKActionButton *spawn = [RKActionButton title:@"Spawn Agent" symbol:@"plus" help:@"Spawn Agent" tint:RKTintViolet action:^{
        if (weak.launcher.hidden) [weak showSpawn]; else weak.launcher.hidden = YES;
    }];
    spawn.availableOffline = YES;
    [top addArrangedSubview:spawn];
    RKAddFullWidth(column, top);
    self.connection = [[RKBadgeView alloc] initWithText:@"Connecting to tmux…" tint:RKTintMuted showsDot:YES];
    self.connection.neutralSurface = YES;
    NSStackView *state = RKRow(8);
    self.hostPicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.hostPicker addItemsWithTitles:@[@"This Mac", @"Debra"]];
    [self.hostPicker selectItemAtIndex:[self.hostID isEqual:@"debra"] ? 1 : 0];
    self.hostPicker.controlSize = NSControlSizeSmall;
    self.hostPicker.accessibilityIdentifier = @"host-picker";
    self.hostPicker.accessibilityLabel = @"Computer";
    self.hostPicker.toolTip = @"Computer whose tmux agents are shown";
    self.hostPicker.target = self;
    self.hostPicker.action = @selector(changeHost:);
    [state addArrangedSubview:self.hostPicker];
    self.connection.accessibilityIdentifier = @"host-status";
    [state addArrangedSubview:self.connection];
    [state addArrangedSubview:RKSpring()];
    self.retry = [RKActionButton title:@"Retry" symbol:@"arrow.clockwise" help:@"Retry connection" tint:RKTintAmber action:^{
        [weak.actions retryConnection];
    }];
    self.retry.availableOffline = YES;
    self.retry.accessibilityIdentifier = @"host-retry";
    self.pin.plainAppearance = YES;
    [state addArrangedSubview:self.pin];
    RKAddFullWidth(column, state);
    self.offlineDetails = RKRow(6);
    self.offlineDetails.hidden = YES;
    self.lastSeen = RKDetail(@"");
    self.lastSeen.accessibilityIdentifier = @"host-last-seen";
    [self.offlineDetails addArrangedSubview:self.lastSeen];
    [self.offlineDetails addArrangedSubview:RKSpring()];
    [self.offlineDetails addArrangedSubview:self.retry];
    RKAddFullWidth(column, self.offlineDetails);
    self.feedback = RKDetail(@"");
    self.feedback.accessibilityIdentifier = @"transient-status";
    self.feedback.maximumNumberOfLines = 3;
    self.feedback.lineBreakMode = NSLineBreakByWordWrapping;
    self.feedback.hidden = YES;
    self.feedback.textColor = RKTintColor(RKTintAmber);
    RKAddFullWidth(column, self.feedback);
    RKAddFullWidth(column, [self buildDeliveryNotice]);
    return column;
}

- (NSView *)buildDeliveryNotice {
    self.deliveryPanel = [[RKPanelView alloc] initWithTint:RKTintAmber];
    self.deliveryPanel.tintsSurface = YES;
    self.deliveryPanel.hidden = YES;
    NSStackView *row = RKRow(6);
    row.distribution = NSStackViewDistributionFill;
    self.deliveryText = [NSTextField wrappingLabelWithString:@""];
    self.deliveryText.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    self.deliveryText.textColor = RKTintColor(RKTintAmber);
    self.deliveryText.accessibilityIdentifier = @"delivery-notice";
    self.deliveryText.preferredMaxLayoutWidth = 230;
    [self.deliveryText setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [row addArrangedSubview:self.deliveryText];
    __weak typeof(self) weak = self;
    RKActionButton *dismiss = [RKActionButton title:@"" symbol:@"xmark" help:@"Dismiss delivery notice" tint:RKTintMuted action:^{
        [weak.actions dismissDeliveryNotice];
    }];
    dismiss.availableOffline = YES;
    dismiss.accessibilityIdentifier = @"dismiss-delivery-notice";
    [row addArrangedSubview:dismiss];
    RKAddFullWidth(self.deliveryPanel.body, row);
    return self.deliveryPanel;
}

- (void)showDeliveryNotice:(NSString *)notice {
    self.deliveryText.stringValue = notice ?: @"";
    self.deliveryPanel.hidden = !notice.length;
}

- (void)changeHost:(NSPopUpButton *)picker {
    NSString *hostID = picker.indexOfSelectedItem == 1 ? @"debra" : @"local";
    if ([hostID isEqual:self.hostID]) return;
    [self switchToHost:hostID];
    [self.actions selectHost:hostID];
}

- (void)switchToHost:(NSString *)hostID {
    if (![@[@"local", @"debra"] containsObject:hostID] || [hostID isEqual:self.hostID]) return;
    self.hostGeneration++;
    for (NSWindow *sheet in self.window.sheets.copy) [self.window endSheet:sheet returnCode:NSModalResponseCancel];
    [self.window makeFirstResponder:nil];
    self.hostID = hostID;
    [self.cards removeAllObjects];
    self.previewID = nil;
    self.previewTarget = nil;
    self.attentionViews = nil;
    self.attentionSnapshot = nil;
    [self buildLayout];
    [self displayPanes:@[] attention:@{}];
    self.workspace.disconnected = YES;
    self.connection.stringValue = @"Connecting…";
    self.connection.tint = RKTintMuted;
    [self setPinned:self.window.level == NSFloatingWindowLevel];
}

- (void)showDisconnectedLastSeen:(NSDate *)date {
    self.workspace.disconnected = YES;
    self.offlineDetails.hidden = NO;
    self.connection.tint = RKTintAmber;
    self.connection.stringValue = @"Disconnected";
    NSString *stamp = date ? [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle] : nil;
    self.lastSeen.stringValue = stamp ? [@"Last seen " stringByAppendingString:stamp] : @"Waiting for the first connection.";
    self.lastSeen.toolTip = self.lastSeen.stringValue;
}

- (void)revealAttention {
    [self scrollTo:self.attentionPanel];
    RKAttentionRowView *first = self.attentionBody.arrangedSubviews.firstObject;
    [first focusForReview];
}

- (void)setPinned:(BOOL)pinned {
    self.window.level = pinned ? NSFloatingWindowLevel : NSNormalWindowLevel;
    self.pin.image = [NSImage imageWithSystemSymbolName:pinned ? @"pin.fill" : @"pin" accessibilityDescription:nil];
    self.pin.contentTintColor = RKTintColor(pinned ? RKTintViolet : RKTintMuted);
    self.pin.toolTip = pinned ? @"Turn off Keep on Top" : @"Keep on Top";
    [NSUserDefaults.standardUserDefaults setBool:pinned forKey:@"RKKeepOnTop"];
}

- (RKPanelView *)section:(NSString *)title symbol:(NSString *)symbol tint:(RKTint)tint count:(NSView *)count action:(NSView *)action {
    RKPanelView *panel = [[RKPanelView alloc] initWithTint:RKTintMuted];
    panel.showsAccentRail = NO;
    panel.body.spacing = 7;
    NSStackView *row = RKRow(6);
    NSImageView *icon = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil]];
    icon.contentTintColor = RKTintColor(tint);
    [row addArrangedSubview:icon];
    [row addArrangedSubview:RKLabel(title, 16, NSFontWeightBold)];
    [row addArrangedSubview:count];
    [row addArrangedSubview:RKSpring()];
    if (action) [row addArrangedSubview:action];
    RKAddFullWidth(panel.body, row);
    RKAddFullWidth(self.content, panel);
    return panel;
}

- (void)buildSections {
    self.agentBody = RKColumn(6);
    RKAddFullWidth(self.content, self.agentBody);
    self.noAgents = RKDetail(@"Spawn an agent or capture a pane to start.");
    RKAddFullWidth(self.content, self.noAgents);
    [self buildDiscovery];
    [self buildAttention];
}

- (void)buildDiscovery {
    __weak typeof(self) weak = self;
    RKActionButton *sort = [RKActionButton title:@"Sort by activity" symbol:@"arrow.up.arrow.down" help:@"Sort other panes by current activity" tint:RKTintMuted action:^{
        [weak.actions sortPanesByActivity];
    }];
    self.otherCount = RKDetail(@"");
    RKPanelView *panel = [self section:@"Other tmux panes" symbol:@"square.on.square" tint:RKTintMuted count:self.otherCount action:sort];
    [self buildPreviewIn:panel.body];
    self.discovery = [[RKDiscoveryView alloc] initWithDelegate:self.actions];
    RKAddFullWidth(panel.body, self.discovery);
    self.noOther = RKDetail(@"No uncaptured panes.");
    RKAddFullWidth(panel.body, self.noOther);
}

- (void)buildAttention {
    self.requestCount = [[RKBadgeView alloc] initWithText:@"0" tint:RKTintRed showsDot:NO];
    RKPanelView *panel = [self section:@"Needs attention" symbol:@"bolt.fill" tint:RKTintAmber count:self.requestCount action:nil];
    self.attentionPanel = panel;
    panel.accessibilityIdentifier = @"needs-attention";
    self.attentionBody = RKColumn(6);
    RKAddFullWidth(panel.body, self.attentionBody);
    self.noRequests = RKDetail(@"No requests waiting.");
    RKAddFullWidth(panel.body, self.noRequests);
}

- (void)buildPreviewIn:(NSStackView *)column {
    self.preview = [[RKPanelView alloc] initWithTint:RKTintBlue];
    self.previewTitle = RKLabel(@"Pane preview", 13, NSFontWeightSemibold);
    NSStackView *head = RKRow(5);
    [head addArrangedSubview:self.previewTitle];
    [head addArrangedSubview:RKSpring()];
    __weak typeof(self) weak = self;
    [head addArrangedSubview:[RKActionButton title:@"Capture" symbol:@"plus" help:@"Capture previewed pane" tint:RKTintBlue action:^{
        if (weak.previewID && [weak.previewTarget isEqual:weak.paneByID[weak.previewID][@"target"]]) [weak.actions capturePane:weak.previewID];
    }]];
    RKActionButton *close = [RKActionButton title:@"" symbol:@"xmark" help:@"Close preview" tint:RKTintMuted action:^{
        weak.preview.hidden = YES;
        weak.previewID = nil;
    }];
    close.availableOffline = YES;
    [head addArrangedSubview:close];
    RKAddFullWidth(self.preview.body, head);
    self.previewText = RKLabel(@"", 12.5, NSFontWeightRegular);
    self.previewText.usesSingleLineMode = NO;
    self.previewText.lineBreakMode = NSLineBreakByWordWrapping;
    self.previewText.selectable = YES;
    RKAddFullWidth(self.preview.body, self.previewText);
    self.preview.hidden = YES;
    RKAddFullWidth(column, self.preview);
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
    self.workspace.disconnected = NO;
    self.offlineDetails.hidden = YES;
    self.paneByID = index;
    self.requests = attention.copy;
    self.connection.stringValue = panes.count ? [NSString stringWithFormat:@"tmux · %lu session%@, %lu pane%@", (unsigned long)sessions.count, sessions.count == 1 ? @"" : @"s", (unsigned long)panes.count, panes.count == 1 ? @"" : @"s"] : @"No tmux sessions";
    self.connection.tint = panes.count ? RKTintMint : RKTintMuted;
    [self updateCards:managed];
    [self updateAttention:managed];
    self.otherCount.stringValue = [NSString stringWithFormat:@"(%lu)", (unsigned long)others.count];
    self.discovery.hidden = !others.count;
    self.noOther.hidden = others.count > 0;
    [self.discovery displayPanes:others];
    if (self.previewID && (![self.previewTarget isEqual:index[self.previewID][@"target"]] || [index[self.previewID][@"managed"] boolValue])) {
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
        NSString *identity = pane[@"target"] ?: pane[@"rkID"] ?: paneID;
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
    self.noAgents.hidden = visible.count > 0;
    self.agentBody.hidden = !visible.count;
}

- (void)updateAttention:(NSArray *)managed {
    NSMutableArray *snapshot = [NSMutableArray array];
    NSMutableArray *results = [NSMutableArray array];
    for (NSDictionary *pane in managed) {
        NSDictionary *request = self.requests[pane[@"id"]];
        if (!request) continue;
        NSMutableArray *section = [request[@"kind"] isEqual:@"complete"] ? results : snapshot;
        [section addObject:@[pane[@"id"], RKPaneTitle(pane), request.copy, pane[@"target"] ?: pane[@"rkID"] ?: pane[@"id"]]];
    }
    [snapshot addObjectsFromArray:results];
    if ([snapshot isEqual:self.attentionSnapshot]) return;
    self.attentionSnapshot = snapshot;
    NSMutableArray *rows = [NSMutableArray array];
    NSMutableDictionary *views = [NSMutableDictionary dictionaryWithCapacity:snapshot.count];
    for (NSArray *entry in snapshot) {
        NSView *row = self.attentionViews[entry] ?: [self attentionRow:entry];
        views[entry] = row;
        [rows addObject:row];
    }
    self.attentionViews = views;
    RKReplaceChildren(self.attentionBody, rows);
    self.requestCount.stringValue = [@(rows.count) stringValue];
    self.requestCount.tint = rows.count ? RKTintRed : RKTintMuted;
    self.attentionBody.hidden = !rows.count;
    self.noRequests.hidden = rows.count > 0;
}

- (NSView *)attentionRow:(NSArray *)entry {
    NSString *paneID = entry[0];
    __weak typeof(self) weak = self;
    NSDictionary *request = entry[2];
    RKAttentionRowView *row = [[RKAttentionRowView alloc] initWithPaneTitle:entry[1] request:request action:^{
        [weak revealPane:paneID];
    }];
    row.answerChoice = ^(NSDictionary *choice) {
        if (![weak.cards[paneID].identifier isEqual:entry[3]]) return;
        [weak.actions answerPane:paneID fingerprint:request[@"fingerprint"] choice:choice];
    };
    return row;
}

- (void)confirmEnd:(NSString *)paneID {
    NSDictionary *pane = self.paneByID[paneID];
    if (!pane || self.workspace.disconnected) return;
    NSUInteger generation = self.hostGeneration;
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = [NSString stringWithFormat:@"End %@?", RKPaneTitle(pane)];
    alert.informativeText = [NSString stringWithFormat:@"FauxRK will send two interrupts and close the tmux session “%@”.",pane[@"session"]];
    [alert addButtonWithTitle:@"Cancel"];
    NSButton *end = [alert addButtonWithTitle:@"End Session"];
    end.hasDestructiveAction = YES;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSAlertSecondButtonReturn || self.workspace.disconnected || generation != self.hostGeneration) return;
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
    if (self.workspace.disconnected || !self.paneByID[paneID] || [self.paneByID[paneID][@"managed"] boolValue]) return;
    self.previewID = paneID;
    self.previewTarget = self.paneByID[paneID][@"target"];
    self.previewTitle.stringValue = RKPaneTitle(self.paneByID[paneID]);
    self.previewText.stringValue = text;
    self.preview.hidden = NO;
    [self scrollTo:self.preview];
}

- (void)showSpawnInProject:(NSString *)directory {
    BOOL chosen = [self.launcher chooseProject:directory];
    [self showSpawn];
    if (!chosen) [self showStatus:@"Choose one of Debra’s three project directories."];
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
    if (!self.workspace.disconnected && [request[@"kind"] isEqual:@"complete"] && [request[@"fingerprint"] length]) {
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
