#import "RKApp.h"
#import "RKHost.h"
#import "RKRemoteTerminal.h"
#import "RKAlerts.h"
#import "RKSidebar.h"
#import "RKVoice.h"
#import "RKPaneOrder.h"

// A route owns exactly one selection and connection lifetime. Work already in flight
// can finish on its original host, but cannot update a replacement route.
@interface RKRoute : NSObject
@property id<RKHost> host;
@property dispatch_queue_t queue;
@property (atomic) BOOL retired;
@end
@implementation RKRoute
@end

@interface RKApp () <RKSidebarDelegate>
@property RKRoute *route;
@property RKLocalHost *localHost;
@property NSString *hostID;
@property NSString *destination;
@property BOOL connected;
@property BOOL asleep;
@property NSUInteger selectionGeneration;
@property NSString *unconfirmed;
@property NSDate *catchUpAfter;
@property NSDate *lastSeen;
@property NSDate *nextRetry;
@property RKSidebar *sidebar;
@property RKVoice *voice;
@property RKAlerts *alerts;
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
@property NSMutableSet<NSString *> *pendingAnswers;
@end

@implementation RKApp
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.sidebar = [[RKSidebar alloc] initWithDelegate:self];
    __weak typeof(self) weakSelf = self;
    self.voice = [[RKVoice alloc] initWithStatus:^(NSString *message) { [weakSelf.sidebar showStatus:message]; }];
    self.alerts = [[RKAlerts alloc] initWithOpen:^(NSString *identity) {
        [weakSelf.sidebar showWindow:nil];
        [NSApp activateIgnoringOtherApps:YES];
        if (identity.length) { weakSelf.notificationTarget = identity; [weakSelf refresh]; }
        else [weakSelf.sidebar revealAttention];
    }];
    [self selectHost:[NSUserDefaults.standardUserDefaults stringForKey:@"FauxRKSelectedHost"] ?: @"local"];
    NSNotificationCenter *workspace = NSWorkspace.sharedWorkspace.notificationCenter;
    [workspace addObserver:self selector:@selector(willSleep:) name:NSWorkspaceWillSleepNotification object:nil];
    [workspace addObserver:self selector:@selector(didWake:) name:NSWorkspaceDidWakeNotification object:nil];
    [self installMenus];
    [self.sidebar showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];
    NSString *project = [NSUserDefaults.standardUserDefaults volatileDomainForName:NSArgumentDomain][@"RKProject"];
    BOOL isDirectory = NO;
    if (![self isRemote] && project.isAbsolutePath && [NSFileManager.defaultManager fileExistsAtPath:project isDirectory:&isDirectory] && isDirectory) {
        [self.sidebar showSpawnInProject:project];
    }
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
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [self retireRoute];
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

- (BOOL)isRemote { return [self.hostID isEqual:@"debra"]; }

- (void)retireRoute {
    self.route.retired = YES;
    if ([self.route.host isKindOfClass:RKRemoteHost.class]) [(RKRemoteHost *)self.route.host disconnect];
}

- (void)replaceRoute {
    [self retireRoute];
    RKRoute *route = [RKRoute new];
    route.queue = dispatch_queue_create("net.robertkarl.RK.selected-host", DISPATCH_QUEUE_SERIAL);
    if (self.isRemote) {
        NSURL *helper = [NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:@"Contents/Helpers/fauxrk-helper"];
        route.host = [[RKRemoteHost alloc] initWithDestination:self.destination helperURL:helper];
    } else {
        if (!self.localHost) self.localHost = [RKLocalHost new];
        route.host = self.localHost;
    }
    self.route = route;
    self.polling = NO;
    self.connected = NO;
    self.launching = NO;
    self.pendingCaptures = [NSMutableSet set];
    self.pendingAnswers = [NSMutableSet set];
    self.previewGeneration++;
}

- (void)selectHost:(NSString *)hostID {
    NSString *selection = [hostID isEqual:@"debra"] ? @"debra" : @"local";
    if ([selection isEqual:self.hostID]) return;
    self.hostID = selection;
    self.localHost = nil;
    self.selectionGeneration++;
    self.unconfirmed = nil;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    self.destination = [defaults stringForKey:@"FauxRKDebraDestination"] ?: @"debra";
    [defaults setObject:selection forKey:@"FauxRKSelectedHost"];
    [self.voice cancel];
    self.recordingKeyDown = NO;
    self.lastSeen = nil;
    self.nextRetry = nil;
    self.lastPollError = nil;
    self.notificationTarget = nil;
    self.paneOrder = [RKPaneOrder new];
    self.targets = @{};
    self.sortRequested = NO;
    [self replaceRoute];
    [self.alerts selectComputer:self.isRemote ? RKAlertsDebra : RKAlertsThisMac];
    [self.sidebar switchToHost:selection];
    [self refresh];
}

- (void)retryConnection { self.nextRetry = nil; [self refresh]; }

- (void)willSleep:(NSNotification *)notification {
    self.asleep = YES;
    if (!self.isRemote) return;
    [self replaceRoute];
    [self.sidebar showDisconnectedLastSeen:self.lastSeen];
}

- (void)didWake:(NSNotification *)notification { self.asleep = NO; [self retryConnection]; }

- (void)lostConnection:(NSError *)error {
    [self replaceRoute];
    self.nextRetry = [NSDate dateWithTimeIntervalSinceNow:3];
    [self.sidebar showDisconnectedLastSeen:self.lastSeen];
    NSString *message = error.localizedDescription ?: @"Could not read tmux.";
    if (![message isEqual:self.lastPollError]) [self.sidebar showStatus:self.unconfirmed ?: message];
    self.lastPollError = message;
}

- (void)refresh {
    if (self.asleep || self.polling || self.nextRetry.timeIntervalSinceNow > 0) return;
    self.polling = YES;
    RKRoute *route = self.route;
    BOOL remote = self.isRemote;
    dispatch_async(route.queue, ^{
        if (route.retired) return;
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSDictionary *args = remote ? @{@"provider":[defaults stringForKey:@"RKHelperProvider"] ?: @"sonnet",
                                        @"model":[defaults stringForKey:@"RKLocalModel"] ?: @"qwen3:4b",
                                        @"focusToken":[RKRemoteTerminal focusedToken] ?: @""} : @{};
        NSError *error = nil;
        NSDictionary *snapshot = [route.host request:@"snapshot" arguments:args error:&error];
        if (!snapshot) route.retired = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (route != self.route) return;
            self.polling = NO;
            if (!snapshot) { [self lostConnection:error]; return; }
            [self displaySnapshot:snapshot];
        });
    });
}

- (void)displaySnapshot:(NSDictionary *)snapshot {
    NSArray *panes = snapshot[@"panes"];
    NSDictionary *attention = snapshot[@"attention"];
    if (!self.connected && self.isRemote) {
        // Give stationary screens time to pass RKMonitor's debounce before grouping the backlog.
        self.catchUpAfter = [NSDate dateWithTimeIntervalSinceNow:1.5];
        [self.alerts beginCatchUp];
    }
    if (self.lastPollError) [self.sidebar showStatus:self.unconfirmed ?: @""];
    if (!self.connected) NSLog(@"FauxRK connected to %@ (%lu panes)", self.isRemote ? @"Debra" : @"This Mac", (unsigned long)panes.count);
    self.connected = YES;
    self.lastSeen = [NSDate date];
    self.lastPollError = nil;
    NSMutableDictionary *targets = [NSMutableDictionary dictionary];
    for (NSDictionary *pane in panes) targets[pane[@"id"]] = pane[@"target"];
    self.targets = targets;
    [self.sidebar displayPanes:[self.paneOrder arrange:panes resort:self.sortRequested] attention:attention];
    self.sortRequested = NO;
    if (self.notificationTarget) {
        for (NSDictionary *pane in panes) if ([pane[@"rkID"] isEqual:self.notificationTarget]) [self openAttention:pane[@"id"]];
        self.notificationTarget = nil;
    }
    if (!self.isRemote || self.catchUpAfter.timeIntervalSinceNow <= 0) [self.alerts updatePanes:panes attention:attention];
}

- (void)sortPanesByActivity { self.sortRequested = YES; [self refresh]; }

- (void)perform:(NSString *)operation arguments:(NSDictionary *)args then:(void (^)(id))finished {
    RKRoute *route = self.route;
    if (!self.connected || route.retired) return;
    NSUInteger selection = self.selectionGeneration;
    dispatch_async(route.queue, ^{
        if (route.retired) return;
        NSError *error = nil;
        id result = [route.host request:operation arguments:args error:&error];
        BOOL lost = [error.domain isEqual:RKTransportErrorDomain];
        if (lost) route.retired = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (selection != self.selectionGeneration) return;
            if (lost && error.code == 2) {
                self.unconfirmed = error.localizedDescription;
                [self.sidebar showStatus:self.unconfirmed];
            }
            if (self.route != route) return;
            if (lost) { [self lostConnection:error]; return; }
            if (result && self.unconfirmed && ![operation isEqual:@"attach"] && ![operation isEqual:@"read"]) {
                self.unconfirmed = nil;
                [self.sidebar showStatus:@""];
            }
            if (!result) [self.sidebar showStatus:error.localizedDescription ?: @"The operation did not complete."];
            if (finished) finished(result);
            [self refresh];
        });
    });
}

- (void)spawnPreset:(NSString *)preset directory:(NSString *)directory prompt:(NSString *)prompt {
    if (self.launching || !self.connected) return;
    self.launching = YES;
    [self perform:@"spawn" arguments:@{@"preset":preset, @"directory":directory, @"prompt":prompt ?: @""} then:^(id result) {
        self.launching = NO;
        if (result) [self.sidebar didSpawnWithPrompt:prompt];
    }];
}

- (void)capturePane:(NSString *)paneID {
    NSString *target = self.targets[paneID];
    if (!self.connected || self.route.retired || !target || [self.pendingCaptures containsObject:target]) return;
    [self.pendingCaptures addObject:target];
    [self perform:@"capture" arguments:@{@"target":target} then:^(id result) { [self.pendingCaptures removeObject:target]; }];
}

- (void)previewPane:(NSString *)paneID {
    RKRoute *route = self.route;
    NSString *target = self.targets[paneID];
    if (!target || !self.connected) return;
    NSUInteger generation = ++self.previewGeneration;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (route.retired) return;
        NSError *error = nil;
        NSString *text = [route.host request:@"preview" arguments:@{@"target":target} error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (route != self.route || generation != self.previewGeneration || ![self.targets[paneID] isEqual:target]) return;
            if ([error.domain isEqual:RKTransportErrorDomain]) { [self lostConnection:error]; return; }
            if (text) [self.sidebar showPreview:text forPane:paneID];
            else [self.sidebar showStatus:error.localizedDescription ?: @"Preview unavailable."];
        });
    });
}

- (void)steerPane:(NSString *)paneID text:(NSString *)text {
    NSString *target = self.targets[paneID];
    if (target) [self perform:@"steer" arguments:@{@"target":target, @"text":text} then:^(id result) {
        if (result && [self.targets[paneID] isEqual:target]) [self.sidebar didSendText:text forPane:paneID];
    }];
}

- (void)interruptPane:(NSString *)paneID {
    NSString *target = self.targets[paneID];
    if (target) [self perform:@"interrupt" arguments:@{@"target":target} then:nil];
}

- (void)endPane:(NSString *)paneID {
    NSString *target = self.targets[paneID];
    if (target) [self perform:@"end" arguments:@{@"target":target} then:nil];
}

- (void)openTerminalForPane:(NSString *)paneID {
    NSString *target = self.targets[paneID];
    if (!target) return;
    if (!self.isRemote) {
        RKRoute *local = self.route;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            if (local.retired) return;
            NSError *error = nil;
            if (![local.host request:@"open" arguments:@{@"target":target} error:&error])
                dispatch_async(dispatch_get_main_queue(), ^{ if (self.route == local) [self.sidebar showStatus:error.localizedDescription]; });
        });
        return;
    }
    RKRoute *route = self.route;
    NSString *destination = self.destination;
    [self perform:@"attach" arguments:@{@"target":target} then:^(NSDictionary *metadata) {
        if (!metadata) return;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            if (route.retired) return;
            NSError *error = nil;
            if (![RKRemoteTerminal openAttachment:metadata target:target destination:destination error:&error])
                dispatch_async(dispatch_get_main_queue(), ^{ if (route == self.route) [self.sidebar showStatus:error.localizedDescription]; });
        });
    }];
}

- (void)readAttentionForPane:(NSString *)paneID fingerprint:(NSString *)fingerprint {
    [self perform:@"read" arguments:@{@"id":paneID, @"fingerprint":fingerprint} then:nil];
}

- (void)answerPane:(NSString *)paneID fingerprint:(NSString *)fingerprint choice:(NSDictionary *)choice {
    if (!self.connected || self.route.retired || [self.pendingAnswers containsObject:fingerprint]) return;
    [self.pendingAnswers addObject:fingerprint];
    [self perform:@"answer" arguments:@{@"id":paneID, @"fingerprint":fingerprint, @"choice":choice} then:^(id result) {
        [self.pendingAnswers removeObject:fingerprint];
    }];
}

- (NSMenu *)submenu:(NSString *)name on:(NSMenu *)bar {
    NSMenuItem *item = [bar addItemWithTitle:name action:nil keyEquivalent:@""];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:name];
    item.submenu = menu;
    return menu;
}

- (void)installMenus {
    NSMenu *bar = [NSMenu new];
    NSMenu *app = [self submenu:@"FauxRK" on:bar];
    [app addItemWithTitle:@"About FauxRK" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [[app addItemWithTitle:@"Helper Settings…" action:@selector(settings:) keyEquivalent:@","] setTarget:self];
    [app addItem:NSMenuItem.separatorItem];
    [app addItemWithTitle:@"Hide FauxRK" action:@selector(hide:) keyEquivalent:@"h"];
    [app addItemWithTitle:@"Quit FauxRK" action:@selector(terminate:) keyEquivalent:@"q"];
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
    alert.informativeText = @"The helper reads captured panes and explicit previews. Sonnet and Ollama both run on the selected computer.";
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
