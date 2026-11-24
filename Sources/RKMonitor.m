#import "RKMonitorInternal.h"
#import <CommonCrypto/CommonDigest.h>

static NSString *const RKLastHandoffs = @"RKLastHandoffsV1";

NSString *RKString(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
NSString *RKTrim(NSString *s) { return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; }
NSString *RKShort(NSString *s, NSUInteger limit) {
    if (s.length <= limit) return s;
    return [s substringWithRange:[s rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, limit)]];
}
NSString *RKLine(id value, NSUInteger limit) {
    NSArray *lines = [RKString(value) componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray *words = [NSMutableArray new];
    for (NSString *part in lines) if (part.length) [words addObject:part];
    return RKShort([words componentsJoinedByString:@" "], limit);
}
NSError *RKMonitorError(NSString *message) {
    return [NSError errorWithDomain:@"RKMonitor" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static NSString *RKHash(NSString *s) {
    NSData *data = [s dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, bytes);
    NSMutableString *digest = [NSMutableString stringWithCapacity:64];
    for (NSUInteger i = 0; i < sizeof(bytes); i++) [digest appendFormat:@"%02x", bytes[i]];
    return digest;
}
@interface RKMonitor ()
@property(nonatomic,strong) RKCore *core;
@property(nonatomic,strong) NSDate *startedAt;
@property(nonatomic,strong) NSUserDefaults *handoffDefaults;
@property(nonatomic,strong) NSOperationQueue *helpers;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSMutableDictionary *> *observations;
@property(nonatomic,strong) NSMutableDictionary *handoffs;
@end

@implementation RKMonitor
- (instancetype)initWithCore:(RKCore *)core {
    return [self initWithCore:core handoffDefaults:NSUserDefaults.standardUserDefaults];
}
- (instancetype)initWithCore:(RKCore *)core handoffDefaults:(NSUserDefaults *)defaults {
    if ((self = [super init])) {
        _startedAt = [NSDate date];
        _handoffDefaults = defaults;
        _core = core;
        _helpers = [NSOperationQueue new];
        _helpers.name = @"RK assistant summaries";
        _helpers.maxConcurrentOperationCount = 4;
        _observations = [NSMutableDictionary new];
        _handoffs = [[defaults dictionaryForKey:RKLastHandoffs] mutableCopy] ?: [NSMutableDictionary new];
    }
    return self;
}
- (void)saveHandoff:(NSDictionary *)handoff forID:(NSString *)rkID {
    if ([_handoffs[rkID] isEqual:handoff] || (!_handoffs[rkID] && !handoff)) return;
    _handoffs[rkID] = handoff;
    [self.handoffDefaults setObject:_handoffs forKey:RKLastHandoffs];
}

- (void)requestHelper:(NSString *)screen signature:(NSString *)signature pane:(NSString *)pid provider:(NSString *)provider observation:(NSMutableDictionary *)obs {
    if ([provider isEqual:@"off"] || obs[@"helper"] || obs[@"pending"] || [obs[@"retryAt"] timeIntervalSinceNow] > 0 ||
        _helpers.operationCount >= (NSUInteger)_helpers.maxConcurrentOperationCount) return;
    obs[@"pending"] = @YES;
    __weak RKMonitor *weakSelf = self;
    [_helpers addOperationWithBlock:^{
        @autoreleasepool {
            NSDictionary *result = RKInfer(weakSelf.core, screen, provider, NULL);
            RKMonitor *self = weakSelf;
            if (!self) return;
            @synchronized (self) {
                NSMutableDictionary *current = self.observations[pid];
                if (current != obs || ![current[@"signature"] isEqual:signature]) return;
                current[@"pending"] = nil;
                current[@"helper"] = result;
                if (!result) current[@"retryAt"] = [NSDate dateWithTimeIntervalSinceNow:60];
            }
        }
    }];
}

- (NSDictionary *)observeScreen:(NSString *)screen pane:(NSDictionary *)pane {
    NSString *pid = pane[@"id"], *rkID = pane[@"rkID"] ?: pane[@"session"] ?: pid;
    NSArray *lines = RKLines(screen);
    NSString *provider = RKProvider();
    NSArray *body = RKContent(lines);
    NSString *signature = RKHash([body componentsJoinedByString:@"\n"]);
    NSString *configuration = [NSString stringWithFormat:@"%@/%@", provider, RKLocalModel()];
    NSMutableDictionary *obs = _observations[pid];
    if (![obs[@"signature"] isEqual:signature] || ![obs[@"configuration"] isEqual:configuration] || ![obs[@"rkID"] isEqual:rkID]) {
        obs = [@{@"signature":signature, @"configuration":configuration, @"rkID":rkID, @"target":pane[@"target"] ?: pid, @"since":[NSDate date]} mutableCopy];
        _observations[pid] = obs;
    }
    NSTimeInterval age = -[obs[@"since"] timeIntervalSinceNow];
    NSDictionary *local = RKClassify(lines, pane);
    NSString *tail = body.lastObject ?: lines.lastObject ?: @"";
    NSString *command = RKString(pane[@"command"]).lastPathComponent.lowercaseString;
    BOOL shell = [@[@"zsh", @"-zsh", @"bash", @"-bash", @"sh", @"fish", @"login"] containsObject:command];
    BOOL idleShell = shell && RKMatches(tail, @"[%$#❯➜]\\s*$");
    BOOL busy = RKBusy(body);
    BOOL welcome = RKWelcome(body, lines) && !local;
    if (lines.count && !idleShell && !busy && !welcome && age >= 0.65)
        [self requestHelper:screen signature:signature pane:pid provider:provider observation:obs];
    NSDictionary *inference = obs[@"helper"];
    NSString *state = RKString(inference[@"state"]);
    NSMutableDictionary *row = [local mutableCopy];
    if (!row && !busy && !idleShell && !welcome) {
        if ([@[@"complete", @"input", @"maybe"] containsObject:state]) {
            NSString *question = RKLine(inference[@"question"], 1000);
            NSString *summary = RKLine(inference[@"summary"], 210);
            row = [RKAttentionRow(state, question.length ? question : summary, @[]) mutableCopy];
        } else if (!state.length && age >= 1.4 && lines.count) {
            // A helper outage must never hide an unrecognized stationary prompt.
            row = [RKAttentionRow(@"maybe", tail, @[]) mutableCopy];
        }
    }
    if (row && inference) {
        NSString *summary = RKLine(inference[@"summary"], 210);
        NSString *suggestion = RKLine(inference[@"suggestedReply"], 1200);
        if (summary.length && [state isEqual:row[@"kind"]]) row[@"summary"] = summary;
        if (suggestion.length && ![row[@"choices"] count] && [state isEqual:@"input"]) row[@"suggestedReply"] = suggestion;
        if ([local[@"kind"] isEqual:@"complete"] && [state isEqual:@"input"]) {
            row[@"kind"] = @"input";
            NSString *question = RKLine(inference[@"question"], 1000);
            if (question.length) row[@"question"] = question;
            if (summary.length) row[@"summary"] = summary;
        }
    }
    NSDictionary *saved = _handoffs[rkID];
    if (!row) {
        // An immediate local 'working' signal or an idle shell resolves a handoff.
        // While debouncing an unknown new screen leave its read marker intact,
        // including across a relaunch before inference has returned.
        if (busy || idleShell || welcome || [@[@"idle", @"working"] containsObject:state]) [self saveHandoff:nil forID:rkID];
        obs[@"row"] = nil;
        return nil;
    }
    // Bind the event to its observed context. Identical "Proceed?" menus for
    // different commands must not share an actionable fingerprint.
    NSString *event = saved[@"id"];
    BOOL same = [saved[@"signature"] isEqual:signature];
    if (!same || !event) event = NSUUID.UUID.UUIDString;
    row[@"fingerprint"] = event;
    NSDate *sentAt = same && [saved[@"sentAt"] isKindOfClass:NSDate.class] ? saved[@"sentAt"] : nil;
    // Preserve the receipt through an SSH timeout and reconnect. On the
    // submitting connection the person can retry an unchanged prompt sooner.
    NSTimeInterval elapsed = -[sentAt timeIntervalSinceNow];
    if (elapsed >= 25) sentAt = nil;
    BOOL restored = sentAt && [sentAt compare:_startedAt] == NSOrderedAscending;
    obs[@"sent"] = restored || elapsed < 4 ? sentAt : nil;
    if (obs[@"sent"]) row[@"responseSent"] = @YES;
    BOOL read = same && [saved[@"read"] boolValue] && [row[@"kind"] isEqual:@"complete"];
    NSMutableDictionary *handoff = [@{@"id":event, @"signature":signature, @"read":@(read)} mutableCopy];
    if (sentAt) handoff[@"sentAt"] = sentAt;
    [self saveHandoff:handoff forID:rkID];
    obs[@"row"] = [row copy];
    return read ? nil : obs[@"row"];
}

- (NSDictionary<NSString *,NSDictionary *> *)update:(NSArray<NSDictionary *> *)panes {
    NSMutableDictionary *rows = [NSMutableDictionary new];
    NSMutableSet *live = [NSMutableSet new];
    for (NSDictionary *pane in panes) {
        NSString *pid = pane[@"id"];
        if (![pane[@"managed"] boolValue] || !pid.length) continue;
        [live addObject:pid];
        NSString *screen = [_core screen:pane[@"target"] ?: pid error:NULL];
        @synchronized (self) {
            if (screen) {
                NSDictionary *row = [self observeScreen:screen pane:pane];
                if (row) rows[pid] = row;
            } else {
                NSDictionary *obs = _observations[pid];
                NSDictionary *row = obs[@"row"];
                if (row && ![_handoffs[obs[@"rkID"]][@"read"] boolValue]) rows[pid] = row;
            }
        }
    }
    @synchronized (self) {
        for (NSString *old in _observations.allKeys) if (![live containsObject:old]) [_observations removeObjectForKey:old];
    }
    return rows;
}
- (void)markRead:(NSString *)pid fingerprint:(NSString *)fingerprint {
    @synchronized (self) {
        NSDictionary *obs = _observations[pid], *row = obs[@"row"];
        if (![row[@"kind"] isEqual:@"complete"] || ![row[@"fingerprint"] isEqual:fingerprint]) return;
        NSString *rkID = obs[@"rkID"];
        NSMutableDictionary *saved = [_handoffs[rkID] mutableCopy];
        saved[@"read"] = @YES;
        [self saveHandoff:saved forID:rkID];
    }
}
- (BOOL)answer:(NSDictionary *)choice pane:(NSString *)pid fingerprint:(NSString *)fingerprint error:(NSError **)error {
    NSString *target;
    @synchronized (self) { target = _observations[pid][@"target"]; }
    if (!target) { if (error) *error = RKMonitorError(@"This agent is no longer available."); return NO; }
    NSString *latest = [_core screen:target error:error];
    if (!latest) return NO;
    NSString *signature = RKHash([RKContent(RKLines(latest)) componentsJoinedByString:@"\n"]);
    @synchronized (self) {
        NSMutableDictionary *obs = _observations[pid];
        NSDictionary *row = obs[@"row"];
        BOOL unchanged = [target isEqual:obs[@"target"]] && [obs[@"signature"] isEqual:signature] && [row[@"fingerprint"] isEqual:fingerprint];
        BOOL listed = [row[@"choices"] containsObject:choice];
        BOOL draft = [choice[@"draft"] boolValue] && RKTrim(RKString(choice[@"text"])).length > 0 &&
                     [row[@"choices"] count] == 0 && [@[@"input",@"maybe"] containsObject:row[@"kind"] ?: @""];
        if (!unchanged || (!listed && !draft) || obs[@"sent"]) {
            if (error) *error = RKMonitorError(@"The prompt has changed or a response was already sent. Check the current request.");
            return NO;
        }
        BOOL sent;
        if (listed && choice[@"keys"]) sent = [_core sendKeys:choice[@"keys"] toPane:target error:error];
        else if (listed && choice[@"key"]) sent = [_core sendKey:choice[@"key"] toPane:target error:error];
        else sent = [_core sendText:choice[@"text"] toPane:target error:error];
        if (sent) {
            obs[@"sent"] = [NSDate date];
            // A fresh SSH helper may see the same prompt before its UI redraws.
            NSMutableDictionary *saved = [_handoffs[obs[@"rkID"]] mutableCopy];
            saved[@"sentAt"] = obs[@"sent"];
            [self saveHandoff:saved forID:obs[@"rkID"]];
        }
        return sent;
    }
}
- (BOOL)steer:(NSString *)text toTarget:(NSString *)target error:(NSError **)error {
    // A text send pastes and presses Return. If a chooser appeared after the
    // card last refreshed, Return could select its default instead of steering.
    @synchronized (_core) {
        NSString *screen = [_core screen:target error:error];
        if (!screen) return NO;
        NSArray *lines = RKLines(screen);
        NSDictionary *current = RKClassify(lines, @{});
        BOOL interactiveFooter = RKMatches(lines.lastObject ?: @"", @"^(?:press )?enter (?:to )?(?:select|confirm|continue).*esc");
        if ([current[@"choices"] count] || interactiveFooter) {
            if (error) *error = RKMonitorError(@"This agent is showing a choice menu. Answer its current request in Needs attention.");
            return NO;
        }
        return [_core sendText:text toPane:target error:error];
    }
}
- (NSString *)preview:(NSString *)pid error:(NSError **)error {
    NSString *screen = [_core screen:pid error:error];
    if (!screen) return nil;
    if (!RKTrim(screen).length) return @"The pane is empty.";
    NSError *failure = nil;
    NSDictionary *inference = RKInfer(_core, screen, RKProvider(), &failure);
    NSString *summary = RKLine(inference[@"summary"], 240);
    if (summary.length) return summary;
    // A local excerpt remains useful if offline; clearly distinguish it from a model summary.
    NSArray *lines = RKLines(screen);
    NSUInteger n = MIN(6, lines.count);
    NSArray *excerpt = [lines subarrayWithRange:NSMakeRange(lines.count - n, n)];
    return [NSString stringWithFormat:@"Screen excerpt%@\n%@", failure.localizedDescription.length ? [NSString stringWithFormat:@" · %@",failure.localizedDescription] : @"", RKShort([excerpt componentsJoinedByString:@"\n"], 900)];
}
@end
