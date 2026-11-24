#import "RKAgentCardView.h"

NSString *RKPaneTitle(NSDictionary *pane) {
    if ([pane[@"capturedLabel"] length]) return pane[@"capturedLabel"];
    NSString *title = [pane[@"title"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *window = pane[@"window"] ?: @"";
    static NSSet<NSString *> *generic;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *host = NSProcessInfo.processInfo.hostName.lowercaseString ?: @"";
        generic = [NSSet setWithArray:@[@"",@"zsh",@"sh",@"bash",@"login",@"fish",@"node",@"codex",@"claude",@"claude.exe",
            @"agent",@"astra-medium",@"luna-medium",@"fable-medium",@"opus",host,host.stringByDeletingPathExtension]];
    });
    if (title.length && ![generic containsObject:title.lowercaseString]) return title;
    if (window.length && ![generic containsObject:window.lowercaseString]) return window;
    NSString *folder = [pane[@"path"] lastPathComponent];
    if (folder.length) return folder;
    if ([pane[@"session"] length]) return pane[@"session"];
    return title.length ? title : @"Agent";
}

NSString *RKRequestKind(NSDictionary *request) {
    NSDictionary *names = @{@"input":@"Needs input", @"maybe":@"May need input", @"complete":@"Turn complete"};
    return names[request[@"kind"] ?: @""] ?: @"Captured";
}

RKTint RKRequestTint(NSDictionary *request) {
    if ([request[@"kind"] isEqual:@"input"]) return RKTintRed;
    if ([request[@"kind"] isEqual:@"maybe"]) return RKTintAmber;
    if ([request[@"kind"] isEqual:@"complete"]) return RKTintBlue;
    return RKTintMint;
}

static NSTextField *WrappedLabel(CGFloat size) {
    NSTextField *label = RKLabel(@"", size, NSFontWeightRegular);
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.usesSingleLineMode = NO;
    label.maximumNumberOfLines = 0;
    label.selectable = YES;
    return label;
}

static RKTint AgentTint(NSDictionary *pane) {
    // The rail identifies a card even when its attention state changes.
    unsigned long long value = [[pane[@"id"] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"%"]] integerValue];
    NSUUID *identity = [[NSUUID alloc] initWithUUIDString:pane[@"rkID"] ?: @""];
    if (identity) {
        uuid_t bytes;
        [identity getUUIDBytes:bytes];
        value = bytes[0];
    }
    static RKTint const colors[] = {RKTintMint, RKTintBlue, RKTintViolet};
    return colors[value % 3];
}

static NSView *Fact(NSString *caption, NSString *symbol, NSTextField *value) {
    NSImageView *icon = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil]];
    icon.contentTintColor = RKTintColor(RKTintMuted);
    [icon setAccessibilityElement:NO];
    [icon.widthAnchor constraintEqualToConstant:14].active = YES;
    [icon.heightAnchor constraintEqualToConstant:13].active = YES;
    NSStackView *captionRow = RKRow(5);
    [captionRow addArrangedSubview:icon];
    [captionRow addArrangedSubview:RKDetail(caption)];
    NSStackView *column = RKColumn(4);
    [column addArrangedSubview:captionRow];
    RKAddFullWidth(column, value);
    return column;
}

@interface RKAgentCardView () <NSTextViewDelegate>
@property (nonatomic, weak) id<RKSidebarDelegate> delegate;
@property (nonatomic) RKActionButton *disclose;
@property (nonatomic) RKActionButton *steerButton;
@property (nonatomic) RKActionButton *terminalButton;
@property (nonatomic) NSTextField *name;
@property (nonatomic) NSTextField *metadata;
@property (nonatomic) RKBadgeView *status;
@property (nonatomic) RKActionButton *interruptButton;
@property (nonatomic) RKActionButton *endButton;
@property (nonatomic) NSStackView *titleColumn;
@property (nonatomic) NSView *header;
@property (nonatomic) NSView *controls;
@property (nonatomic) NSArray<NSLayoutConstraint *> *wideConstraints;
@property (nonatomic) NSLayoutConstraint *narrowConstraint;
@property (nonatomic) NSStackView *subtitle;
@property (nonatomic) BOOL wrappedHeader;
@property (nonatomic) NSTextField *folder;
@property (nonatomic) NSTextField *session;
@property (nonatomic) NSTextField *result;
@property (nonatomic) NSStackView *detail;
@property (nonatomic) NSStackView *questionBody;
@property (nonatomic) NSTextField *questionLabel;
@property (nonatomic) RKPromptView *composer;
@property (nonatomic) RKPromptView *reply;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *replyDraft;
@property (nonatomic, copy) NSString *initialReplyText;
@property (nonatomic, copy) NSDictionary *request;
@property (nonatomic, copy) NSString *latestResult;
@end

@implementation RKAgentCardView
- (instancetype)initWithPaneID:(NSString *)paneID delegate:(id<RKSidebarDelegate>)delegate {
    if (!(self = [super initWithTint:RKTintMint])) return nil;
    _paneID = [paneID copy];
    _delegate = delegate;
    _name = WrappedLabel(15.5);
    _name.selectable = NO;
    _name.font = [NSFont systemFontOfSize:15.5 weight:NSFontWeightBold];
    [_name setAccessibilityIdentifier:[@"agent-name-" stringByAppendingString:paneID]];
    _status = [[RKBadgeView alloc] initWithText:@"Captured" tint:RKTintMint showsDot:YES];
    [_status setAccessibilityIdentifier:[@"agent-status-" stringByAppendingString:paneID]];
    _metadata = RKDetail(@"");
    [_metadata setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    _detail = RKColumn(10);
    self.body.spacing = 12;
    _detail.hidden = YES;
    [self buildHeader];
    [self buildExpandedBody];
    self.expanded = NO;
    return self;
}

- (void)buildHeader {
    __weak typeof(self) weak = self;
    _disclose = [RKActionButton title:@"" symbol:@"chevron.right" help:@"Show or hide agent details" tint:RKTintMint action:^{
        if (weak.expanded) weak.expanded = NO;
        else if (weak.openCard) weak.openCard();
    }];
    [_disclose setAccessibilityIdentifier:[@"agent-" stringByAppendingString:_paneID]];
    _disclose.plainAppearance = YES;
    _disclose.availableOffline = YES;
    _interruptButton = [RKActionButton title:@"" symbol:@"stop.fill" help:@"Interrupt · send Ctrl-C" tint:RKTintAmber action:^{
        [weak.delegate interruptPane:weak.paneID];
    }];
    _endButton = [RKActionButton title:@"" symbol:@"xmark" help:@"End session…" tint:RKTintRed action:^{
        if (weak.requestEnd) weak.requestEnd();
    }];
    _interruptButton.accessibilityIdentifier = [@"card-interrupt-" stringByAppendingString:_paneID];
    _endButton.accessibilityIdentifier = [@"card-end-" stringByAppendingString:_paneID];
    NSStackView *controls = RKRow(5);
    [controls addArrangedSubview:_interruptButton];
    [controls addArrangedSubview:_endButton];
    _titleColumn = RKColumn(3);
    RKAddFullWidth(_titleColumn, _name);
    _subtitle = RKRow(7);
    [_subtitle addArrangedSubview:_metadata];
    RKAddFullWidth(_titleColumn, _subtitle);
    [_titleColumn setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_titleColumn setContentCompressionResistancePriority:250 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_status setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_status setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    _header = [NSView new];
    _controls = controls;
    for (NSView *view in @[_disclose,_titleColumn,_status,controls]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [_header addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
        [_disclose.leadingAnchor constraintEqualToAnchor:_header.leadingAnchor],
        [_disclose.centerYAnchor constraintEqualToAnchor:_header.centerYAnchor],
        [_titleColumn.leadingAnchor constraintEqualToAnchor:_disclose.trailingAnchor constant:6],
        [_titleColumn.topAnchor constraintEqualToAnchor:_header.topAnchor],
        [_titleColumn.bottomAnchor constraintEqualToAnchor:_header.bottomAnchor],
        [controls.trailingAnchor constraintEqualToAnchor:_header.trailingAnchor],
        [controls.centerYAnchor constraintEqualToAnchor:_header.centerYAnchor],
        [controls.topAnchor constraintGreaterThanOrEqualToAnchor:_header.topAnchor],
        [controls.widthAnchor constraintEqualToConstant:_interruptButton.intrinsicContentSize.width + _endButton.intrinsicContentSize.width + controls.spacing]
    ]];
    _narrowConstraint = [controls.leadingAnchor constraintEqualToAnchor:_titleColumn.trailingAnchor constant:8];
    [self layOutWideStatus];
    RKAddFullWidth(self.body, _header);
    // The name is also a large disclosure target, adjacent to the chevron.
    [_name addGestureRecognizer:[[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(toggleCard:)]];
}

- (void)toggleCard:(id)sender {
    if (!self.window) return;
    if (self.expanded) self.expanded = NO;
    else if (self.openCard) self.openCard();
}

- (void)layOutWideStatus {
    if (self.status.superview != self.header) [self.header addSubview:self.status];
    self.status.translatesAutoresizingMaskIntoConstraints = NO;
    self.wideConstraints = @[
        [self.status.leadingAnchor constraintEqualToAnchor:self.titleColumn.trailingAnchor constant:8],
        [self.status.trailingAnchor constraintEqualToAnchor:self.controls.leadingAnchor constant:-8],
        [self.status.centerYAnchor constraintEqualToAnchor:self.header.centerYAnchor]
    ];
    [NSLayoutConstraint activateConstraints:self.wideConstraints];
}

- (void)layout {
    [super layout];
    if (self.bounds.size.width <= 0) return;
    BOOL compact = self.bounds.size.width < 380;
    if (compact != self.wrappedHeader) {
        self.wrappedHeader = compact;
        if (compact) {
            [NSLayoutConstraint deactivateConstraints:self.wideConstraints];
            [self.status removeFromSuperview];
            [self.subtitle addArrangedSubview:self.status];
            self.narrowConstraint.active = YES;
        } else {
            self.narrowConstraint.active = NO;
            [self.status removeFromSuperview];
            [self layOutWideStatus];
        }
    }
    // NSTextField can determine wrapping height once the stack allocates
    // the available width (including after a sidebar resize).
    for (NSTextField *label in @[self.name,self.folder,self.session]) {
        CGFloat width = NSWidth(label.bounds);
        if (width > 10 && fabs(label.preferredMaxLayoutWidth-width) > 1) label.preferredMaxLayoutWidth = width;
    }
}

- (void)buildExpandedBody {
    __weak typeof(self) weak = self;
    _folder = WrappedLabel(12);
    _session = WrappedLabel(12);
    _folder.lineBreakMode = NSLineBreakByCharWrapping;
    _session.lineBreakMode = NSLineBreakByCharWrapping;
    [_folder setAccessibilityIdentifier:[@"agent-folder-" stringByAppendingString:_paneID]];
    [_session setAccessibilityIdentifier:[@"agent-session-" stringByAppendingString:_paneID]];
    NSView *left = Fact(@"Folder", @"folder", _folder);
    NSView *right = Fact(@"tmux session / pane", @"rectangle.split.2x1", _session);
    NSBox *separator = [NSBox new];
    separator.boxType = NSBoxSeparator;
    [separator.widthAnchor constraintEqualToConstant:1].active = YES;
    NSView *facts = [NSView new];
    for (NSView *field in @[left,separator,right]) {
        field.translatesAutoresizingMaskIntoConstraints = NO;
        [facts addSubview:field];
    }
    [NSLayoutConstraint activateConstraints:@[
        [left.leadingAnchor constraintEqualToAnchor:facts.leadingAnchor],
        [left.topAnchor constraintEqualToAnchor:facts.topAnchor],
        [right.trailingAnchor constraintEqualToAnchor:facts.trailingAnchor],
        [right.topAnchor constraintEqualToAnchor:facts.topAnchor],
        [left.widthAnchor constraintEqualToAnchor:right.widthAnchor multiplier:0.9],
        [separator.leadingAnchor constraintEqualToAnchor:left.trailingAnchor constant:10],
        [separator.trailingAnchor constraintEqualToAnchor:right.leadingAnchor constant:-10],
        [separator.topAnchor constraintEqualToAnchor:facts.topAnchor],
        [separator.bottomAnchor constraintEqualToAnchor:facts.bottomAnchor],
        [facts.bottomAnchor constraintGreaterThanOrEqualToAnchor:left.bottomAnchor],
        [facts.bottomAnchor constraintGreaterThanOrEqualToAnchor:right.bottomAnchor]
    ]];
    NSView *factsPanel = RKInset(facts,NSEdgeInsetsMake(8,10,8,10));
    factsPanel.wantsLayer = YES;
    factsPanel.layer.backgroundColor = [NSColor colorWithWhite:0.17 alpha:0.16].CGColor;
    factsPanel.layer.borderColor = [RKTintColor(RKTintMuted) colorWithAlphaComponent:0.32].CGColor;
    factsPanel.layer.borderWidth = 1;
    factsPanel.layer.cornerRadius = 7;
    RKAddFullWidth(_detail, factsPanel);
    _result = WrappedLabel(12.5);
    _result.hidden = YES;
    RKAddFullWidth(_detail, _result);
    _questionBody = RKColumn(7);
    _questionBody.hidden = YES;
    RKAddFullWidth(_detail, _questionBody);
    NSStackView *steerCaption = RKRow(6);
    [steerCaption addArrangedSubview:RKLabel(@"Steer",13,NSFontWeightSemibold)];
    [steerCaption addArrangedSubview:RKSpring()];
    [steerCaption addArrangedSubview:RKDetail(@"Hold F10 to dictate")];
    RKAddFullWidth(_detail, steerCaption);
    _composer = [[RKPromptView alloc] initWithHint:@"Message this agent…"];
    [_composer.editor setAccessibilityIdentifier:[@"steer-" stringByAppendingString:self.paneID]];
    RKAddFullWidth(_detail, _composer);
    NSStackView *actions = RKRow(4);
    self.terminalButton = [RKActionButton title:@"Open in New Window" symbol:@"macwindow" help:@"Attach in a new iTerm2 window" tint:RKTintMuted action:^{
        [weak.delegate openTerminalForPane:weak.paneID];
    }];
    self.terminalButton.accessibilityIdentifier = [@"card-open-window-" stringByAppendingString:self.paneID];
    [actions addArrangedSubview:self.terminalButton];
    [actions addArrangedSubview:RKSpring()];
    self.steerButton = [RKActionButton title:@"Steer" symbol:@"arrow.up" help:@"Send steering message" tint:RKTintViolet action:^{
        NSString *text = weak.composer.editor.string.copy;
        if ([text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) {
            [weak.delegate steerPane:weak.paneID text:text];
        }
    }];
    self.steerButton.accessibilityIdentifier = [@"card-send-steer-" stringByAppendingString:self.paneID];
    [actions addArrangedSubview:self.steerButton];
    RKAddFullWidth(_detail, actions);
    RKAddFullWidth(self.body, _detail);
}

- (void)labelControl:(NSView *)control action:(NSString *)action {
    NSString *number = [self.paneID hasPrefix:@"%"] ? [self.paneID substringFromIndex:1] : self.paneID;
    control.accessibilityLabel = [NSString stringWithFormat:@"%@, %@, pane %@",action,self.name.stringValue,number];
}

- (void)updateDisclosureLabel {
    [self labelControl:self.disclose action:self.expanded ? @"Collapse agent details" : @"Expand agent details"];
}

- (void)updateControlLabels {
    [self updateDisclosureLabel];
    [self labelControl:self.interruptButton action:@"Interrupt with Control C"];
    [self labelControl:self.endButton action:@"End session"];
    [self labelControl:self.terminalButton action:@"Open in new iTerm2 window"];
    [self labelControl:self.steerButton action:@"Send steering message"];
    [self labelControl:self.composer.editor action:@"Steering message"];
    [self labelControl:self.reply.editor action:@"Reply to request"];
    for (NSView *view in self.questionBody.arrangedSubviews) {
        if ([view isKindOfClass:RKActionButton.class]) [self labelControl:view action:((RKActionButton *)view).title];
    }
}

- (void)setExpanded:(BOOL)expanded {
    _expanded = expanded;
    self.detail.hidden = !expanded;
    self.tintsSurface = expanded;
    [self.disclose setAccessibilityExpanded:expanded];
    [self updateDisclosureLabel];
    NSImage *glyph = [NSImage imageWithSystemSymbolName:expanded ? @"chevron.down" : @"circle.fill" accessibilityDescription:nil];
    self.disclose.image = [glyph imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:expanded ? 12 : 8 weight:NSFontWeightSemibold]];
}

- (void)updatePane:(NSDictionary *)pane request:(NSDictionary *)request {
    NSString *name = RKPaneTitle(pane);
    self.steerButton.enabled = ![request[@"choices"] count];
    self.steerButton.toolTip = self.steerButton.enabled ? @"Send steering message" : @"Answer the current menu before steering";
    if (![self.name.stringValue isEqual:name]) {
        self.name.stringValue = name;
        [self updateControlLabels];
    }
    self.name.toolTip = name;
    NSString *detail = [pane[@"preset"] length] ? pane[@"preset"] : pane[@"command"];
    if ([pane[@"capturedLabel"] length] && [pane[@"title"] length]) detail = pane[@"title"];
    self.metadata.stringValue = detail ?: @"";
    self.metadata.toolTip = self.metadata.stringValue;
    RKTint tint = RKRequestTint(request);
    RKTint identityTint = AgentTint(pane);
    [self setAccent:identityTint];
    self.disclose.contentTintColor = RKTintColor(identityTint);
    NSString *status = RKRequestKind(request);
    if (![self.status.stringValue isEqual:status]) self.status.stringValue = status;
    if (self.status.tint != tint) self.status.tint = tint;
    self.folder.stringValue = [pane[@"path"] stringByAbbreviatingWithTildeInPath] ?: @"";
    self.folder.toolTip = pane[@"path"];
    self.session.stringValue = [NSString stringWithFormat:@"%@ · %@",pane[@"session"] ?: @"",self.paneID];
    self.session.toolTip = [NSString stringWithFormat:@"%@ / %@ / %@",pane[@"session"] ?: @"",pane[@"window"] ?: @"",self.paneID];
    self.disclose.toolTip = [NSString stringWithFormat:@"Show or hide %@", name];
    if ([request[@"kind"] isEqual:@"complete"]) self.latestResult = request[@"summary"];
    self.result.stringValue = self.latestResult ?: @"";
    self.result.hidden = !self.latestResult.length || (request && ![request[@"kind"] isEqual:@"complete"]);
    if ([self.request isEqual:request] || (!self.request && !request)) return;
    if (self.reply && ![self.reply.editor.string isEqual:self.initialReplyText]) [self rememberReply];
    BOOL sameQuestion = [self.request[@"fingerprint"] isEqual:request[@"fingerprint"]];
    self.request = request.copy;
    if (sameQuestion && self.reply && [self requestAcceptsDraft]) {
        [self refreshQuestionText];
        [self fillSuggestionIfEmpty];
        return;
    }
    [self rebuildQuestion];
}

- (BOOL)requestAcceptsDraft {
    return self.request && ![self.request[@"kind"] isEqual:@"complete"]
        && ![self.request[@"responseSent"] boolValue] && ![self.request[@"choices"] count];
}

- (void)refreshQuestionText {
    self.questionLabel.stringValue = [self.request[@"question"] length] ? self.request[@"question"] : (self.request[@"summary"] ?: @"");
}

- (void)rememberReply {
    NSString *fingerprint = self.request[@"fingerprint"];
    if (fingerprint.length) self.replyDraft = @{fingerprint:self.reply.editor.string.copy};
}

- (void)textDidChange:(NSNotification *)notification {
    if (notification.object == self.reply.editor) [self rememberReply];
}

- (void)applyInitialReply:(NSString *)text {
    NSTextView *editor = self.reply.editor;
    self.initialReplyText = text;
    editor.delegate = nil;
    editor.string = text;
    [editor didChangeText];
    editor.delegate = self;
}

- (void)fillSuggestionIfEmpty {
    NSString *suggestion = self.request[@"suggestedReply"];
    NSString *fingerprint = self.request[@"fingerprint"];
    if (fingerprint && !self.replyDraft[fingerprint] && !self.reply.editor.string.length && suggestion.length) {
        [self applyInitialReply:suggestion];
    }
}

- (void)rebuildQuestion {
    for (NSView *view in self.questionBody.arrangedSubviews.copy) [view removeFromSuperview];
    self.reply = nil;
    BOOL show = self.request && ![self.request[@"kind"] isEqual:@"complete"];
    self.questionBody.hidden = !show;
    if (!show) return;
    self.questionLabel = WrappedLabel(13);
    [self refreshQuestionText];
    RKAddFullWidth(self.questionBody, self.questionLabel);
    if ([self.request[@"responseSent"] boolValue]) {
        [self.questionBody addArrangedSubview:RKDetail(@"Response sent · waiting for agent")];
        return;
    }
    NSArray *choices = self.request[@"choices"];
    for (NSUInteger index=0; index<choices.count; index++) [self addChoice:choices[index] atIndex:index];
    if (!choices.count) [self addReply];
}

- (void)addChoice:(NSDictionary *)choice atIndex:(NSUInteger)index {
    __weak typeof(self) weak = self;
    // Bind the displayed fingerprint to this action, even when a poll replaces the card's request.
    NSString *fingerprint = self.request[@"fingerprint"];
    RKActionButton *button = [RKActionButton title:choice[@"label"] ?: @"Respond" symbol:nil help:choice[@"label"] tint:RKTintBlue action:^{
        [weak.delegate answerPane:weak.paneID fingerprint:fingerprint choice:choice];
    }];
    button.maximumTitleWidth = 210;
    button.accessibilityIdentifier = [NSString stringWithFormat:@"card-choice-%@-%lu", self.paneID, (unsigned long)index];
    [self labelControl:button action:button.title];
    button.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.questionBody addArrangedSubview:button];
    [button.widthAnchor constraintLessThanOrEqualToAnchor:self.questionBody.widthAnchor].active = YES;
}

- (void)addReply {
    __weak typeof(self) weak = self;
    NSString *fingerprint = self.request[@"fingerprint"];
    self.reply = [[RKPromptView alloc] initWithHint:@"Reply to the request…"];
    [self.reply.editor setAccessibilityIdentifier:[@"reply-" stringByAppendingString:self.paneID]];
    [self labelControl:self.reply.editor action:@"Reply to request"];
    RKAddFullWidth(self.questionBody, self.reply);
    NSString *saved = fingerprint ? self.replyDraft[fingerprint] : nil;
    if (!saved) self.replyDraft = nil;
    [self applyInitialReply:saved ?: self.request[@"suggestedReply"] ?: @""];

    RKActionButton *send = [RKActionButton title:@"Send reply" symbol:@"paperplane" help:@"Send edited reply to this request" tint:RKTintBlue action:^{
        NSString *reply = weak.reply.editor.string.copy;
        if (![reply stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) return;
        [weak.delegate answerPane:weak.paneID fingerprint:fingerprint choice:@{@"text":reply, @"label":@"Reply", @"draft":@YES}];
    }];
    send.accessibilityIdentifier = [@"card-send-reply-" stringByAppendingString:self.paneID];
    [self labelControl:send action:send.title];
    [self.questionBody addArrangedSubview:send];
}

- (void)acknowledgeText:(NSString *)text {
    if (![self.composer.editor.string isEqualToString:text]) return;
    self.composer.editor.string = @"";
    [self.composer.editor didChangeText];
}
@end
