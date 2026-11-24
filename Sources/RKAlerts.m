#import "RKAlerts.h"
#import <UserNotifications/UserNotifications.h>

NSString *const RKAlertsThisMac = @"This Mac";
NSString *const RKAlertsDebra = @"Debra";

@interface RKAlerts () <UNUserNotificationCenterDelegate>
@property (copy) void (^open)(NSString *);
@property (copy) BOOL (^foreground)(void);
@property UNUserNotificationCenter *center;
@property NSUserDefaults *defaults;
@property NSString *socket;
@property NSString *computer;
@property NSUInteger generation;
@property NSMutableDictionary<NSString *, NSString *> *delivered;
@property NSMutableSet<NSString *> *pending;
@property NSDictionary<NSString *, NSString *> *live;
@property NSDictionary<NSString *, NSString *> *summarized;
@property BOOL catchUp;
@property BOOL postingSummary;
@property NSUInteger catchUpCycle;
@property BOOL requested;
@property BOOL resolved;
@property BOOL authorized;
@property NSString *store;
@end

@implementation RKAlerts
- (instancetype)initWithOpen:(void (^)(NSString *))open {
    return [self initWithOpen:open center:UNUserNotificationCenter.currentNotificationCenter
                     defaults:NSUserDefaults.standardUserDefaults foreground:^BOOL{ return NSApp.isActive; }];
}

- (instancetype)initWithOpen:(void (^)(NSString *))open center:(UNUserNotificationCenter *)center
                    defaults:(NSUserDefaults *)defaults foreground:(BOOL (^)(void))foreground {
    if (!(self = [super init])) return nil;
    _open = [open copy];
    _foreground = [foreground copy];
    _defaults = defaults;
    _socket = NSProcessInfo.processInfo.environment[@"RK_TMUX_SOCKET"] ?: @"default";
    _center = center;
    _center.delegate = self;
    // A summary describes the backlog at a particular reconnect. Relaunch
    // opens the sidebar again; either computer's old aggregate may be stale.
    // Individual handoff receipts remain available to suppress duplicates.
    [center removeDeliveredNotificationsWithIdentifiers:@[[@"RKCatchUp." stringByAppendingString:RKAlertsThisMac],
                                                           [@"RKCatchUp." stringByAppendingString:RKAlertsDebra]]];
    [self loadComputer:RKAlertsThisMac];
    return self;
}

- (void)loadComputer:(NSString *)computer {
    self.computer = computer;
    self.generation++;
    self.store = [computer isEqual:RKAlertsThisMac] ? [@"RKAlertState." stringByAppendingString:self.socket] : [@"RKAlertState." stringByAppendingString:computer];
    self.delivered = [[self.defaults dictionaryForKey:self.store] mutableCopy] ?: [NSMutableDictionary dictionary];
    self.pending = [NSMutableSet set];
    self.live = @{};
    self.summarized = @{};
    self.catchUp = NO;
    self.postingSummary = NO;
}

- (NSString *)notificationID:(NSString *)identity {
    return [self.computer isEqual:RKAlertsThisMac] ? identity : [NSString stringWithFormat:@"%@:%@", self.computer, identity];
}

- (NSString *)summaryID { return [@"RKCatchUp." stringByAppendingString:self.computer]; }

- (void)selectComputer:(NSString *)computer {
    if (![@[RKAlertsThisMac, RKAlertsDebra] containsObject:computer ?: @""] || [computer isEqual:self.computer]) return;
    NSMutableArray *old = [NSMutableArray arrayWithObject:self.summaryID];
    for (NSString *identity in self.delivered) [old addObject:[self notificationID:identity]];
    for (NSString *identity in self.pending) [old addObject:[self notificationID:identity]];
    [self.center removeDeliveredNotificationsWithIdentifiers:old];
    [self loadComputer:computer];
}

- (void)beginCatchUp { self.catchUp = YES; self.catchUpCycle++; }

- (void)authorize {
    if (self.requested) return;
    self.requested = YES;
    [self.center requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound completionHandler:^(BOOL allowed, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ self.authorized = allowed; self.resolved = YES; });
    }];
}

- (void)saveDelivered { [self.defaults setObject:self.delivered forKey:self.store]; }

// Posts a request; the completion is discarded (and its banner withdrawn) if the computer changed or the request went stale.
- (void)post:(NSString *)notificationID content:(UNNotificationContent *)content fresh:(BOOL (^)(void))fresh done:(void (^)(void))done {
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:notificationID content:content trigger:nil];
    NSUInteger generation = self.generation;
    __weak typeof(self) weakSelf = self;
    [self.center addNotificationRequest:request withCompletionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            if (self.generation != generation) {
                if (!error) [self.center removeDeliveredNotificationsWithIdentifiers:@[notificationID]];
                return;
            }
            if (done) done();
            if (error) return;
            if (!fresh()) [self.center removeDeliveredNotificationsWithIdentifiers:@[notificationID]];
        });
    }];
}

- (BOOL)eligible:(NSDictionary *)pane identity:(NSString *)identity fingerprint:(NSString *)fingerprint {
    return ![pane[@"focused"] boolValue] && ![self.delivered[identity] isEqual:fingerprint] && ![self.pending containsObject:identity];
}

- (void)sendRow:(NSDictionary *)row pane:(NSDictionary *)pane identity:(NSString *)identity {
    NSString *fingerprint = row[@"fingerprint"];
    if (!self.authorized || self.foreground() || ![self eligible:pane identity:identity fingerprint:fingerprint]) return;
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.title = [pane[@"title"] length] ? pane[@"title"] : pane[@"session"];
    content.body = row[@"summary"] ?: row[@"question"] ?: @"Agent needs attention";
    content.userInfo = @{@"identity":identity, @"computer":self.computer};
    [self.pending addObject:identity];
    __weak typeof(self) weakSelf = self;
    [self post:[self notificationID:identity] content:content fresh:^BOOL{
        __strong typeof(weakSelf) self = weakSelf;
        if (![self.live[identity] isEqual:fingerprint]) return NO;
        self.delivered[identity] = fingerprint;
        [self saveDelivered];
        return YES;
    } done:^{ [weakSelf.pending removeObject:identity]; }];
}

// A catch-up stays active until it is acknowledged, consumed in front, or has no eligible requests.
- (BOOL)catchUpPanes:(NSArray<NSDictionary *> *)waiting attention:(NSDictionary *)rows {
    if (self.postingSummary) return NO;
    NSMutableDictionary *backlog = [NSMutableDictionary dictionary];
    for (NSDictionary *pane in waiting) {
        NSDictionary *row = rows[pane[@"id"]];
        if (![self eligible:pane identity:pane[@"rkID"] fingerprint:row[@"fingerprint"]]) continue;
        backlog[pane[@"rkID"]] = row[@"fingerprint"];
    }
    if (backlog.count && !self.resolved) return NO;
    if (!backlog.count || !self.authorized) return YES;
    if (self.foreground()) {
        // The sidebar already brought these rows back into view.
        [self.delivered addEntriesFromDictionary:backlog];
        [self saveDelivered];
        return YES;
    }
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.title = [NSString stringWithFormat:@"Reconnected to %@", self.computer];
    content.body = backlog.count == 1 ? @"1 agent needs your attention" :
        [NSString stringWithFormat:@"%lu agents need your attention", (unsigned long)backlog.count];
    content.userInfo = @{@"catchUp":@YES, @"computer":self.computer};
    self.postingSummary = YES;
    NSUInteger cycle = self.catchUpCycle;
    __weak typeof(self) weakSelf = self;
    [self post:self.summaryID content:content fresh:^BOOL{
        __strong typeof(weakSelf) self = weakSelf;
        // Only this success path may record delivery. A failed add leaves
        // catchUp set; the next poll retries one summary for the current backlog.
        NSMutableDictionary *remaining = [NSMutableDictionary dictionary];
        [backlog enumerateKeysAndObjectsUsingBlock:^(NSString *identity, NSString *fingerprint, BOOL *stop) {
            if ([self.live[identity] isEqual:fingerprint]) remaining[identity] = fingerprint;
        }];
        if (self.catchUpCycle == cycle) self.catchUp = NO;
        self.summarized = remaining;
        if (remaining.count) {
            [self.delivered addEntriesFromDictionary:remaining];
            [self saveDelivered];
        }
        return remaining.count > 0 && !self.foreground();
    } done:^{ weakSelf.postingSummary = NO; }];
    return NO;
}

- (BOOL)summaryLive {
    for (NSString *identity in self.summarized) if ([self.summarized[identity] isEqual:self.live[identity]]) return YES;
    return NO;
}

- (void)updatePanes:(NSArray<NSDictionary *> *)panes attention:(NSDictionary<NSString *,NSDictionary *> *)rows {
    NSMutableDictionary *live = [NSMutableDictionary dictionary];
    NSMutableArray *waiting = [NSMutableArray array];
    for (NSDictionary *pane in panes) {
        if (![pane[@"managed"] boolValue]) continue;
        [self authorize];
        NSString *identity = pane[@"rkID"];
        NSDictionary *row = rows[pane[@"id"]];
        NSString *fingerprint = row[@"fingerprint"];
        if (!identity.length || !fingerprint.length) continue;
        live[identity] = fingerprint;
        [waiting addObject:pane];
    }
    self.live = live;
    [self clearObsoleteDeliveries];
    if (self.catchUp) {
        self.catchUp = ![self catchUpPanes:waiting attention:rows];
        return;
    }
    for (NSDictionary *pane in waiting) {
        [self sendRow:rows[pane[@"id"]] pane:pane identity:pane[@"rkID"]];
    }
}

- (void)clearObsoleteDeliveries {
    if (self.summarized.count && ![self summaryLive]) {
        self.summarized = @{};
        [self.center removeDeliveredNotificationsWithIdentifiers:@[self.summaryID]];
    }
    NSMutableArray *obsolete = [NSMutableArray array];
    [self.delivered enumerateKeysAndObjectsUsingBlock:^(NSString *identity, NSString *fingerprint, BOOL *stop) {
        if (![fingerprint isEqual:self.live[identity]]) [obsolete addObject:identity];
    }];
    if (!obsolete.count) return;
    NSMutableArray *ids = [NSMutableArray array];
    for (NSString *identity in obsolete) [ids addObject:[self notificationID:identity]];
    [self.center removeDeliveredNotificationsWithIdentifiers:ids];
    [self.delivered removeObjectsForKeys:obsolete];
    [self saveDelivered];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)(void))done {
    UNNotificationRequest *request = response.notification.request;
    NSDictionary *info = request.content.userInfo;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *computer = [info[@"computer"] isKindOfClass:NSString.class] ? info[@"computer"] : RKAlertsThisMac;
        NSString *identity = info[@"identity"];
        if (![computer isEqual:self.computer]) {
            [self.center removeDeliveredNotificationsWithIdentifiers:@[request.identifier]];
        } else if ([info[@"catchUp"] isEqual:@YES] && [request.identifier isEqual:self.summaryID]) {
            self.open(@"");
        } else if ([identity isKindOfClass:NSString.class] && identity.length && [[self notificationID:identity] isEqual:request.identifier]) {
            self.open(identity);
        }
        done();
    });
}
@end
