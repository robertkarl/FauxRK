#import "RKApp.h"
#import "RKCore.h"
#import "RKAlerts.h"
#import "RKSidebar.h"
#import "RKVoice.h"
#import "RKPaneOrder.h"

@interface RKApp () <RKSidebarDelegate>
@property RKCore *core;
@property RKMonitor *monitor;
@property RKSidebar *sidebar;
@property RKVoice *voice;
@property RKAlerts *alerts;
@property dispatch_queue_t worker;
@property NSTimer *timer;
@property id keyMonitor;
@property BOOL polling;
@property BOOL sortRequested;
@property BOOL recordingKeyDown;
@property RKPaneOrder *paneOrder;
@property BOOL launching;
@property NSString *notificationTarget;
@property NSUInteger previewGeneration;
@property NSString *lastPollError;
@property NSDictionary<NSString *, NSString *> *targets;
@property NSMutableSet<NSString *> *pendingCaptures;
@end

@implementation RKApp
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.core = [RKCore new];
    self.paneOrder = [RKPaneOrder new];
    self.monitor = [[RKMonitor alloc] initWithCore:self.core];
    self.worker = dispatch_queue_create("net.robertkarl.RK.agent-control", DISPATCH_QUEUE_SERIAL);
    self.pendingCaptures = [NSMutableSet set];
    self.sidebar = [[RKSidebar alloc] initWithDelegate:self];
    __weak typeof(self) weakSelf = self;
    self.voice = [[RKVoice alloc] initWithStatus:^(NSString *message) { [weakSelf.sidebar showStatus:message]; }];
    self.alerts = [[RKAlerts alloc] initWithOpen:^(NSString *identity) { weakSelf.notificationTarget = identity; [weakSelf.sidebar showWindow:nil]; [NSApp activateIgnoringOtherApps:YES]; [weakSelf refresh]; }];
    [self installMenus];
    [self.sidebar showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];
    self.keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskKeyUp handler:^NSEvent *(NSEvent *e) {
        return [weakSelf handleDictationKey:e];
    }];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.2 repeats:YES block:^(NSTimer *t) { [weakSelf refresh]; }];
    [self refresh];
}

- (NSEvent *)handleDictationKey:(NSEvent *)event {
    if (event.keyCode != 109) return event;
    if (event.type == NSEventTypeKeyUp && self.recordingKeyDown) {
        self.recordingKeyDown = NO;
        [self.voice finish];
        return nil;
    }
    NSTextView *editor = [self.sidebar focusedPromptEditor];
    if (event.type != NSEventTypeKeyDown || !editor) return event;
    if (!event.isARepeat && !self.recordingKeyDown) {
        self.recordingKeyDown = YES;
        [self.voice beginWithEditor:editor];
    }
    return nil;
}

- (void)applicationWillResignActive:(NSNotification *)notification {
    if (self.recordingKeyDown) {
        self.recordingKeyDown = NO;
        [self.voice cancel];
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.timer invalidate];
    if (self.keyMonitor) [NSEvent removeMonitor:self.keyMonitor];
    [self.voice cancel];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)application hasVisibleWindows:(BOOL)visible {
    [self.sidebar showWindow:nil];
    return YES;
}

- (void)openAttention:(NSString *)paneID {
    [NSApp activateIgnoringOtherApps:YES];
    [self.sidebar showWindow:nil];
    [self.sidebar revealPane:paneID];

}

- (void)refresh {
    if (self.polling) return;
    self.polling = YES;
    dispatch_async(self.worker, ^{
        NSError *error = nil;
        NSArray *panes = [self.core panes:&error];
        NSDictionary *attention = panes ? [self.monitor update:panes] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.polling = NO;
            if (!panes) {
                NSString *reason = error.localizedDescription ?: @"Could not read tmux.";
                if (![reason isEqual:self.lastPollError]) [self.sidebar showStatus:reason];
                self.lastPollError = reason;
                return;
            }
            self.lastPollError = nil;
            NSMutableDictionary *targets = [NSMutableDictionary dictionary];
            for (NSDictionary *pane in panes) targets[pane[@"id"]] = pane[@"target"] ?: pane[@"id"];
            self.targets = targets;
            [self.sidebar displayPanes:[self.paneOrder arrange:panes resort:self.sortRequested] attention:attention];
            self.sortRequested = NO;
            if (self.notificationTarget) {
                for (NSDictionary *pane in panes) {
                    if ([pane[@"rkID"] isEqual:self.notificationTarget]) [self openAttention:pane[@"id"]];
                }
                self.notificationTarget = nil;
            }
            [self.alerts updatePanes:panes attention:attention];
        });
    });
}

- (void)sortPanesByActivity { self.sortRequested = YES; [self refresh]; }

- (void)perform:(BOOL (^)(NSError **error))operation then:(void (^)(BOOL))finished {
    dispatch_async(self.worker, ^{
        NSError *error = nil;
        BOOL ok = operation(&error);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ok) [self.sidebar showStatus:error.localizedDescription ?: @"The operation did not complete."];
            if (finished) finished(ok);
            [self refresh];
        });
    });
}

- (void)spawnPreset:(NSString *)preset directory:(NSString *)directory prompt:(NSString *)prompt {
    if (self.launching) return;
    self.launching = YES;
    [self perform:^BOOL(NSError **error) { return [self.core spawnPreset:preset directory:directory.stringByExpandingTildeInPath prompt:prompt error:error] != nil; }
            then:^(BOOL ok) { self.launching = NO; if (ok) [self.sidebar didSpawnWithPrompt:prompt]; }];
}
- (void)capturePane:(NSString *)paneID {
    if ([self.pendingCaptures containsObject:paneID]) return;
    NSString *target = self.targets[paneID];
    if (!target) return;
    [self.pendingCaptures addObject:paneID];
    [self perform:^BOOL(NSError **error) { return [self.core capture:target error:error]; }
            then:^(BOOL ok) { [self.pendingCaptures removeObject:paneID]; }];
}
- (void)previewPane:(NSString *)paneID {
    NSString *target = self.targets[paneID];
    if (!target) return;
    NSUInteger generation = ++self.previewGeneration;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSString *text = [self.monitor preview:target error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.previewGeneration || ![self.targets[paneID] isEqual:target]) return;
            if (text) [self.sidebar showPreview:text forPane:paneID];
            else [self.sidebar showStatus:error.localizedDescription ?: @"Preview unavailable."];
        });
    });
}
- (void)steerPane:(NSString *)paneID text:(NSString *)text {
    NSString *target = self.targets[paneID];
    if (!target) return;
    [self perform:^BOOL(NSError **error) { return [self.core sendText:text toPane:target error:error]; }
            then:^(BOOL ok) { if (ok) [self.sidebar didSendText:text forPane:paneID]; }];
}
- (void)interruptPane:(NSString *)paneID {
    NSString *target = self.targets[paneID];
    if (!target) return;
    [self perform:^BOOL(NSError **error) { return [self.core interrupt:target error:error]; } then:nil];
}
- (void)endPane:(NSString *)paneID {
    NSString *target = self.targets[paneID];
    if (!target) return;
    [self perform:^BOOL(NSError **error) { return [self.core end:target error:error]; } then:nil];
}
- (void)openTerminalForPane:(NSString *)paneID {
    NSString *target = self.targets[paneID];
    if (!target) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        if (![self.core openWindow:target error:&error]) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self.sidebar showStatus:error.localizedDescription]; });
        }
    });
}
- (void)readAttentionForPane:(NSString *)paneID fingerprint:(NSString *)fingerprint {
    [self perform:^BOOL(NSError **error) { [self.monitor markRead:paneID fingerprint:fingerprint]; return YES; } then:nil];
}
- (void)answerPane:(NSString *)paneID fingerprint:(NSString *)fingerprint choice:(NSDictionary *)choice {
    [self perform:^BOOL(NSError **error) { return [self.monitor answer:choice pane:paneID fingerprint:fingerprint error:error]; }
            then:^(BOOL ok) { if (ok && choice[@"text"]) [self.sidebar didSendText:choice[@"text"] forPane:paneID]; }];
}

- (NSMenu *)submenu:(NSString *)name on:(NSMenu *)bar {
    NSMenuItem *item = [bar addItemWithTitle:name action:nil keyEquivalent:@""];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:name];
    item.submenu = menu;
    return menu;
}

- (void)installMenus {
    NSMenu *bar = [NSMenu new];
    NSMenu *app = [self submenu:@"RK" on:bar];
    [app addItemWithTitle:@"About RK" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [[app addItemWithTitle:@"Helper Settings…" action:@selector(settings:) keyEquivalent:@","] setTarget:self];
    [app addItem:NSMenuItem.separatorItem];
    [app addItemWithTitle:@"Hide RK" action:@selector(hide:) keyEquivalent:@"h"];
    [app addItemWithTitle:@"Quit RK" action:@selector(terminate:) keyEquivalent:@"q"];
    NSMenu *file = [self submenu:@"File" on:bar];
    [[file addItemWithTitle:@"Spawn Agent…" action:@selector(newAgent:) keyEquivalent:@"n"] setTarget:self];
    [file addItemWithTitle:@"Close Window" action:@selector(performClose:) keyEquivalent:@"w"];
    NSMenu *edit = [self submenu:@"Edit" on:bar];
    for (NSArray *entry in @[@[@"Undo",@"undo:",@"z"], @[@"Redo",@"redo:",@"Z"], @[@"Cut",@"cut:",@"x"],
                              @[@"Copy",@"copy:",@"c"], @[@"Paste",@"paste:",@"v"], @[@"Select All",@"selectAll:",@"a"]]) {
        [edit addItemWithTitle:entry[0] action:NSSelectorFromString(entry[1]) keyEquivalent:entry[2]];
    }
    NSApp.mainMenu = bar;
}

- (void)newAgent:(id)sender { [self.sidebar showWindow:nil]; [self.sidebar showSpawn]; }

- (void)settings:(id)sender {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Agent helper";
    alert.informativeText = @"The helper reads captured panes and explicit previews. Local inference uses Ollama on this Mac.";
    NSPopUpButton *provider = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 42, 290, 28)];
    [provider addItemsWithTitles:@[@"Hosted · Sonnet", @"Local · Ollama"]];
    [provider selectItemAtIndex:[[defaults stringForKey:@"RKHelperProvider"] isEqual:@"local"] ? 1 : 0];
    NSTextField *model = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 4, 290, 25)];
    model.placeholderString = @"Local model name";
    model.stringValue = [defaults stringForKey:@"RKLocalModel"] ?: @"qwen3:4b";
    NSView *fields = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 290, 78)];
    [fields addSubview:provider]; [fields addSubview:model];
    alert.accessoryView = fields;
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:self.sidebar.window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        [defaults setObject:provider.indexOfSelectedItem == 1 ? @"local" : @"sonnet" forKey:@"RKHelperProvider"];
        [defaults setObject:model.stringValue forKey:@"RKLocalModel"];
        [self refresh];
    }];
}
@end
