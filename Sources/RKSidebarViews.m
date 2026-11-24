#import "RKSidebarViews.h"
#import <QuartzCore/QuartzCore.h>

static NSColor *RKColor(CGFloat r, CGFloat g, CGFloat b) {
    return [NSColor colorWithSRGBRed:r green:g blue:b alpha:1];
}

NSColor *RKTintColor(RKTint tint) {
    switch (tint) {
        case RKTintViolet: return RKColor(.72,.49,1);
        case RKTintMint: return RKColor(.32,.94,.50);
        case RKTintAmber: return RKColor(1,.79,.26);
        case RKTintRed: return RKColor(1,.35,.38);
        case RKTintBlue: return RKColor(.33,.67,1);
        default: return RKColor(.74,.77,.83);
    }
}

NSColor *RKSurface(void) { return RKColor(.056,.066,.088); }

NSTextField *RKLabel(NSString *text, CGFloat size, NSFontWeight weight) {
    NSTextField *label = [NSTextField labelWithString:text ?: @""];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = RKColor(.97,.975,.99);
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

static NSColor *RKBlend(NSColor *base, NSColor *accent, CGFloat amount) {
    return [base blendedColorWithFraction:amount ofColor:accent] ?: base;
}

static NSBezierPath *RKRoundedRect(NSRect bounds, CGFloat radius) {
    return [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, .65, .65) xRadius:radius yRadius:radius];
}

static void RKFillRim(NSBezierPath *shape, NSColor *top, NSColor *bottom, NSColor *rim, CGFloat weight) {
    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:top endingColor:bottom];
    [gradient drawInBezierPath:shape angle:-90];
    [rim setStroke];
    shape.lineWidth = weight;
    [shape stroke];
}

@interface RKBadgeView ()
@property (nonatomic) NSTextField *label;
@property (nonatomic) BOOL showsDot;
@end

@implementation RKBadgeView
- (instancetype)initWithText:(NSString *)text tint:(RKTint)tint showsDot:(BOOL)showsDot {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _tint = tint;
    _showsDot = showsDot;
    _label = RKLabel(@"", 11.5, NSFontWeightSemibold);
    _label.translatesAutoresizingMaskIntoConstraints = NO;
    [_label setAccessibilityElement:NO];
    [self addSubview:_label];
    [self setAccessibilityElement:YES];
    [self setAccessibilityRole:NSAccessibilityStaticTextRole];
    self.stringValue = text;
    [self updateInk];
    [NSLayoutConstraint activateConstraints:@[
        [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:showsDot ? 18 : 8],
        [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
    ]];
    return self;
}

- (void)setStringValue:(NSString *)value {
    _stringValue = [value copy] ?: @"";
    self.label.stringValue = _stringValue;
    self.toolTip = _stringValue;
    [self setAccessibilityValue:_stringValue];
    [self invalidateIntrinsicContentSize];
}

- (NSSize)intrinsicContentSize {
    return NSMakeSize(ceil(self.label.intrinsicContentSize.width) + (self.showsDot ? 26 : 16), self.neutralSurface ? 24 : 20);
}

- (void)updateInk {
    self.label.textColor = self.neutralSurface ? RKColor(.94,.95,.97) : RKTintColor(self.tint);
    self.needsDisplay = YES;
}

- (void)setTint:(RKTint)tint { _tint = tint; [self updateInk]; }
- (void)setNeutralSurface:(BOOL)neutralSurface {
    _neutralSurface = neutralSurface;
    [self invalidateIntrinsicContentSize];
    [self updateInk];
}

- (void)drawRect:(NSRect)dirtyRect {
    NSColor *tint = RKTintColor(self.tint);
    NSColor *accent = self.neutralSurface ? RKColor(.46,.50,.58) : tint;
    NSColor *fill = RKColor(.038,.043,.055);
    NSBezierPath *shape = RKRoundedRect(self.bounds, NSHeight(self.bounds) / 2);
    RKFillRim(shape, RKBlend(fill, accent, .12), RKBlend(fill, accent, .045), RKBlend(fill, accent, .72), 1);
    if (self.showsDot) {
        [tint setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(7, floor(NSMidY(self.bounds)) - 3.5, 7, 7)] fill];
    }
}
@end

@interface RKActionButton ()
@property (nonatomic, copy) dispatch_block_t invoke;
@property (nonatomic) RKTint tint;
@property (nonatomic) BOOL disabledByAction;
- (void)refreshAvailability;
@end

static void RKRefreshHostActions(NSView *view) {
    if ([view isKindOfClass:RKActionButton.class]) {
        [(RKActionButton *)view refreshAvailability];
        return;
    }
    for (NSView *child in view.subviews) RKRefreshHostActions(child);
}

@implementation RKWorkspaceView
- (void)setDisconnected:(BOOL)disconnected {
    if (_disconnected == disconnected) return;
    _disconnected = disconnected;
    RKRefreshHostActions(self);
}
@end

@implementation RKActionButton
+ (instancetype)title:(NSString *)title symbol:(NSString *)symbol help:(NSString *)help tint:(RKTint)tint action:(dispatch_block_t)action {
    RKActionButton *button = [self new];
    button.title = title;
    button.tint = tint;
    button.bordered = NO;
    button.buttonType = NSButtonTypeMomentaryPushIn;
    button.focusRingType = NSFocusRingTypeExterior;
    button.font = [NSFont systemFontOfSize:12 weight:tint == RKTintViolet ? NSFontWeightSemibold : NSFontWeightMedium];
    button.contentTintColor = RKTintColor(tint);
    if (symbol.length) {
        button.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
        button.imagePosition = title.length ? NSImageLeading : NSImageOnly;
    }
    button.toolTip = help;
    NSString *identifier = [(title.length ? title : help) lowercaseString];
    [button setAccessibilityIdentifier:[identifier stringByReplacingOccurrencesOfString:@" " withString:@"-"]];
    [button setAccessibilityLabel:help.length ? help : title];
    button.target = button;
    button.action = @selector(performAction:);
    button.invoke = action;
    [button setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    return button;
}

- (void)performAction:(id)sender { if (self.window && self.enabled && self.invoke) self.invoke(); }
- (void)setEnabled:(BOOL)enabled { self.disabledByAction = !enabled; [self refreshAvailability]; }
- (void)setAvailableOffline:(BOOL)value { _availableOffline = value; [self refreshAvailability]; }
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; [self refreshAvailability]; }
- (void)refreshAvailability {
    RKWorkspaceView *root = (RKWorkspaceView *)self.window.contentView;
    BOOL offline = [root isKindOfClass:RKWorkspaceView.class] && root.disconnected;
    [super setEnabled:!self.disabledByAction && (!offline || self.availableOffline)];
}
- (BOOL)isPrimary { return self.tint == RKTintViolet && self.title.length && !self.plainAppearance; }

- (void)setPlainAppearance:(BOOL)plain {
    _plainAppearance = plain;
    [self invalidateIntrinsicContentSize];
    self.needsDisplay = YES;
}

- (void)setMaximumTitleWidth:(CGFloat)width {
    _maximumTitleWidth = width;
    [self invalidateIntrinsicContentSize];
    self.needsDisplay = YES;
}

- (NSRect)wrappedTitle:(CGFloat)width attributes:(NSDictionary *)attributes {
    return [self.title boundingRectWithSize:NSMakeSize(width, CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading attributes:attributes];
}

- (NSSize)intrinsicContentSize {
    if (!self.title.length) return NSMakeSize(self.plainAppearance ? 17 : 28, 24);
    CGFloat width = ceil([self.title sizeWithAttributes:@{NSFontAttributeName:self.font}].width);
    if (self.maximumTitleWidth > 0 && width > self.maximumTitleWidth) {
        NSRect text = [self wrappedTitle:self.maximumTitleWidth attributes:@{NSFontAttributeName:self.font}];
        return NSMakeSize(self.maximumTitleWidth + 16, ceil(NSHeight(text)) + 9);
    }
    return NSMakeSize(width + (self.image ? 18 : 0) + (self.isPrimary ? 22 : 16), self.isPrimary ? 27 : 24);
}

- (void)drawRect:(NSRect)dirtyRect {
    NSColor *accent = self.contentTintColor ?: RKTintColor(self.tint);
    NSBezierPath *shape = RKRoundedRect(self.bounds, self.isPrimary ? 7 : 5.5);
    if (!self.plainAppearance) [self drawBezel:shape accent:accent];
    NSColor *ink = self.title.length ? RKColor(.955,.962,.985) : accent;
    [self drawContentsInRect:self.bounds color:self.enabled ? ink : [ink colorWithAlphaComponent:.43]];
}

- (void)drawBezel:(NSBezierPath *)shape accent:(NSColor *)accent {
    NSColor *surface = RKColor(.048,.059,.079);
    CGFloat strength = self.tint == RKTintMuted ? .38 : .79;
    NSColor *rim = RKBlend(surface, accent, strength);
    NSColor *top = RKBlend(surface, accent, self.highlighted ? .28 : .13);
    NSColor *bottom = RKBlend(surface, accent, .038);
    if (self.isPrimary) {
        rim = RKColor(.49,.49,.99);
        top = self.highlighted ? RKColor(.21,.20,.59) : RKColor(.24,.24,.76);
        bottom = RKColor(.12,.13,.53);
    }
    if (!self.enabled) rim = RKBlend(surface, rim, .55);
    RKFillRim(shape, top, bottom, rim, self.isPrimary || (!self.title.length && self.tint != RKTintMuted) ? 1.25 : 1);
}

- (void)drawContentsInRect:(NSRect)bounds color:(NSColor *)ink {
    CGFloat icon = self.image ? (self.title.length ? 13 : 15) : 0;
    CGFloat gap = self.title.length && icon ? 4 : 0;
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *attributes = @{NSFontAttributeName:self.font, NSForegroundColorAttributeName:ink, NSParagraphStyleAttributeName:style};
    NSSize title = [self.title sizeWithAttributes:attributes];
    if (self.maximumTitleWidth > 0 && title.width > self.maximumTitleWidth) {
        style.lineBreakMode = NSLineBreakByWordWrapping;
        style.alignment = NSTextAlignmentCenter;
        CGFloat wrap = MAX(1, MIN(self.maximumTitleWidth, NSWidth(bounds) - 12));
        CGFloat height = ceil(NSHeight([self wrappedTitle:wrap attributes:attributes]));
        NSRect rect = NSMakeRect(floor(NSMidX(bounds)-wrap/2), floor(NSMidY(bounds)-height/2), wrap, height);
        [self.title drawWithRect:rect options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
            attributes:attributes];
        return;
    }
    CGFloat textWidth = MIN(ceil(title.width), MAX(0, NSWidth(bounds) - icon - gap - 12));
    CGFloat x = floor(NSMidX(bounds) - (textWidth + gap + icon) / 2);
    if (icon) {
        NSImageSymbolConfiguration *color = [NSImageSymbolConfiguration configurationWithHierarchicalColor:ink];
        NSImage *image = [self.image imageWithSymbolConfiguration:color] ?: self.image;
        CGFloat scale = icon / MAX(1, MAX(image.size.width, image.size.height));
        NSSize size = NSMakeSize(image.size.width * scale, image.size.height * scale);
        NSRect rect = NSMakeRect(x + (icon-size.width)/2, floor(NSMidY(bounds) - size.height/2), size.width, size.height);
        [image drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
    }
    if (textWidth) {
        NSRect rect = NSMakeRect(x+icon+gap, floor(NSMidY(bounds)-title.height/2), textWidth, ceil(title.height));
        [self.title drawInRect:rect withAttributes:attributes];
    }
}

- (NSRect)focusRingMaskBounds { return self.bounds; }
- (void)drawFocusRingMask { [RKRoundedRect(self.bounds, 6) fill]; }
@end

@interface RKPanelView ()
@property (nonatomic, readwrite) NSStackView *body;
@property (nonatomic) RKTint accent;
@end

@implementation RKPanelView
- (instancetype)initWithTint:(RKTint)tint {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    _accent = tint;
    _showsAccentRail = tint != RKTintMuted;
    _body = RKColumn(9);
    _body.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_body];
    [NSLayoutConstraint activateConstraints:@[
        [_body.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:13],
        [_body.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-11],
        [_body.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
        [_body.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
    ]];
    return self;
}

- (void)setAccent:(RKTint)tint { if (_accent != tint) { _accent = tint; self.needsDisplay = YES; } }
- (void)setShowsAccentRail:(BOOL)value { _showsAccentRail = value; self.needsDisplay = YES; }
- (void)setTintsSurface:(BOOL)value { _tintsSurface = value; self.needsDisplay = YES; }

- (void)drawRect:(NSRect)dirtyRect {
    NSColor *accent = RKTintColor(self.accent);
    NSColor *base = RKColor(.033,.041,.056);
    NSColor *top = RKBlend(RKSurface(), accent, self.tintsSurface ? .095 : .018);
    NSColor *bottom = RKBlend(base, accent, self.tintsSurface ? .045 : 0);
    NSColor *rim = self.tintsSurface ? RKBlend(base, accent, .64) : RKColor(.29,.34,.42);
    NSBezierPath *shape = RKRoundedRect(self.bounds, 8);
    RKFillRim(shape, top, bottom, rim, 1);
    if (!self.showsAccentRail) return;
    [NSGraphicsContext saveGraphicsState];
    [shape addClip];
    [accent setFill];
    NSRectFill(NSMakeRect(0,0,4.5,NSHeight(self.bounds)));
    [NSGraphicsContext restoreGraphicsState];
}
@end
@interface RKPromptEditor : NSTextView
@property (copy) void (^focusChanged)(BOOL);
@end

@implementation RKPromptEditor
- (BOOL)becomeFirstResponder {
    BOOL focused = [super becomeFirstResponder];
    if (focused && self.focusChanged) self.focusChanged(YES);
    return focused;
}
- (BOOL)resignFirstResponder {
    BOOL resigned = [super resignFirstResponder];
    if (resigned && self.focusChanged) self.focusChanged(NO);
    return resigned;
}
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
    self.layer.backgroundColor = RKColor(.073,.085,.106).CGColor;
    self.layer.cornerRadius = 6;
    self.layer.borderWidth = 1;
    self.layer.borderColor = RKColor(.32,.36,.43).CGColor;
    NSScrollView *scroll = [NSScrollView new];
    scroll.drawsBackground = NO;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    RKPromptEditor *prompt = [RKPromptEditor new];
    __weak typeof(self) weakSelf = self;
    prompt.focusChanged = ^(BOOL focused) {
        weakSelf.layer.borderColor = (focused ? RKColor(.56,.54,.98) : RKColor(.32,.36,.43)).CGColor;
        weakSelf.layer.borderWidth = focused ? 1.5 : 1;
    };
    _editor = prompt;
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
