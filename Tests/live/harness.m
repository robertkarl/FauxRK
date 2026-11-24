// Live smoke harness: drives real agent CLIs through RKCore/RKMonitor on an
// isolated tmux socket. Refuses to run without an absolute RK_TMUX_SOCKET.
#import "RKCore.h"

static void out(NSString *fmt, ...) NS_FORMAT_FUNCTION(1,2);
static void out(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"HH:mm:ss.SSS";
    printf("[%s] %s\n", [f stringFromDate:NSDate.date].UTF8String, s.UTF8String);
    fflush(stdout);
}
static NSString *json(id obj) {
    if (!obj) return @"null";
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingSortedKeys|NSJSONWritingWithoutEscapingSlashes error:NULL];
    return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : [obj description];
}
static NSArray *managed(RKCore *core) {
    NSError *e; NSArray *p = [core panes:&e];
    if (!p) { out(@"panes error: %@", e.localizedDescription); return @[]; }
    return [p filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"managed == YES"]];
}
static NSDictionary *paneFor(RKCore *core, NSString *pid) {
    for (NSDictionary *p in managed(core)) if ([p[@"id"] isEqual:pid]) return p;
    return nil;
}
static NSString *tail(NSString *s, NSUInteger n) {
    NSMutableArray *l = [NSMutableArray new];
    for (NSString *x in [s componentsSeparatedByString:@"\n"]) if ([x stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length) [l addObject:x];
    NSUInteger k = MIN(n, l.count);
    return [[l subarrayWithRange:NSMakeRange(l.count-k, k)] componentsJoinedByString:@"\n"];
}

int main(int argc, const char **argv) { @autoreleasepool {
    NSString *sock = NSProcessInfo.processInfo.environment[@"RK_TMUX_SOCKET"];
    NSString *scratch = [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:@"build/tmp/"];
    if (!sock.isAbsolutePath || ![sock.stringByStandardizingPath hasPrefix:scratch]) {
        fprintf(stderr, "Run from the repository with RK_TMUX_SOCKET under build/tmp/.\n"); return 2;
    }
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{@"RKHelperProvider":@"off"} forName:NSArgumentDomain];
    NSMutableArray *a = [NSMutableArray new];
    for (int i = 1; i < argc; i++) [a addObject:@(argv[i])];
    if (!a.count) { fprintf(stderr, "usage: spawn|shape|screen|send|key|watch|answer|end\n"); return 2; }
    NSString *cmd = a[0];
    RKCore *core = [RKCore new];
    NSError *e = nil;
    if ([cmd isEqual:@"spawn"]) {                       // spawn PRESET DIR PROMPT
        NSString *pid = [core spawnPreset:a[1] directory:a[2] prompt:a.count > 3 ? a[3] : @"" error:&e];
        if (!pid) { out(@"spawn FAILED: %@", e.localizedDescription); return 1; }
        printf("%s\n", pid.UTF8String); return 0;
    }
    if ([cmd isEqual:@"shape"]) {
        NSArray *p = [core panes:&e];
        for (NSDictionary *x in p) printf("%s\n", json(x).UTF8String);
        return p ? 0 : 1;
    }
    if ([cmd isEqual:@"screen"]) { NSString *s = [core screen:a[1] error:&e]; printf("%s", (s ?: e.localizedDescription).UTF8String); return s ? 0 : 1; }
    if ([cmd isEqual:@"send"]) { BOOL ok = [core sendText:a[2] toPane:a[1] error:&e]; out(@"sendText %@ -> %@ %@", a[1], ok ? @"ok" : @"FAILED", e.localizedDescription ?: @""); return !ok; }
    if ([cmd isEqual:@"key"]) { BOOL ok = [core sendKey:a[2] toPane:a[1] error:&e]; out(@"sendKey %@ %@ -> %@ %@", a[1], a[2], ok ? @"ok" : @"FAILED", e.localizedDescription ?: @""); return !ok; }
    if ([cmd isEqual:@"end"]) { BOOL ok = [core end:a[1] error:&e]; out(@"end %@ -> %@ %@", a[1], ok ? @"ok" : @"FAILED", e.localizedDescription ?: @""); return !ok; }
    RKMonitor *m = [[RKMonitor alloc] initWithCore:core];
    if ([cmd isEqual:@"watch"]) {                       // watch PANE SECONDS [KIND...]: print row transitions, exit 0 when a listed kind appears
        NSString *pid = a[1]; double limit = [a[2] doubleValue];
        NSArray *until = [a subarrayWithRange:NSMakeRange(3, a.count-3)];
        NSDate *start = NSDate.date; NSString *last = @"<start>"; NSString *lastScreen = nil;
        while (-start.timeIntervalSinceNow < limit) {
            NSDictionary *pane = paneFor(core, pid);
            if (!pane) { out(@"pane %@ gone", pid); return 3; }
            NSDictionary *row = [m update:managed(core)][pid];
            NSString *now = row ? json(row) : @"(none)";
            NSString *screen = [core screen:pid error:NULL];
            if (![now isEqual:last]) {
                out(@"t+%.1fs cmd=%@ row=%@", -start.timeIntervalSinceNow, pane[@"command"], now);
                out(@"  screen tail:\n%@", tail(screen, 14));
                last = now;
            }
            lastScreen = screen;
            if (row && [until containsObject:row[@"kind"]]) return 0;
            [NSThread sleepForTimeInterval:0.5];
        }
        out(@"watch timeout after %.0fs; last row=%@\n%@", limit, last, tail(lastScreen, 20));
        return 4;
    }
    if ([cmd isEqual:@"answer"]) {                      // answer PANE LABEL_REGEX [draft TEXT]
        NSString *pid = a[1]; NSDictionary *row = nil;
        for (int i = 0; i < 6 && !row; i++) { row = [m update:managed(core)][pid]; if (!row) [NSThread sleepForTimeInterval:0.4]; }
        if (!row) { out(@"answer: no row for %@", pid); return 1; }
        out(@"answer: current row %@", json(row));
        NSDictionary *choice = nil;
        if ([a[2] isEqual:@"draft"]) choice = @{@"label":@"Reply", @"text":a[3], @"draft":@YES};
        else for (NSDictionary *c in row[@"choices"])
            if ([c[@"label"] rangeOfString:a[2] options:NSRegularExpressionSearch|NSCaseInsensitiveSearch].location != NSNotFound) { choice = c; break; }
        if (!choice) { out(@"answer: no choice matching %@", a[2]); return 1; }
        BOOL ok = [m answer:choice pane:pid fingerprint:row[@"fingerprint"] error:&e];
        out(@"answer %@ -> %@ %@", json(choice), ok ? @"ok" : @"FAILED", e.localizedDescription ?: @"");
        return !ok;
    }
    fprintf(stderr, "unknown command\n"); return 2;
}}
