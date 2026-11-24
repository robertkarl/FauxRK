#import "RKAttentionRowView.h"
#import "RKSidebarViews.h"

@interface RKAttentionDisclosure : NSButton
@property(nonatomic, copy) dispatch_block_t open;
@property(nonatomic, strong) NSColor *accent;
- (instancetype)initWithPaneTitle:(NSString *)title request:(NSDictionary *)request action:(dispatch_block_t)open;
@end

@implementation RKAttentionDisclosure
- (instancetype)initWithPaneTitle:(NSString *)title request:(NSDictionary *)request action:(dispatch_block_t)open {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _open = [open copy];
    BOOL input = [request[@"kind"] isEqual:@"input"];
    BOOL complete = [request[@"kind"] isEqual:@"complete"];
    NSString *status = input ? @"Blocker" : (complete ? @"Results" : @"May need input");
    NSString *symbol = input ? @"exclamationmark.circle.fill" : (complete ? @"checkmark.bubble" : @"questionmark.circle");
    _accent = RKTintColor(input ? RKTintRed : (complete ? RKTintViolet : RKTintAmber));
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
    NSString *detail = request[@"summary"] ?: request[@"question"] ?: @"";
    NSTextField *name = RKLabel(heading, 14, NSFontWeightSemibold);
    NSTextField *summary = RKLabel(detail, 12, NSFontWeightRegular);
    summary.textColor = [NSColor colorWithSRGBRed:.80 green:.83 blue:.89 alpha:1];
    NSStackView *labels = RKColumn(2);
    RKAddFullWidth(labels, name);
    if (detail.length) RKAddFullWidth(labels, summary);
    for (NSView *child in @[icon, labels, disclosure]) {
        child.translatesAutoresizingMaskIntoConstraints = NO;
        [child setAccessibilityElement:NO];
        [self addSubview:child];
    }
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:11],
        [icon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:23],
        [icon.heightAnchor constraintEqualToConstant:23],
        [labels.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:8],
        [labels.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
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

- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, 49); }
- (BOOL)acceptsFirstResponder { return YES; }
- (NSView *)hitTest:(NSPoint)point { return [super hitTest:point] ? self : nil; }
- (void)reveal:(id)sender { if (self.open) self.open(); }
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
@property(nonatomic, strong) NSDictionary *request;
@property(nonatomic, strong) NSStackView *body;
@property(nonatomic, strong) NSView *responses;
@end

@implementation RKAttentionRowView
- (instancetype)initWithPaneTitle:(NSString *)title request:(NSDictionary *)request action:(dispatch_block_t)open {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _request = [request copy];
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
    RKAddFullWidth(_body, disclosure);
    return self;
}

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
        RKActionButton *button = [RKActionButton title:label symbol:nil help:label tint:RKTintMuted action:^{
            if (weak.answerChoice) weak.answerChoice(choice);
        }];
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
            RKAddFullWidth(actions, button);
        }
    }
    if (inlineLayout) [actions addArrangedSubview:RKSpring()];
    self.responses = RKInset(actions, NSEdgeInsetsMake(0, 11, 9, 11));
    RKAddFullWidth(self.body, self.responses);
}
@end
