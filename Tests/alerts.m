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
        [defaults removePersistentDomainForName:suite];
        puts("notification fixtures passed");
    }
}
