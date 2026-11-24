#import "RKAlerts.h"
#import <UserNotifications/UserNotifications.h>

@interface RKAlerts (TestInit) <UNUserNotificationCenterDelegate>
- (instancetype)initWithOpen:(void (^)(NSString *))open center:(UNUserNotificationCenter *)center
                    defaults:(NSUserDefaults *)defaults foreground:(BOOL (^)(void))foreground;
@end

static void Check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"Alert regression: %@", message); exit(1); }
}
static void Drain(void) { [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.015]]; }

@interface FakeCenter : NSObject
@property (weak) id<UNUserNotificationCenterDelegate> delegate;
@property BOOL grantsPermission;
@property NSUInteger prompts;
@property NSMutableArray<UNNotificationRequest *> *posts;
@property NSMutableDictionary *adding;
@property NSMutableSet *delivered;
@end
@implementation FakeCenter
- (instancetype)init {
    if (!(self = [super init])) return nil;
    _grantsPermission = YES;
    _posts = [NSMutableArray array];
    _adding = [NSMutableDictionary dictionary];
    _delivered = [NSMutableSet set];
    return self;
}
- (void)requestAuthorizationWithOptions:(UNAuthorizationOptions)options completionHandler:(void (^)(BOOL, NSError *))block {
    self.prompts++;
    block(self.grantsPermission,nil);
}
- (void)addNotificationRequest:(UNNotificationRequest *)request withCompletionHandler:(void (^)(NSError *))block {
    [self.posts addObject:request];
    self.adding[request.identifier] = [block copy];
}
- (void)finishAdd:(NSString *)identity {
    void (^completion)(NSError *) = self.adding[identity];
    Check(completion != nil, @"No pending notification to complete");
    [self.delivered addObject:identity];
    [self.adding removeObjectForKey:identity];
    completion(nil);
    Drain();
}
- (void)removeDeliveredNotificationsWithIdentifiers:(NSArray *)identifiers {
    [self.delivered minusSet:[NSSet setWithArray:identifiers]];
}
@end

@interface Response : NSObject
@property UNNotificationRequest *request;
- (instancetype)notification;
@end
@implementation Response
- (instancetype)notification { return self; }
@end

static NSDictionary *Pane(NSString *paneID, NSString *stable, BOOL focused) {
    return @{@"id":paneID, @"rkID":stable, @"title":stable, @"managed":@YES, @"focused":@(focused)};
}
static NSDictionary *Row(NSString *fingerprint) { return @{@"fingerprint":fingerprint, @"summary":@"Proceed?"}; }
static void Click(FakeCenter *center, UNNotificationRequest *request) {
    Response *response = [Response new];
    response.request = request;
    __block BOOL done = NO;
    [center.delegate userNotificationCenter:(id)center didReceiveNotificationResponse:(id)response withCompletionHandler:^{ done=YES; }];
    Drain();
    Check(done, @"Notify macOS click was handled");
}

static NSDictionary *Kind(NSString *fingerprint, NSString *kind) { return @{@"fingerprint":fingerprint, @"summary":@"Proceed?", @"kind":kind}; }

static void RemoteCatchUp(NSUserDefaults *defaults) {
    FakeCenter *center = [FakeCenter new];
    __block BOOL front = NO;
    __block NSString *opened;
    RKAlerts *alerts = [[RKAlerts alloc] initWithOpen:^(NSString *identity){ opened=identity; } center:(id)center
                                             defaults:defaults foreground:^{ return front; }];
    [alerts selectComputer:@"Debra"];
    [alerts beginCatchUp];
    NSArray *panes = @[Pane(@"%1",@"r-A",YES), Pane(@"%2",@"r-B",NO), Pane(@"%3",@"r-C",NO), Pane(@"%4",@"r-D",NO)];
    NSDictionary *rows = @{@"%1":Kind(@"a1",@"input"), @"%2":Kind(@"b1",@"input"), @"%3":Kind(@"c1",@"maybe"), @"%4":Kind(@"d1",@"complete")};
    [alerts updatePanes:panes attention:rows];
    Check(!center.posts.count, @"Catch-up waits while authorization is pending");
    Drain();
    [alerts updatePanes:panes attention:rows];
    Check(center.posts.count == 1, @"Reconnect backlog produces exactly one notification");
    UNNotificationRequest *summary = center.posts.lastObject;
    Check([summary.identifier isEqual:@"RKCatchUp.Debra"], @"Summary uses the catch-up identifier");
    Check([summary.content.body isEqual:@"2 decisions and 1 result waiting"], @"Summary counts eligible requests, excluding the focused pane");
    [center finishAdd:@"RKCatchUp.Debra"];
    Check([center.delivered containsObject:@"RKCatchUp.Debra"], @"Summary remains while backlog is live");
    [alerts updatePanes:panes attention:rows];
    [alerts updatePanes:panes attention:rows];
    Check(center.posts.count == 1, @"Backlog is not repeated individually on later polls");
    Click(center, summary);
    Check([opened isEqual:@""], @"Clicking summary opens with empty identity");

    NSMutableDictionary *next = [rows mutableCopy];
    next[@"%2"] = Kind(@"b2",@"input");
    [alerts updatePanes:panes attention:next];
    UNNotificationRequest *live = center.posts.lastObject;
    Check(center.posts.count == 2 && [live.identifier isEqual:@"Debra:r-B"], @"Live event after catch-up notifies individually");
    Check([live.content.userInfo[@"computer"] isEqual:@"Debra"], @"Remote banner records its computer");
    [center finishAdd:@"Debra:r-B"];
    Click(center, live);
    Check([opened isEqual:@"r-B"], @"Remote banner click opens its identity");
    [alerts updatePanes:@[Pane(@"%2",@"r-B",NO)] attention:@{@"%2":Kind(@"b2",@"input")}];
    Check(![center.delivered containsObject:@"RKCatchUp.Debra"], @"Summary withdrawn once its backlog resolves");

    [alerts beginCatchUp];
    [alerts updatePanes:@[Pane(@"%2",@"r-B",NO)] attention:@{@"%2":Kind(@"b2",@"input")}];
    Check(center.posts.count == 2, @"No catch-up notification when nothing is eligible");
    [alerts updatePanes:panes attention:rows];
    Check(center.posts.count == 5, @"Catch-up ended; new events post individually");
    for (NSString *identity in @[@"Debra:r-B",@"Debra:r-C",@"Debra:r-D"]) [center finishAdd:identity];

    front = YES;
    [alerts beginCatchUp];
    [alerts updatePanes:panes attention:next];
    front = NO;
    [alerts updatePanes:panes attention:next];
    [alerts updatePanes:panes attention:next];
    Check(center.posts.count == 5, @"Backlog consumed silently when RK was in front during reconnect");

    [alerts updatePanes:panes attention:@{@"%2":Kind(@"b2",@"input"), @"%3":Kind(@"c3",@"maybe")}];
    UNNotificationRequest *stale = center.posts.lastObject;
    Check([stale.identifier isEqual:@"Debra:r-C"], @"Remote event in flight");
    [alerts selectComputer:@"Debra"];
    Check(center.adding[@"Debra:r-C"] != nil, @"Reselecting the same computer is a no-op");
    [alerts selectComputer:@"This Mac"];
    [center finishAdd:@"Debra:r-C"];
    Check(!center.delivered.count, @"Switching removes old-host notifications, including late completions");
    opened = nil;
    Click(center, stale);
    Check(opened == nil, @"Old-host click is ignored after switching");
    [alerts updatePanes:panes attention:@{@"%2":Kind(@"b2",@"input")}];
    Check([center.posts.lastObject.identifier isEqual:@"r-B"], @"Local state is independent of Debra's delivered state");
    [center finishAdd:@"r-B"];
    [alerts beginCatchUp];
    [alerts selectComputer:@"Debra"];
    [alerts updatePanes:@[Pane(@"%2",@"r-B",NO)] attention:@{@"%2":Kind(@"b2",@"input")}];
    Check(center.posts.count == 7, @"Switching clears catch-up and restores Debra's delivered state");
    Check(![center.delivered containsObject:@"r-B"], @"Switching back removes the local banner");
}

int main(void) {
    @autoreleasepool {
        NSString *suite = [@"RK.notification.tests." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        FakeCenter *center = [FakeCenter new];
        __block BOOL front = NO;
        __block NSString *opened;
        void (^open)(NSString *) = ^(NSString *identity){ opened=identity; };
        BOOL (^foreground)(void) = ^{ return front; };
        RKAlerts *alerts = [[RKAlerts alloc] initWithOpen:open center:(id)center defaults:defaults foreground:foreground];
        NSArray *panes = @[Pane(@"%4",@"stable-A",YES), Pane(@"%5",@"stable-B",NO)];
        NSDictionary *rows = @{@"%4":Row(@"a1"), @"%5":Row(@"b1")};
        [alerts updatePanes:@[] attention:@{}];
        Check(center.prompts == 0, @"First launch without captured agents stays quiet");
        [alerts updatePanes:panes attention:rows];
        Drain();
        [alerts updatePanes:panes attention:rows];
        [alerts updatePanes:panes attention:rows];
        Check(center.prompts == 1 && center.posts.count == 1, @"One permission request, one pending banner");
        UNNotificationRequest *banner = center.posts.lastObject;
        Check([banner.identifier isEqual:@"stable-B"] && [banner.content.body isEqual:@"Proceed?"], @"B notifies while A has terminal focus");
        [center finishAdd:@"stable-B"];
        [alerts updatePanes:panes attention:rows];
        Check(center.posts.count == 1, @"Unchanged blocker only delivers once");
        alerts = [[RKAlerts alloc] initWithOpen:open center:(id)center defaults:defaults foreground:foreground];
        [alerts updatePanes:panes attention:rows];
        Drain();
        [alerts updatePanes:panes attention:rows];
        Check(center.posts.count == 1, @"Persist delivery across app relaunch");

        NSArray *switched = @[Pane(@"%4",@"stable-A",NO), Pane(@"%5",@"stable-B",YES)];
        [alerts updatePanes:switched attention:rows];
        Check([center.posts.lastObject.identifier isEqual:@"stable-A"], @"Switching focus exposes waiting A");
        [alerts updatePanes:switched attention:@{@"%5":Row(@"b2")}];
        Check(![center.delivered containsObject:@"stable-B"], @"Remove old B banner when a different focused request replaces it");
        [center finishAdd:@"stable-A"];
        Check(!center.delivered.count, @"Resolution during an in-flight post removes stale delivery");

        front=YES;
        [alerts updatePanes:panes attention:rows];
        Check(center.posts.count==2, @"RK foreground suppresses banners");
        front=NO;
        [alerts updatePanes:panes attention:rows];
        [center finishAdd:@"stable-B"];
        [alerts updatePanes:panes attention:@{}];
        Check(!center.delivered.count, @"Resolving a delivered request clears system notification");
        [alerts updatePanes:@[Pane(@"%5",@"replacement",NO)] attention:@{}];
        Click(center,banner);
        Check([opened isEqual:@"stable-B"], @"Click routes by durable managed identity even after tmux reuses pane number");

        FakeCenter *denied = [FakeCenter new];
        denied.grantsPermission=NO;
        RKAlerts *quiet = [[RKAlerts alloc] initWithOpen:open center:(id)denied defaults:defaults foreground:foreground];
        [quiet updatePanes:panes attention:rows];
        Drain();
        [quiet updatePanes:panes attention:rows];
        Check(denied.prompts == 1 && !denied.posts.count, @"Denied authorization never posts");
        RemoteCatchUp(defaults);
        [defaults removePersistentDomainForName:suite];
        puts("notification fixtures passed");
    }
}
