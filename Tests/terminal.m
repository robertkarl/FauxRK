#import "RKCore.h"
#import "RKRemoteTerminal.h"

@interface RKRemoteTerminal (Testing)
+ (NSString *)terminalCommandForMetadata:(NSDictionary *)metadata target:(NSString *)target destination:(NSString *)destination ssh:(NSString *)ssh error:(NSError **)error;
@end

@interface RKCore (Testing)
- (NSString *)tmux:(NSArray *)args error:(NSError **)error;
@end

static NSString *work;

static NSArray *parts0(NSString *target) { return [target componentsSeparatedByString:@"|"]; }

static NSString *trimmed(NSString *s) {
    return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *managedSession(RKCore *core, NSString *name, NSString *uuid) {
    NSString *pane = trimmed([core tmux:@[@"new-session", @"-d", @"-P", @"-F", @"#{pane_id}", @"-s", name, @"sleep", @"1000"] error:NULL]);
    NSCAssert(pane.length, @"Create fixture session");
    [core tmux:@[@"set-option", @"-p", @"-t", pane, @"@rk_managed", @"1", @";", @"set-option", @"-p", @"-t", pane, @"@rk_pane", pane,
                 @";", @"set-option", @"-p", @"-t", pane, @"@rk_id", uuid] error:NULL];
    for (NSDictionary *row in [core panes:NULL]) if ([row[@"id"] isEqual:pane]) {
        NSCAssert([row[@"managed"] boolValue], @"Fixture is managed");
        return row[@"target"];
    }
    return nil;
}

static NSDictionary *metadata(RKCore *core, NSString *target) {
    NSMutableDictionary *meta = [[core attachMetadata:target error:NULL] mutableCopy];
    NSCAssert(meta, @"Attach metadata");
    meta[@"binary"] = [work stringByAppendingPathComponent:@"tmuxw"];
    return meta;
}

static NSString *command(NSDictionary *meta, NSString *target, NSString *destination) {
    NSError *error;
    NSString *cmd = [RKRemoteTerminal terminalCommandForMetadata:meta target:target destination:destination
                                                             ssh:[work stringByAppendingPathComponent:@"fakessh"] error:&error];
    NSCAssert(cmd, @"Build command: %@", error);
    return cmd;
}

// Run the iTerm2 command string through sh, as iTerm2 parses it, inside a pty.
static NSTask *attach(NSString *cmd, NSString *iTermSession, NSPipe *keepOpen) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/script"];
    task.arguments = @[@"-q", @"/dev/null", @"/bin/sh", @"-c", cmd];
    NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
    [env removeObjectsForKeys:@[@"TMUX", @"TMUX_PANE"]];
    env[@"ITERM_SESSION_ID"] = iTermSession;
    env[@"TERM"] = @"xterm-256color";
    task.environment = env;
    task.standardInput = keepOpen;
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    [task launch];
    return task;
}

static NSArray *clients(RKCore *core) {
    NSString *out = trimmed([core tmux:@[@"list-clients", @"-F", @"#{client_pid} #{session_id}"] error:NULL] ?: @"");
    return out.length ? [out componentsSeparatedByString:@"\n"] : @[];
}

static void waitForClients(RKCore *core, NSUInteger count) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (clients(core).count != count && deadline.timeIntervalSinceNow > 0) [NSThread sleepForTimeInterval:0.05];
    NSCAssert(clients(core).count == count, @"Expected %lu clients, have %@", (unsigned long)count, clients(core));
}

static void waitForFocus(RKCore *core, NSString *token, NSString *pane) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (![[RKRemoteTerminal focusedPaneForToken:token core:core] isEqual:pane] && deadline.timeIntervalSinceNow > 0) [NSThread sleepForTimeInterval:0.05];
    NSCAssert([[RKRemoteTerminal focusedPaneForToken:token core:core] isEqual:pane], @"Token %@ should focus %@", token, pane);
}

static void rejects(id meta, id target, id destination, NSString *why) {
    NSError *error;
    NSCAssert(![RKRemoteTerminal terminalCommandForMetadata:meta target:target destination:destination ssh:@"/usr/bin/ssh" error:&error] && error.localizedDescription.length, @"Reject %@", why);
    error = nil;
    NSCAssert(![RKRemoteTerminal openAttachment:meta target:target destination:destination error:&error] && error.localizedDescription.length, @"Open rejects %@", why);
}

int main(void) {
    @autoreleasepool {
        work = NSProcessInfo.processInfo.environment[@"RK_TERMINAL_WORK"];
        RKCore *core = [[RKCore alloc] initWithDesktopFocus:NO];
        NSString *uuidA = NSUUID.UUID.UUIDString.lowercaseString, *uuidB = NSUUID.UUID.UUIDString.lowercaseString;
        NSString *targetA = managedSession(core, @"agent-a", uuidA), *targetB = managedSession(core, @"agent-b", uuidB);
        NSString *paneA = [targetA componentsSeparatedByString:@"|"][0], *paneB = [targetB componentsSeparatedByString:@"|"][0];
        NSDictionary *metaA = metadata(core, targetA), *metaB = metadata(core, targetB);

        // Malformed metadata, targets and destinations never reach osascript.
        NSString *dest = @"robert@debra.local";
        rejects(nil, targetA, dest, @"nil metadata");
        rejects(@[], targetA, dest, @"array metadata");
        rejects(@{}, targetA, dest, @"empty metadata");
        rejects(@{@"binary":@"tmux", @"sessionID":metaA[@"sessionID"]}, targetA, dest, @"relative binary");
        rejects(@{@"binary":@"/opt/homebrew/bin/tmux x", @"sessionID":metaA[@"sessionID"]}, targetA, dest, @"binary with space");
        rejects(@{@"binary":@"/opt/homebrew/bin/tmux';id;'", @"sessionID":metaA[@"sessionID"]}, targetA, dest, @"binary with quote");
        rejects(@{@"binary":@"/opt/../tmp/tmux", @"sessionID":metaA[@"sessionID"]}, targetA, dest, @"binary traversal");
        rejects(@{@"binary":@5, @"sessionID":metaA[@"sessionID"]}, targetA, dest, @"numeric binary");
        rejects(@{@"binary":@"/opt/homebrew/bin/tmux", @"sessionID":@"3"}, targetA, dest, @"session without $");
        rejects(@{@"binary":@"/opt/homebrew/bin/tmux", @"sessionID":@"$3;id"}, targetA, dest, @"session with command");
        rejects(@{@"binary":@"/opt/homebrew/bin/tmux", @"sessionID":@"$"}, targetA, dest, @"bare $");
        rejects(metaA, paneA, dest, @"bare pane target");
        rejects(metaA, [paneA stringByAppendingString:@"|1-2-3|"], dest, @"unmanaged target");
        rejects(metaA, [paneA stringByAppendingString:@"|1-2-3|not-a-uuid"], dest, @"invalid uuid");
        rejects(metaA, [NSString stringWithFormat:@"%@|1;id|%@", paneA, uuidA], dest, @"invalid generation");
        rejects(metaA, @[targetA], dest, @"non-string target");
        rejects(metaA, targetA, @"-oProxyCommand=touch", @"option destination");
        rejects(metaA, targetA, @"debra local", @"destination with space");
        rejects(metaA, targetA, @"debra;id", @"destination with semicolon");
        rejects(metaA, targetA, @"", @"empty destination");
        rejects(metaA, targetA, nil, @"nil destination");

        // Malformed tokens never match.
        NSCAssert(![RKRemoteTerminal focusedPaneForToken:@"" core:core], @"Empty token");
        NSCAssert(![RKRemoteTerminal focusedPaneForToken:@"w0t0p0:x" core:core], @"Non-UUID token");
        NSCAssert(![RKRemoteTerminal focusedPaneForToken:(id)@5 core:core], @"Non-string token");
        NSString *focused = [RKRemoteTerminal focusedToken];
        NSCAssert([focused isEqual:@""] || [[NSUUID alloc] initWithUUIDString:focused], @"focusedToken is empty or a UUID");

        // iTerm2 parses the command itself: only plain single-quoted runs, nothing nested.
        NSString *iTermCommand = command(metaA, targetA, dest);
        NSCAssert([iTermCommand componentsSeparatedByString:@"'"].count == 9 && ![iTermCommand containsString:@"\\"], @"Flat quoting: %@", iTermCommand);
        NSCAssert([iTermCommand hasPrefix:@"/bin/sh -c '"], @"Local shell launcher");

        // Two attached clients map to their own iTerm sessions and panes.
        NSString *tokenA = NSUUID.UUID.UUIDString, *tokenB = NSUUID.UUID.UUIDString;
        NSPipe *inA = [NSPipe pipe], *inB = [NSPipe pipe], *inC = [NSPipe pipe];
        NSTask *clientA = attach(command(metaA, targetA, dest), [@"w0t0p0:" stringByAppendingString:tokenA], inA);
        waitForClients(core, 1);
        NSString *log = [NSString stringWithContentsOfFile:[work stringByAppendingPathComponent:@"ssh-args"] encoding:NSUTF8StringEncoding error:NULL];
        NSString *prefix = [NSString stringWithFormat:@"-t\n-o\nStrictHostKeyChecking=yes\n-o\nBatchMode=yes\n--\n%@\nexec /bin/sh -c '", dest];
        NSCAssert([log hasPrefix:prefix], @"ssh -t -- destination, then one remote command: %@", log);
        NSString *suffix = [NSString stringWithFormat:@"'%@' %@\n", parts0(targetA)[2], tokenA];
        NSCAssert([log hasSuffix:suffix], @"Remote command ends with the managed UUID and iTerm session token: %@", log);
        waitForFocus(core, tokenA, paneA);
        NSTask *clientB = attach(command(metaB, targetB, dest), [@"w1t0p0:" stringByAppendingString:tokenB.lowercaseString], inB);
        waitForClients(core, 2);
        waitForFocus(core, tokenB, paneB);
        NSCAssert([[RKRemoteTerminal focusedPaneForToken:tokenA core:core] isEqual:paneA], @"First mapping survives");
        NSCAssert(![RKRemoteTerminal focusedPaneForToken:NSUUID.UUID.UUIDString core:core], @"Unknown token focuses nothing");
        NSCAssert(![RKRemoteTerminal focusedPaneForToken:@"" core:core], @"Empty token focuses nothing");

        // Overlapping terminal opens must not prune a new registration while
        // its peer is still being established.
        NSString *parallel = managedSession(core, @"parallel", NSUUID.UUID.UUIDString.lowercaseString);
        NSMutableArray<NSTask *> *workers = [NSMutableArray array];
        NSMutableArray<NSString *> *tokens = [NSMutableArray array];
        NSString *parallelCommand = command(metadata(core,parallel),parallel,dest);
        for (int i=0; i<4; i++) {
            NSString *token = NSUUID.UUID.UUIDString;
            [tokens addObject:token];
            [workers addObject:attach(parallelCommand, [@"w2:" stringByAppendingString:token], [NSPipe pipe])];
        }
        waitForClients(core, 6);
        for (NSString *token in tokens) waitForFocus(core,token,parts0(parallel).firstObject);
        [core tmux:@[@"detach-client",@"-s",@"parallel"] error:NULL];
        for (NSTask *worker in workers) [worker waitUntilExit];
        waitForClients(core,2);

        // A closed window stops suppressing even though its option is not yet pruned.
        [clientA terminate]; [clientA waitUntilExit];
        [core tmux:@[@"detach-client", @"-s", @"agent-a"] error:NULL];
        waitForClients(core, 1);
        NSCAssert(![RKRemoteTerminal focusedPaneForToken:tokenA core:core], @"Departed client no longer focuses");
        NSCAssert([[RKRemoteTerminal focusedPaneForToken:tokenB core:core] isEqual:paneB], @"Remaining mapping");

        // A hostile session ID is neither executed nor registered; the next attach prunes stale entries.
        NSString *pwned = [work stringByAppendingPathComponent:@"pwned"];
        NSTask *clientC = attach(command(metaA, targetA, dest), [NSString stringWithFormat:@"w2:$(touch %@)`touch %@`", pwned, pwned], inC);
        waitForClients(core, 2);
        NSCAssert(![NSFileManager.defaultManager fileExistsAtPath:pwned], @"Session ID was not executed");
        NSString *options = [core tmux:@[@"show-options", @"-s"] error:NULL];
        NSCAssert([options componentsSeparatedByString:@"@rk_iterm_"].count == 2 && [options containsString:tokenB.lowercaseString], @"Only live registrations remain: %@", options);

        // The remote guard refuses a changed generation or ownership marker before attaching.
        NSArray *parts = [targetA componentsSeparatedByString:@"|"];
        for (NSString *stale in @[[NSString stringWithFormat:@"%@|%@9|%@", parts[0], parts[1], parts[2]],
                                  [NSString stringWithFormat:@"%@|%@|%@", parts[0], parts[1], uuidB],
                                  [NSString stringWithFormat:@"%@|%@|%@", paneB, [targetB componentsSeparatedByString:@"|"][1], uuidB]]) {
            NSTask *task = [NSTask new];
            task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/script"];
            task.arguments = @[@"-q",@"/dev/null",@"/bin/sh",@"-c",command(metaA, stale, dest)];
            task.environment = @{@"ITERM_SESSION_ID":[@"w3:" stringByAppendingString:NSUUID.UUID.UUIDString], @"PATH":@"/usr/bin:/bin", @"TERM":@"xterm-256color"};
            NSPipe *err = [NSPipe pipe];
            task.standardInput = [NSPipe pipe];
            task.standardOutput = err;
            task.standardError = err;
            [task launch];
            NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:3];
            while (task.running && limit.timeIntervalSinceNow>0) [NSThread sleepForTimeInterval:.02];
            if (task.running) { [task terminate]; NSCAssert(NO,@"Mismatched target left a live terminal open"); }
            NSString *message = [[NSString alloc] initWithData:[err.fileHandleForReading readDataToEndOfFile] encoding:NSUTF8StringEncoding];
            [task waitUntilExit];
            NSCAssert(task.terminationStatus == 1 && [message containsString:@"FauxRK:"], @"Guard refuses %@: %@", stale, message);
            NSCAssert(clients(core).count == 2, @"Refused guard does not attach");
        }

        [clientB terminate]; [clientC terminate];
        [clientB waitUntilExit]; [clientC waitUntilExit];
        puts("terminal tests passed");
    }
    return 0;
}
