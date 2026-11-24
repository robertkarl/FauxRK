#import "RKAttentionRowView.h"
#import "RKSidebarViews.h"

@interface RKAttentionDisclosure : NSButton
@property(nonatomic, copy) dispatch_block_t open;
@property(nonatomic, strong) NSColor *accent;
@property(nonatomic, strong) NSTextField *headingLabel;
@property(nonatomic, strong) NSTextField *detailLabel;
- (instancetype)initWithPaneTitle:(NSString *)title request:(NSDictionary *)request action:(dispatch_block_t)open;
@end

@implementation RKAttentionDisclosure
- (instancetype)initWithPaneTitle:(NSString *)title request:(NSDictionary *)request action:(dispatch_block_t)open {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _open = [open copy];
    BOOL input = [request[@"kind"] isEqual:@"input"];
    BOOL complete = [request[@"kind"] isEqual:@"complete"];
    BOOL sent = [request[@"responseSent"] boolValue];
    NSString *status = sent ? @"Response sent" : input ? @"Blocker" : (complete ? @"Results" : @"May need input");
    NSString *symbol = sent ? @"paperplane.fill" : input ? @"exclamationmark.circle.fill" : (complete ? @"checkmark.bubble" : @"questionmark.circle");
    _accent = RKTintColor(sent ? RKTintMint : input ? RKTintRed : (complete ? RKTintViolet : RKTintAmber));
    self.bordered = NO;
    self.title = @"";
    self.focusRingType = NSFocusRingTypeExterior;
    self.target = self;
    self.action = @selector(reveal:);

    NSImageView *icon = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil]];
    icon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:19 weight:NSFontWeightSemibold];
    icon.contentTintColor = _accent;
    NSImageView *disclosure = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"chevron.right" accessibilityDescription:nil]];
    disclosure.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:11 weight:NSFontWeightSemibold];
    disclosure.contentTintColor = [NSColor colorWithWhite:.84 alpha:1];

    NSString *heading = [NSString stringWithFormat:@"%@ — %@", status, title];
    NSString *summary = request[@"summary"] ?: @"";
    NSString *question = request[@"question"] ?: @"";
    NSString *detail = complete ? summary : (question.length ? question : summary);
    self.headingLabel = RKLabel(heading, 14, NSFontWeightSemibold);
    self.detailLabel = RKLabel(detail, 12.5, NSFontWeightRegular);
    self.detailLabel.textColor = [NSColor colorWithSRGBRed:.83 green:.85 blue:.90 alpha:1];
    NSStackView *labels = RKColumn(3);
    for (NSTextField *label in @[self.headingLabel, self.detailLabel]) {
        label.usesSingleLineMode = NO;
        label.maximumNumberOfLines = 0;
        label.lineBreakMode = NSLineBreakByWordWrapping;
        label.preferredMaxLayoutWidth = 238;
        [label setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
        if (label.stringValue.length) RKAddFullWidth(labels, label);
    }
    if (sent) {
        NSTextField *wait = RKLabel(@"Waiting for the agent to continue", 11.5, NSFontWeightMedium);
        wait.textColor = _accent;
        RKAddFullWidth(labels, wait);
    }
    for (NSView *child in @[icon, labels, disclosure]) {
        child.translatesAutoresizingMaskIntoConstraints = NO;
        [child setAccessibilityElement:NO];
        [self addSubview:child];
    }
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:11],
        [icon.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
        [icon.widthAnchor constraintEqualToConstant:23],
        [icon.heightAnchor constraintEqualToConstant:23],
        [labels.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:8],
        [labels.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
        [labels.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],
        [labels.trailingAnchor constraintEqualToAnchor:disclosure.leadingAnchor constant:-8],
        [disclosure.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-11],
        [disclosure.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [disclosure.widthAnchor constraintEqualToConstant:9],
    ]];
    [self setAccessibilityLabel:heading];
    [self setAccessibilityHelp:detail];
    self.toolTip = detail.length ? [NSString stringWithFormat:@"%@\n%@",heading,detail] : heading;
    return self;
}

- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric); }
- (void)layout {
    [super layout];
    for (NSTextField *label in @[self.headingLabel, self.detailLabel]) {
        CGFloat width = NSWidth(label.bounds);
        if (width > 10 && fabs(width - label.preferredMaxLayoutWidth) > 1) label.preferredMaxLayoutWidth = width;
    }
}
- (BOOL)acceptsFirstResponder { return YES; }
- (NSView *)hitTest:(NSPoint)point { return [super hitTest:point] ? self : nil; }
- (void)reveal:(id)sender { if (self.window && self.open) self.open(); }
- (void)drawFocusRingMask { [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:8 yRadius:8] fill]; }
- (NSRect)focusRingMaskBounds { return self.bounds; }
- (void)drawRect:(NSRect)dirtyRect {
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, .5, .5) xRadius:8 yRadius:8];
    if (self.isHighlighted) {
        [[_accent colorWithAlphaComponent:.13] setFill];
        [shape fill];
    }
}
@end


@interface RKAttentionRowView ()
@property(nonatomic, copy) NSString *paneTitle;
@property(nonatomic, strong) NSDictionary *request;
@property(nonatomic, strong) NSStackView *body;
@property(nonatomic, strong) NSView *responses;
@property(nonatomic, strong) RKAttentionDisclosure *disclosure;
@end

@implementation RKAttentionRowView
- (instancetype)initWithPaneTitle:(NSString *)title request:(NSDictionary *)request action:(dispatch_block_t)open {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _request = [request copy];
    _paneTitle = [title copy];
    self.wantsLayer = YES;
    BOOL input = [request[@"kind"] isEqual:@"input"];
    BOOL complete = [request[@"kind"] isEqual:@"complete"];
    NSColor *accent = RKTintColor(input ? RKTintRed : (complete ? RKTintViolet : RKTintAmber));
    NSColor *surface = [NSColor colorWithSRGBRed:.075 green:.087 blue:.114 alpha:1];
    self.layer.backgroundColor = [surface blendedColorWithFraction:input ? .12 : .025 ofColor:accent].CGColor;
    self.layer.borderColor = [surface blendedColorWithFraction:input ? .78 : .48 ofColor:accent].CGColor;
    self.layer.borderWidth = 1;
    self.layer.cornerRadius = 8;
    _body = RKColumn(0);
    _body.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_body];
    [NSLayoutConstraint activateConstraints:@[
        [_body.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_body.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_body.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_body.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
    RKAttentionDisclosure *disclosure = [[RKAttentionDisclosure alloc] initWithPaneTitle:title request:request action:open];
    [disclosure setAccessibilityIdentifier:[NSString stringWithFormat:@"attention-open-%@",request[@"fingerprint"] ?: title]];
    _disclosure = disclosure;
    RKAddFullWidth(_body, disclosure);
    return self;
}

- (void)focusForReview { [self.window makeFirstResponder:self.disclosure]; }

- (void)setAnswerChoice:(void (^)(NSDictionary *))answerChoice {
    _answerChoice = [answerChoice copy];
    [self.responses removeFromSuperview];
    self.responses = nil;
    NSArray *choices = self.request[@"choices"];
    if (!answerChoice || !choices.count || ![self.request[@"choiceSource"] isEqual:@"terminal"] ||
        ![self.request[@"kind"] isEqual:@"input"] || [self.request[@"responseSent"] boolValue]) return;

    NSMutableArray<NSButton *> *buttons = [NSMutableArray new];
    CGFloat totalWidth = 0;
    __weak typeof(self) weak = self;
    for (NSDictionary *choice in choices) {
        NSString *label = choice[@"label"];
        if (!label.length) continue;
        NSString *normalized = label.lowercaseString;
        BOOL secondary = [@[@"type something.", @"chat about this", @"back"] containsObject:normalized];
        NSString *help = [NSString stringWithFormat:@"%@ — %@",label,self.paneTitle];
        // All substantive answers share an accent. A refusal has the same
        // weight as approval, and none of these controls is the default button.
        RKActionButton *button = [RKActionButton title:label symbol:nil help:help tint:secondary ? RKTintMuted : RKTintBlue action:^{
            if (weak.answerChoice) weak.answerChoice(choice);
        }];
        [button setAccessibilityIdentifier:[NSString stringWithFormat:@"attention-choice-%@-%lu",
            self.request[@"fingerprint"] ?: self.paneTitle, (unsigned long)buttons.count]];
        button.maximumTitleWidth = 210;
        button.keyEquivalent = @"";
        button.lineBreakMode = NSLineBreakByTruncatingTail;
        button.toolTip = label;
        [buttons addObject:button];
        totalWidth += button.intrinsicContentSize.width + 6;
    }
    if (!buttons.count) return;
    BOOL inlineLayout = totalWidth <= 245;
    NSStackView *actions = inlineLayout ? RKRow(6) : RKColumn(4);
    for (NSButton *button in buttons) {
        if (inlineLayout) {
            [actions addArrangedSubview:button];
        } else {
            [button setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
            [button setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
            RKAddFullWidth(actions, button);
        }
    }
    if (inlineLayout) [actions addArrangedSubview:RKSpring()];
    self.responses = RKInset(actions, NSEdgeInsetsMake(0, 11, 9, 11));
    RKAddFullWidth(self.body, self.responses);
}
@end
