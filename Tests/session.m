#import "RKCore.h"

static int fixture(void) {
    puts("Use the selected project? [y/N]");
    fflush(stdout);
    char reply[256];
    if (!fgets(reply, sizeof(reply), stdin)) return 1;
    puts("Project selected.");
    puts("›");
    fflush(stdout);
    while (fgets(reply, sizeof(reply), stdin)) {
        puts("Revision complete.");
        puts("›");
        fflush(stdout);
    }
    return 0;
}

static NSDictionary *waitFor(RKCore *core, RKMonitor *monitor, NSString *paneID, NSString *kind) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    do {
        NSArray *panes = [core panes:NULL];
        NSDictionary *row = [monitor update:panes][paneID];
        if ([row[@"kind"] isEqual:kind]) return row;
        [NSThread sleepForTimeInterval:0.1];
    } while (deadline.timeIntervalSinceNow > 0);
    return nil;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc == 2 && !strcmp(argv[1], "fixture")) return fixture();
        [NSUserDefaults.standardUserDefaults setObject:@"off" forKey:@"RKHelperProvider"];
        RKCore *core = [RKCore new];
        NSArray *panes = [core panes:NULL];
        NSCAssert(panes.count == 1 && ![panes[0][@"managed"] boolValue], @"First discovery should be unmanaged");
        NSCAssert([core capture:panes[0][@"target"] error:NULL], @"Capture live fixture");
        NSDictionary *managed = [core panes:NULL].firstObject;
        NSCAssert([managed[@"managed"] boolValue] && ![managed[@"attached"] boolValue], @"Detached capture");
        RKMonitor *monitor = [[RKMonitor alloc] initWithCore:core];
        NSDictionary *row = waitFor(core, monitor, managed[@"id"], @"input");
        NSCAssert([row[@"choices"] count] == 2, @"Expected yes/no on first detached poll");
        NSCAssert([monitor answer:[row[@"choices"] firstObject] pane:managed[@"id"] fingerprint:row[@"fingerprint"] error:NULL], @"Answer live fixture");
        row = waitFor(core, monitor, managed[@"id"], @"complete");
        NSCAssert([row[@"summary"] containsString:@"Project selected"], @"Read exact result");
        [monitor markRead:managed[@"id"] fingerprint:row[@"fingerprint"]];
        monitor = [[RKMonitor alloc] initWithCore:core];
        NSCAssert(![monitor update:[core panes:NULL]][managed[@"id"]], @"Old completion stays read after reopening");
        NSCAssert([core sendText:@"Change the result." toPane:managed[@"target"] error:NULL], @"Steer live fixture");
        row = waitFor(core, monitor, managed[@"id"], @"complete");
        NSCAssert([row[@"summary"] containsString:@"Revision complete"], @"Surface the new handoff");
        NSCAssert([core end:managed[@"target"] error:NULL], @"End fixture session");
    }
    puts("detached capture, answer, reopen, and steer passed");
    return 0;
}
