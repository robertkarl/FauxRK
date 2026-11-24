#import "RKAgentCardView.h"

NSString *RKPaneTitle(NSDictionary *pane) {
    for (NSString *field in @[@"title", @"window", @"session", @"command", @"id"]) {
        NSString *value = pane[field];
        if (value.length) return value;
    }
    return @"Agent";
}

NSString *RKRequestKind(NSDictionary *request) {
    NSDictionary *names = @{@"input":@"Needs input", @"maybe":@"May need input", @"complete":@"Turn complete"};
    return names[request[@"kind"] ?: @""] ?: @"Managed";
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

@interface RKAgentCardView ()
@property (nonatomic, weak) id<RKSidebarDelegate> delegate;
@property (nonatomic) RKActionButton *disclose;
@property (nonatomic) RKActionButton *steerButton;
@property (nonatomic) NSTextField *name;
@property (nonatomic) NSTextField *metadata;
@property (nonatomic) NSTextField *status;
@property (nonatomic) NSTextField *location;
@property (nonatomic) NSTextField *result;
@property (nonatomic) NSStackView *detail;
@property (nonatomic) NSStackView *questionBody;
@property (nonatomic) NSTextField *questionLabel;
@property (nonatomic) RKPromptView *composer;
@property (nonatomic) RKPromptView *reply;
@property (nonatomic, copy) NSDictionary *request;
@property (nonatomic, copy) NSString *latestResult;
@end

@implementation RKAgentCardView
- (instancetype)initWithPaneID:(NSString *)paneID delegate:(id<RKSidebarDelegate>)delegate {
    if (!(self = [super initWithTint:RKTintMint])) return nil;
    _paneID = [paneID copy];
    _delegate = delegate;
    _name = RKLabel(@"", 14, NSFontWeightSemibold);
    _status = RKDetail(@"");
    _metadata = RKDetail(@"");
    _detail = RKColumn(9);
    _detail.hidden = YES;
    [self buildHeader];
    [self buildExpandedBody];
    return self;
}

- (void)buildHeader {
    __weak typeof(self) weak = self;
    _disclose = [RKActionButton title:@"" symbol:@"chevron.right" help:@"Show or hide agent details" tint:RKTintMint action:^{
        if (weak.expanded) weak.expanded = NO;
        else if (weak.openCard) weak.openCard();
    }];
    [_disclose setAccessibilityIdentifier:[@"agent-" stringByAppendingString:_paneID]];
    NSStackView *row = RKRow(6);
    [row addArrangedSubview:_disclose];
    [row addArrangedSubview:_name];
    [row addArrangedSubview:RKSpring()];
    [row addArrangedSubview:[RKActionButton title:@"" symbol:@"stop.fill" help:@"Interrupt · send Ctrl-C" tint:RKTintAmber action:^{
        [weak.delegate interruptPane:weak.paneID];
    }]];
    [row addArrangedSubview:[RKActionButton title:@"" symbol:@"xmark" help:@"End session…" tint:RKTintRed action:^{
        if (weak.requestEnd) weak.requestEnd();
    }]];
    RKAddFullWidth(self.body, row);
    NSStackView *info = RKRow(8);
    [info addArrangedSubview:_status];
    [info addArrangedSubview:_metadata];
    RKAddFullWidth(self.body, info);
}

- (void)buildExpandedBody {
    __weak typeof(self) weak = self;
    _location = RKDetail(@"");
    RKAddFullWidth(_detail, _location);
    _result = WrappedLabel(12.5);
    _result.hidden = YES;
    RKAddFullWidth(_detail, _result);
    _questionBody = RKColumn(7);
    RKAddFullWidth(_detail, _questionBody);
    _composer = [[RKPromptView alloc] initWithHint:@"Message this agent…"];
    [_composer.editor setAccessibilityIdentifier:[@"steer-" stringByAppendingString:self.paneID]];
    RKAddFullWidth(_detail, _composer);
    NSStackView *actions = RKRow(4);
    [actions addArrangedSubview:[RKActionButton title:@"Open in New Window" symbol:@"macwindow" help:@"Attach in a new iTerm2 window" tint:RKTintMuted action:^{
        [weak.delegate openTerminalForPane:weak.paneID];
    }]];
    [actions addArrangedSubview:RKSpring()];
    self.steerButton = [RKActionButton title:@"Steer" symbol:@"arrow.up" help:@"Send steering message" tint:RKTintViolet action:^{
        NSString *text = weak.composer.editor.string;
        if ([text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) {
            [weak.delegate steerPane:weak.paneID text:text];
        }
    }];
    [actions addArrangedSubview:self.steerButton];
    RKAddFullWidth(_detail, actions);
    RKAddFullWidth(self.body, _detail);
}

- (void)setExpanded:(BOOL)expanded {
    _expanded = expanded;
    self.detail.hidden = !expanded;
    self.disclose.image = [NSImage imageWithSystemSymbolName:expanded ? @"chevron.down" : @"chevron.right" accessibilityDescription:nil];
}

- (void)updatePane:(NSDictionary *)pane request:(NSDictionary *)request {
    NSString *name = RKPaneTitle(pane);
    self.steerButton.enabled = ![request[@"choices"] count];
    self.steerButton.toolTip = self.steerButton.enabled ? @"Send steering message" : @"Answer the current menu before steering";
    self.name.stringValue = name;
    self.name.toolTip = name;
    self.metadata.stringValue = [pane[@"preset"] length] ? pane[@"preset"] : pane[@"command"] ?: @"";
    RKTint tint = RKRequestTint(request);
    [self setAccent:tint];
    self.status.stringValue = RKRequestKind(request);
    self.status.textColor = RKTintColor(tint);
    self.location.stringValue = [NSString stringWithFormat:@"%@   ·   %@", [pane[@"path"] stringByAbbreviatingWithTildeInPath] ?: @"", pane[@"session"] ?: @""];
    self.location.toolTip = self.location.stringValue;
    self.disclose.toolTip = [NSString stringWithFormat:@"Show or hide %@", name];
    if ([request[@"kind"] isEqual:@"complete"]) self.latestResult = request[@"summary"];
    self.result.stringValue = self.latestResult ?: @"";
    self.result.hidden = !self.latestResult.length || (request && ![request[@"kind"] isEqual:@"complete"]);
    if ([self.request isEqual:request] || (!self.request && !request)) return;
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

- (void)fillSuggestionIfEmpty {
    if (!self.reply.editor.string.length && [self.request[@"suggestedReply"] length]) {
        self.reply.editor.string = self.request[@"suggestedReply"];
        [self.reply.editor didChangeText];
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
    for (NSDictionary *choice in choices) [self addChoice:choice];
    if (!choices.count) [self addReply];
}

- (void)addChoice:(NSDictionary *)choice {
    __weak typeof(self) weak = self;
    // Bind the displayed fingerprint to this action, even when a poll replaces the card's request.
    NSString *fingerprint = self.request[@"fingerprint"];
    RKActionButton *button = [RKActionButton title:choice[@"label"] ?: @"Respond" symbol:nil help:choice[@"label"] tint:RKTintBlue action:^{
        [weak.delegate answerPane:weak.paneID fingerprint:fingerprint choice:choice];
    }];
    button.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.questionBody addArrangedSubview:button];
    [button.widthAnchor constraintLessThanOrEqualToAnchor:self.questionBody.widthAnchor].active = YES;
}

- (void)addReply {
    __weak typeof(self) weak = self;
    NSString *fingerprint = self.request[@"fingerprint"];
    self.reply = [[RKPromptView alloc] initWithHint:@"Reply to the request…"];
    [self.reply.editor setAccessibilityIdentifier:[@"reply-" stringByAppendingString:self.paneID]];
    RKAddFullWidth(self.questionBody, self.reply);
    [self fillSuggestionIfEmpty];
    RKActionButton *send = [RKActionButton title:@"Send reply" symbol:@"paperplane" help:@"Send edited reply to this request" tint:RKTintBlue action:^{
        NSString *reply = weak.reply.editor.string;
        if (![reply stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) return;
        [weak.delegate answerPane:weak.paneID fingerprint:fingerprint choice:@{@"text":reply, @"label":@"Reply", @"draft":@YES}];
    }];
    [self.questionBody addArrangedSubview:send];
}

- (void)acknowledgeText:(NSString *)text {
    if (![self.composer.editor.string isEqualToString:text]) return;
    self.composer.editor.string = @"";
    [self.composer.editor didChangeText];
}
@end
