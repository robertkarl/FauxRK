#import "RKSidebar.h"

static void Check(BOOL condition, NSString *message) {
    if (condition) return;
    NSLog(@"Sidebar regression: %@", message);
    exit(1);
}

static NSView *Find(NSView *root, NSString *identifier) {
    if ([root.accessibilityIdentifier isEqual:identifier]) return root;
    for (NSView *child in root.subviews) {
        NSView *match = Find(child, identifier);
        if (match) return match;
    }
    return nil;
}

static NSDictionary *Pane(NSInteger number) {
    BOOL managed = number == 0;
    NSString *paneID = [NSString stringWithFormat:@"%%%ld",number];
    return @{@"id":paneID, @"target":paneID, @"title":managed ? @"Optimize the inference engine" : @"Terminal",
        @"managed":@(managed), @"session":[NSString stringWithFormat:@"regina-%ld",number], @"window":@"agent",
        @"path":@"~/Code/regina/", @"command":@"claude", @"focused":@NO};
}

@interface Actions : NSObject <RKSidebarDelegate>
@property (nonatomic) NSString *launched, *steered, *captured;
@end
@implementation Actions
- (void)spawnPreset:(NSString *)preset directory:(NSString *)directory prompt:(NSString *)prompt { self.launched = prompt; }
- (void)steerPane:(NSString *)paneID text:(NSString *)text { self.steered = text; }
- (void)capturePane:(NSString *)paneID { self.captured = paneID; }
- (void)sortPanesByActivity {}
- (void)previewPane:(NSString *)paneID {}
- (void)interruptPane:(NSString *)paneID {}
- (void)endPane:(NSString *)paneID {}
- (void)openTerminalForPane:(NSString *)paneID {}
- (void)readAttentionForPane:(NSString *)paneID fingerprint:(NSString *)fingerprint {}
- (void)answerPane:(NSString *)paneID fingerprint:(NSString *)fingerprint choice:(NSDictionary *)choice {}
@end

static void Snapshot(NSView *root, NSString *name) {
    NSString *directory = NSProcessInfo.processInfo.environment[@"RK_UI_SNAPSHOTS"];
    if (!directory.length) return;
    NSBitmapImageRep *rep = [root bitmapImageRepForCachingDisplayInRect:root.bounds];
    [root cacheDisplayInRect:root.bounds toBitmapImageRep:rep];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    Check([png writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES], @"Save snapshot");
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        Actions *actions = [Actions new];
        RKSidebar *sidebar = [[RKSidebar alloc] initWithDelegate:actions];
        NSMutableArray *panes = [NSMutableArray array];
        for (NSInteger n=0; n<80; n++) [panes addObject:Pane(n)];
        NSMutableDictionary *question = [@{@"kind":@"maybe", @"summary":@"Which project should I inspect?", @"fingerprint":@"one"} mutableCopy];
        [sidebar displayPanes:panes attention:@{@"%0":question.copy}];
        [sidebar showWindow:nil];
        NSView *view = sidebar.window.contentView;
        [view layoutSubtreeIfNeeded];
        Snapshot(view, @"dashboard.png");
        NSButton *capture = (NSButton *)Find(view, @"capture-%1");
        [capture performClick:nil];
        Check([actions.captured isEqual:@"%1"], @"Capture visible unmanaged pane by id");
        [sidebar revealPane:@"%0"];
        [view layoutSubtreeIfNeeded];
        NSTextView *reply = (NSTextView *)Find(view, @"reply-%0");
        Check(reply && [sidebar.window makeFirstResponder:reply], @"Focus reply");
        question[@"suggestedReply"] = @"Inspect regina.";
        [sidebar displayPanes:panes attention:@{@"%0":question.copy}];
        Check([reply.string isEqual:@"Inspect regina."], @"Apply helper suggestion to empty editor");
        reply.string = @"Inspect regina first.";
        reply.selectedRange = NSMakeRange(3, 2);
        question[@"summary"] = @"Choose the project.";
        [sidebar displayPanes:panes attention:@{@"%0":question.copy}];
        Check(sidebar.window.firstResponder == reply && NSEqualRanges(reply.selectedRange, NSMakeRange(3, 2)), @"Keep reply focus and selection across polls");
        Check([reply.string isEqual:@"Inspect regina first."], @"Preserve edited helper suggestion");
        NSTextView *steer = (NSTextView *)Find(view, @"steer-%0");
        steer.string = @"Summarize the changes.";
        [(NSButton *)Find(view, @"steer") performClick:nil];
        Check([actions.steered isEqual:steer.string], @"Deliver steer");
        [steer.textStorage.mutableString appendString:@" Next."];
        Check([actions.steered isEqual:@"Summarize the changes."], @"Submitted steer is immutable");
        [sidebar didSendText:actions.steered forPane:@"%0"];
        Check([steer.string hasSuffix:@"Next."], @"Keep typing after send");
        [sidebar didSendText:steer.string.copy forPane:@"%0"];
        Check(!steer.string.length, @"Clear acknowledged draft");
        Snapshot(view, @"expanded-agent.png");
        [sidebar showSpawn];
        NSTextView *spawn = (NSTextView *)Find(view, @"spawn-prompt");
        [spawn insertText:@"Review the changes." replacementRange:spawn.selectedRange];
        [(NSButton *)Find(view, @"launch") performClick:nil];
        Check([actions.launched isEqual:spawn.string], @"Launch with prompt");
        [spawn.textStorage.mutableString appendString:@" Again."];
        Check([actions.launched isEqual:@"Review the changes."], @"Submitted first prompt is immutable");
        Snapshot(view, @"spawn.png");
        [sidebar didSpawnWithPrompt:spawn.string];
        [sidebar.window orderOut:nil];
        puts("sidebar fixtures passed");
    }
}
