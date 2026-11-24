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
@property (nonatomic) NSString *launched, *steered, *captured, *selectedHost, *directory;
@property (nonatomic) NSUInteger retries, ends, dismissals;
@end
@implementation Actions
- (void)selectHost:(NSString *)hostID { self.selectedHost = hostID; }
- (void)retryConnection { self.retries++; }
- (void)dismissDeliveryNotice { self.dismissals++; }
- (void)spawnPreset:(NSString *)preset directory:(NSString *)directory prompt:(NSString *)prompt { self.launched = prompt; self.directory = directory; }
- (void)steerPane:(NSString *)paneID text:(NSString *)text { self.steered = text; }
- (void)capturePane:(NSString *)paneID { self.captured = paneID; }
- (void)sortPanesByActivity {}
- (void)previewPane:(NSString *)paneID {}
- (void)interruptPane:(NSString *)paneID {}
- (void)endPane:(NSString *)paneID { self.ends++; }
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

static void RenderReferenceStates(RKSidebar *sidebar) {
    if (!NSProcessInfo.processInfo.environment[@"RK_UI_SNAPSHOTS"]) return;
    NSMutableArray *panes = [NSMutableArray array];
    NSArray *titles = @[@"Inference engine optimization", @"Running experiment on Qwen 27B",
                        @"Development on T3 Code", @"Bugfix on Strata", @"research:notes", @"data:prep"];
    NSArray *presets = @[@"Fable Medium", @"Astra Medium", @"Opus", @"Luna Medium"];
    for (NSUInteger index = 0; index < titles.count; index++) {
        NSMutableDictionary *pane = [Pane(index + 90) mutableCopy];
        pane[@"managed"] = @(index < presets.count);
        pane[@"title"] = titles[index];
        pane[@"session"] = @[@"inference-engine", @"qwen", @"t3-code", @"strata", @"research", @"data"][index];
        pane[@"window"] = @[@"agent", @"agent", @"agent", @"agent", @"notes", @"prep"][index];
        pane[@"path"] = [@"~/Code/" stringByAppendingString:pane[@"session"]];
        if (index < presets.count) pane[@"preset"] = presets[index];
        [panes addObject:pane];
    }
    NSDictionary *blocker = @{@"kind":@"input", @"fingerprint":@"dependency", @"choiceSource":@"terminal",
        @"question":@"Install @t3/runtime and retry?", @"summary":@"The build needs @t3/runtime. Install it and retry?",
        @"choices":@[@{@"label":@"Install and retry", @"text":@"y"}, @{@"label":@"Decline", @"text":@"n"}]};
    NSDictionary *result = @{@"kind":@"complete", @"fingerprint":@"experiment", @"summary":@"The experiment finished. Results and metrics are ready."};
    NSDictionary *events = @{@"%92":blocker, @"%91":result};
    [sidebar displayPanes:panes attention:events];
    [sidebar.window.contentView layoutSubtreeIfNeeded];
    Snapshot(sidebar.window.contentView, @"reference-dashboard.png");
    [sidebar revealPane:@"%90"];
    [sidebar.window.contentView layoutSubtreeIfNeeded];
    Snapshot(sidebar.window.contentView, @"reference-expanded.png");
}

static void VerifyHostSwitching(RKSidebar *sidebar, Actions *actions) {
    NSView *local = sidebar.window.contentView;
    [sidebar showSpawn];
    NSTextView *oldDraft = (NSTextView *)Find(local, @"spawn-prompt");
    oldDraft.string = @"For this Mac only.";
    [oldDraft didChangeText];
    NSButton *oldLaunch = (NSButton *)Find(local, @"launch");
    NSPopUpButton *picker = (NSPopUpButton *)Find(local, @"host-picker");
    Check([picker.itemTitles isEqual:@[@"This Mac",@"Debra"]], @"Exactly two host choices");
    [picker selectItemWithTitle:@"Debra"];
    [picker sendAction:picker.action to:picker.target];
    NSView *remote = sidebar.window.contentView;
    Check([actions.selectedHost isEqual:@"debra"] && remote != local, @"Switch selects Debra and discards the old workspace");
    actions.launched = nil;
    [oldLaunch performClick:nil];
    Check(!actions.launched && !oldDraft.window, @"Detached local Draft cannot be sent to Debra");
    [sidebar showSpawn];
    NSTextView *draft = (NSTextView *)Find(remote, @"spawn-prompt");
    Check(draft && !draft.string.length, @"No local draft in remote launcher");
    NSButton *launch = (NSButton *)Find(remote, @"launch");
    Check(!launch.enabled, @"Wait for the remote inventory before launching");
    NSPopUpButton *projects = (NSPopUpButton *)Find(remote, @"spawn-directory");
    Check([projects.itemTitles isEqual:@[@"~/Code/regina/",@"~/homelab/",@"~/Code/unbiasedbob-private/"]], @"Three remote directories");
    [projects selectItemAtIndex:2];
    [projects sendAction:projects.action to:projects.target];

    NSDictionary *event = @{@"kind":@"input", @"fingerprint":@"handoff", @"summary":@"Which file?"};
    NSDictionary *requests = @{@"%0":event};
    NSArray *panes = @[Pane(0),Pane(1)];
    [sidebar displayPanes:panes attention:requests];
    [remote layoutSubtreeIfNeeded];
    [launch performClick:nil];
    Check([actions.directory isEqual:@"~/Code/unbiasedbob-private/"], @"Remote spawn preserves literal host-relative path");
    [sidebar revealAttention];
    Check([[(NSView *)sidebar.window.firstResponder accessibilityIdentifier] isEqual:@"attention-open-handoff"], @"Catch-up opens Needs attention");
    [sidebar revealPane:@"%0"];
    NSTextView *steer = (NSTextView *)Find(remote, @"steer-%0");
    steer.string = @"Keep this draft on disconnect.";
    draft.string = @"Keep remote launch draft.";
    [steer didChangeText]; [draft didChangeText];
    [sidebar showPreview:@"Remote preview." forPane:@"%1"];
    NSButton *send = (NSButton *)Find(remote, @"card-send-steer-%0");
    NSButton *capture = (NSButton *)Find(remote, @"capture-%1");
    [sidebar showDisconnectedLastSeen:NSDate.date];
    NSString *uncertain = @"Delivery unconfirmed. Check the agent before resending.";
    [sidebar showDeliveryNotice:uncertain];
    [sidebar showStatus:@"Listening…"];
    NSTextField *notice = (NSTextField *)Find(remote, @"delivery-notice");
    Check([notice.stringValue isEqual:uncertain] && !notice.hiddenOrHasHiddenAncestor, @"Offline notice survives unrelated dictation status");
    NSString *badge = [Find(remote, @"host-status") accessibilityValue];
    Check([badge isEqual:@"Disconnected"] && [[(NSTextField *)Find(remote, @"host-last-seen") stringValue] containsString:@"Last seen"], @"Show last-known time while disconnected");
    [remote layoutSubtreeIfNeeded];
    Check(NSWidth(remote.bounds) <= 370, @"Offline chrome fits a narrow sidebar");
    Check(!send.enabled && !launch.enabled && !capture.enabled, @"Disable sending, spawn, and capture while disconnected");
    actions.steered = nil;
    [send performClick:nil];
    Check(!actions.steered, @"Disabled send never calls host");
    NSButton *retry = (NSButton *)Find(remote, @"host-retry");
    [retry performClick:nil];
    Check(retry.enabled && actions.retries == 1, @"Offer explicit Retry");
    Snapshot(remote, @"debra-offline.png");

    [sidebar displayPanes:panes attention:requests];
    Check(send.enabled && capture.enabled && launch.enabled, @"A fresh snapshot restores host actions");
    [sidebar showStatus:@"Draft inserted."];
    Check([notice.stringValue isEqual:uncertain] && !notice.hiddenOrHasHiddenAncestor, @"Reconnect preserves unconfirmed delivery");
    [(NSButton *)Find(remote, @"dismiss-delivery-notice") performClick:nil];
    Check(actions.dismissals == 1, @"Dismiss button requests controller acknowledgement");
    [sidebar showDeliveryNotice:@""];
    Check(notice.hiddenOrHasHiddenAncestor && [[(NSTextField *)Find(remote, @"transient-status") stringValue] isEqual:@"Draft inserted."], @"Clearing delivery notice preserves unrelated status");
    [sidebar showDeliveryNotice:uncertain];
    Check(Find(remote, @"steer-%0") == steer && [steer.string hasPrefix:@"Keep this"], @"Reconnect preserves pane draft");
    Check([draft.string isEqual:@"Keep remote launch draft."], @"Reconnect preserves spawn draft");
    NSView *oldAttention = Find(remote, @"attention-open-handoff");
    NSMutableDictionary *replacement = [Pane(0) mutableCopy];
    replacement[@"target"] = @"new-generation:%0";
    [sidebar displayPanes:@[replacement,Pane(1)] attention:requests];
    [sidebar revealPane:@"%0"];
    NSTextView *newDraft = (NSTextView *)Find(remote, @"steer-%0");
    Check(newDraft != steer && !newDraft.string.length && !steer.window, @"Reused pane IDs never inherit previous agent drafts");
    Check(Find(remote, @"attention-open-handoff") != oldAttention, @"Reused pane IDs also get fresh attention controls");

    [(NSButton *)Find(remote, @"card-end-%0") performClick:nil];
    Check(sidebar.window.sheets.count > 0, @"End confirmation is open on Debra");
    [sidebar switchToHost:@"local"];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
    [sidebar displayPanes:panes attention:requests];
    Check(!sidebar.window.sheets.count && actions.ends == 0, @"Switch cancels host-bound confirmation");
    NSTextField *freshNotice = (NSTextField *)Find(sidebar.window.contentView, @"delivery-notice");
    Check(!freshNotice || freshNotice.hiddenOrHasHiddenAncestor, @"Host switch clears the previous host’s notice");
    [sidebar showSpawn];
    projects = (NSPopUpButton *)Find(sidebar.window.contentView, @"spawn-directory");
    Check([projects.itemTitles containsObject:@"Choose another folder…"], @"This Mac keeps local folder selection");
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
        [(NSButton *)Find(view, @"card-send-steer-%0") performClick:nil];
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
        RenderReferenceStates(sidebar);
        [sidebar.window setFrameAutosaveName:@""];
        NSString *longChoice = @"Install the runtime dependency and apply the new configuration to every selected target";
        NSDictionary *menu = @{@"kind":@"input", @"fingerprint":@"narrow", @"question":@"Apply changes?",
            @"choiceSource":@"terminal", @"choices":@[@{@"label":longChoice}, @{@"label":@"No"}]};
        [sidebar displayPanes:@[Pane(0)] attention:@{@"%0":menu}];
        [sidebar.window setContentSize:NSMakeSize(370,680)];
        [view layoutSubtreeIfNeeded];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
        NSView *longButton = Find(view, @"attention-choice-narrow-0");
        Check(longButton && NSHeight(longButton.bounds) > 24, @"Wrap a long terminal answer");
        Check(fabs(NSWidth(view.bounds) - 370) < 1, @"Answer choices must honor the requested sidebar width");
        VerifyHostSwitching(sidebar, actions);
        [sidebar.window orderOut:nil];
        puts("sidebar fixtures passed");
    }
}
