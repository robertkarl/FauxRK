#import "RKSidebarViews.h"
#import <QuartzCore/QuartzCore.h>

static NSColor *RKColor(CGFloat r, CGFloat g, CGFloat b) {
    return [NSColor colorWithSRGBRed:r green:g blue:b alpha:1];
}

NSColor *RKTintColor(RKTint tint) {
    switch (tint) {
        case RKTintViolet: return RKColor(.70,.65,1);
        case RKTintMint: return RKColor(.43,.90,.67);
        case RKTintAmber: return RKColor(.98,.78,.43);
        case RKTintRed: return RKColor(1,.56,.60);
        case RKTintBlue: return RKColor(.46,.76,1);
        default: return RKColor(.65,.68,.73);
    }
}

NSColor *RKSurface(void) { return RKColor(.082,.090,.111); }

NSTextField *RKLabel(NSString *text, CGFloat size, NSFontWeight weight) {
    NSTextField *label = [NSTextField labelWithString:text ?: @""];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = RKColor(.93,.94,.96);
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

NSTextField *RKDetail(NSString *text) {
    NSTextField *label = RKLabel(text, 11.5, NSFontWeightRegular);
    label.textColor = RKTintColor(RKTintMuted);
    return label;
}

static NSStackView *RKStack(NSInteger orientation, CGFloat spacing) {
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = orientation;
    stack.alignment = orientation == NSUserInterfaceLayoutOrientationVertical ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY;
    stack.spacing = spacing;
    stack.detachesHiddenViews = YES;
    return stack;
}

NSStackView *RKColumn(CGFloat spacing) { return RKStack(NSUserInterfaceLayoutOrientationVertical, spacing); }
NSStackView *RKRow(CGFloat spacing) { return RKStack(NSUserInterfaceLayoutOrientationHorizontal, spacing); }

NSView *RKSpring(void) {
    NSView *view = [[NSView alloc] init];
    [view setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [view setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    return view;
}

void RKAddFullWidth(NSStackView *column, NSView *child) {
    [column addArrangedSubview:child];
    [child.widthAnchor constraintEqualToAnchor:column.widthAnchor].active = YES;
}

NSView *RKInset(NSView *child, NSEdgeInsets insets) {
    NSView *view = [[NSView alloc] init];
    child.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:child];
    [NSLayoutConstraint activateConstraints:@[
        [child.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:insets.left],
        [child.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-insets.right],
        [child.topAnchor constraintEqualToAnchor:view.topAnchor constant:insets.top],
        [child.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-insets.bottom],
    ]];
    return view;
}

void RKReplaceChildren(NSStackView *stack, NSArray<NSView *> *children) {
    if ([stack.arrangedSubviews isEqualToArray:children]) return;
    NSSet *keep = [NSSet setWithArray:children];
    for (NSView *view in stack.arrangedSubviews.copy) {
        if (![keep containsObject:view]) [view removeFromSuperview];
    }
    [children enumerateObjectsUsingBlock:^(NSView *view, NSUInteger index, BOOL *stop) {
        if (index < stack.arrangedSubviews.count && stack.arrangedSubviews[index] == view) return;
        [view removeFromSuperview];
        [stack insertArrangedSubview:view atIndex:index];
        [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }];
}

@interface RKActionButton ()
@property (nonatomic, copy) dispatch_block_t invoke;
@end

@implementation RKActionButton
+ (instancetype)title:(NSString *)title symbol:(NSString *)symbol help:(NSString *)help tint:(RKTint)tint action:(dispatch_block_t)action {
    RKActionButton *button = [self new];
    button.title = title;
    button.bezelStyle = NSBezelStyleRounded;
    button.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    button.controlSize = NSControlSizeSmall;
    button.contentTintColor = RKTintColor(tint);
    if (symbol.length) {
        button.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
        button.imagePosition = title.length ? NSImageLeading : NSImageOnly;
    }
    button.toolTip = help;
    [button setAccessibilityLabel:help.length ? help : title];
    button.target = button;
    button.action = @selector(performAction:);
    button.invoke = action;
    [button setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    return button;
}
- (void)performAction:(id)sender { if (self.invoke) self.invoke(); }
@end

@interface RKPanelView ()
@property (nonatomic) NSView *stripe;
@property (nonatomic, readwrite) NSStackView *body;
@end

@implementation RKPanelView
- (instancetype)initWithTint:(RKTint)tint {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    self.wantsLayer = YES;
    self.layer.backgroundColor = RKSurface().CGColor;
    self.layer.borderColor = RKColor(.20,.22,.27).CGColor;
    self.layer.borderWidth = 1;
    self.layer.cornerRadius = 9;
    self.layer.masksToBounds = YES;
    _body = RKColumn(9);
    _body.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_body];
    _stripe = [[NSView alloc] init];
    _stripe.translatesAutoresizingMaskIntoConstraints = NO;
    _stripe.wantsLayer = YES;
    [self addSubview:_stripe];
    [self setAccent:tint];
    [NSLayoutConstraint activateConstraints:@[
        [_body.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:13],
        [_body.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-11],
        [_body.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
        [_body.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
        [_stripe.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_stripe.widthAnchor constraintEqualToConstant:3],
        [_stripe.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_stripe.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
    return self;
}
- (void)setAccent:(RKTint)tint { self.stripe.layer.backgroundColor = RKTintColor(tint).CGColor; }
@end

@interface RKPromptView ()
@property (nonatomic, readwrite) NSTextView *editor;
@property (nonatomic) NSTextField *placeholder;
@property (nonatomic) id changeObserver;
@end

@implementation RKPromptView
- (instancetype)initWithHint:(NSString *)hint {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    self.wantsLayer = YES;
    self.layer.backgroundColor = RKColor(.052,.058,.073).CGColor;
    self.layer.cornerRadius = 6;
    self.layer.borderWidth = 1;
    self.layer.borderColor = RKColor(.25,.27,.33).CGColor;
    NSScrollView *scroll = [NSScrollView new];
    scroll.drawsBackground = NO;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    _editor = [NSTextView new];
    _editor.richText = NO;
    _editor.drawsBackground = NO;
    _editor.font = [NSFont systemFontOfSize:13];
    _editor.textColor = NSColor.textColor;
    _editor.insertionPointColor = NSColor.whiteColor;
    _editor.textContainerInset = NSMakeSize(2, 3);
    _editor.textContainer.widthTracksTextView = YES;
    _editor.verticallyResizable = YES;
    _editor.horizontallyResizable = NO;
    _editor.autoresizingMask = NSViewWidthSizable;
    _editor.allowsUndo = YES;
    _editor.automaticQuoteSubstitutionEnabled = NO;
    _editor.automaticDashSubstitutionEnabled = NO;
    [_editor setAccessibilityLabel:hint];
    scroll.documentView = _editor;
    [self addSubview:scroll];
    _placeholder = RKDetail(hint);
    _placeholder.translatesAutoresizingMaskIntoConstraints = NO;
    _placeholder.font = _editor.font;
    [self addSubview:_placeholder];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:2],
        [scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-2],
        [scroll.topAnchor constraintEqualToAnchor:self.topAnchor constant:2],
        [scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-2],
        [_placeholder.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:9],
        [_placeholder.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-5],
        [_placeholder.topAnchor constraintEqualToAnchor:self.topAnchor constant:6],
        [self.heightAnchor constraintEqualToConstant:58]
    ]];
    __weak typeof(self) weakSelf = self;
    _changeObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSTextDidChangeNotification object:_editor queue:nil usingBlock:^(NSNotification *note) {
        weakSelf.placeholder.hidden = weakSelf.editor.string.length > 0;
    }];
    return self;
}
- (NSView *)hitTest:(NSPoint)point {
    NSView *hit = [super hitTest:point];
    return hit == self.placeholder ? self.editor : hit;
}
- (void)dealloc { if (_changeObserver) [NSNotificationCenter.defaultCenter removeObserver:_changeObserver]; }
@end
