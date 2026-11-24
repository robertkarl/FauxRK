#import <AppKit/AppKit.h>

typedef NS_ENUM(NSInteger, RKTint) {
    RKTintMuted, RKTintViolet, RKTintMint, RKTintAmber, RKTintRed, RKTintBlue
};

NSColor *RKTintColor(RKTint tint);
NSColor *RKSurface(void);
NSTextField *RKLabel(NSString *text, CGFloat size, NSFontWeight weight);
NSTextField *RKDetail(NSString *text);
NSStackView *RKColumn(CGFloat spacing);
NSStackView *RKRow(CGFloat spacing);
NSView *RKSpring(void);
void RKAddFullWidth(NSStackView *column, NSView *child);
NSView *RKInset(NSView *child, NSEdgeInsets insets);
void RKReplaceChildren(NSStackView *stack, NSArray<NSView *> *children);

@interface RKBadgeView : NSView
@property (nonatomic, copy) NSString *stringValue;
@property (nonatomic) RKTint tint;
@property (nonatomic) BOOL neutralSurface;
- (instancetype)initWithText:(NSString *)text tint:(RKTint)tint showsDot:(BOOL)showsDot;
@end

@interface RKWorkspaceView : NSView
@property (nonatomic) BOOL disconnected;
@end

@interface RKActionButton : NSButton
@property (nonatomic) BOOL availableOffline;
@property (nonatomic) BOOL plainAppearance;
@property (nonatomic) CGFloat maximumTitleWidth;
+ (instancetype)title:(NSString *)title symbol:(NSString *)symbol help:(NSString *)help tint:(RKTint)tint action:(dispatch_block_t)action;
@end

@interface RKPanelView : NSView
@property (nonatomic, readonly) NSStackView *body;
@property (nonatomic) BOOL showsAccentRail;
@property (nonatomic) BOOL tintsSurface;
- (instancetype)initWithTint:(RKTint)tint;
- (void)setAccent:(RKTint)tint;
@end

@interface RKPromptView : NSView
@property (nonatomic, readonly) NSTextView *editor;
- (instancetype)initWithHint:(NSString *)hint;
@end
