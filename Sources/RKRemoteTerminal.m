#import "RKRemoteTerminal.h"
#import "RKCore.h"
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <signal.h>

static NSString *const RKITermBundle = @"com.googlecode.iterm2";
static NSString *const RKTerminalErrorDomain = @"net.robertkarl.FauxRK.Terminal";

@interface RKCore (RKRemoteTerminalTmux)
- (NSString *)tmux:(NSArray *)args error:(NSError **)error;
@end

static BOOL RKTerminalFail(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:RKTerminalErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}

static NSString *RKQuote(NSString *s) {
    return [NSString stringWithFormat:@"'%@'", [s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

static BOOL RKOnly(NSString *s, NSString *allowed) {
    return [s isKindOfClass:NSString.class] && s.length &&
        [s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:allowed].invertedSet].location == NSNotFound;
}

static BOOL RKPrefixedNumber(NSString *s, NSString *prefix) {
    return [s isKindOfClass:NSString.class] && s.length > 1 && [s hasPrefix:prefix] && RKOnly([s substringFromIndex:1], @"0123456789");
}

static NSString *RKUUIDToken(NSString *s) {
    if (![s isKindOfClass:NSString.class] || s.length != 36 || ![[NSUUID alloc] initWithUUIDString:s]) return nil;
    return s;
}

// One outstanding focus query may wait on macOS Automation, including a
// preflight that blocks before osascript starts. Snapshot callers share it.
@interface RKFocusProbe : NSObject
@property dispatch_group_t finished;
@property (atomic, copy) NSString *token;
@end
@implementation RKFocusProbe
@end

// Runs on the remote host as: /bin/sh -c GUARD fauxrk TMUX SOCKET SESSION PANE GENERATION UUID TOKEN.
// The state check repeats the helper's managed-lifetime validation at attach time. The
// registration names the client by $$, which exec preserves as the tmux client PID.
// Every attach first drops registrations whose client PID is no longer attached.
static NSString *const RKRemoteGuard =
    @"fail() { printf \"FauxRK: %s\\n\" \"$1\" >&2; printf \"Press Return to close.\" >&2; read -r _ || true; exit 1; }\n"
    "tmux=$1 socket=$2 sid=$3 pane=$4 gen=$5 uuid=$6 token=${7-}\n"
    "[ -x \"$tmux\" ] || fail \"tmux is not installed at $tmux.\"\n"
    "unset TMUX TMUX_PANE\n"
    "set -- \"$tmux\"\n"
    "[ -z \"$socket\" ] || set -- \"$tmux\" -S \"$socket\"\n"
    "actual='#{session_id}|#{pid}-#{start_time}-#{pane_pid}|#{@rk_id}|#{@rk_pane}|#{@rk_managed}'\n"
    "expected=\"$sid|$gen|$uuid|$pane|1\"\n"
    "case $token in *[!0-9A-Fa-f-]*) token= ;; [0-9A-Fa-f]*-*-*-*-*) ;; *) token= ;; esac\n"
    // Enumerate registration candidates before the live clients. An attach
    // that arrives during cleanup cannot appear as a newly stale candidate.
    "candidates=$(\"$@\" show-options -s 2>/dev/null)\n"
    "live=\" $(\"$@\" list-clients -F '#{client_pid}' 2>/dev/null | tr '\\n' ' ') \"\n"
    "printf '%s\\n' \"$candidates\" | while read -r name registered _; do\n"
    "  case $name in @rk_iterm_*) pid=${name#@rk_iterm_} ;; *) continue ;; esac\n"
    "  case $pid in ''|*[!0-9]*) continue ;; esac\n"
    "  case $registered in ''|*[!0-9A-Fa-f-]*) continue ;; esac\n"
    "  case $live in *\" $pid \"*) continue ;; esac\n"
    "  \"$@\" if-shell -F \"#{==:#{$name},$registered}\" \"set-option -su $name\"\n"
    "done\n"
    "attach=\"attach-session -t '$sid'\"\n"
    "[ -z \"$token\" ] || attach=\"$attach ; set-option -s @rk_iterm_$$ $token\"\n"
    // The condition, attach and registration run together on one tmux server,
    // including when a previously resolved pane ID was reused after a restart.
    "exec \"$@\" if-shell -F -t \"$pane\" \"#{==:$actual,$expected}\" \"$attach\" "
    "\"display-message -p 'FauxRK: This agent changed. Refresh and open it again.' ; run-shell /usr/bin/false\"\n";

// Runs locally in the new iTerm2 session as: /bin/sh -c LAUNCHER fauxrk BASE64(REMOTE) DESTINATION SSH.
// iTerm2 splits its command string itself, so every argument is a single-quoted run with no
// embedded quotes. The session ID is expanded here and reduced to UUID characters before ssh.
static NSString *const RKLocalLauncher =
    @"r=$(printf %s \"$1\" | /usr/bin/base64 -D) || exit 1\n"
    "t=${ITERM_SESSION_ID#*:}\n"
    "case $t in \"\"|*[!0-9A-Fa-f-]*) t=- ;; esac\n"
    "exec \"$3\" -t -o StrictHostKeyChecking=yes -o BatchMode=yes -- \"$2\" \"$r $t\"\n";

@implementation RKRemoteTerminal

// A TCC permission prompt can keep osascript alive beyond AppleScript's
// own event timeout. Bound the actual process and its output pipes too.
+ (NSString *)runScript:(NSString *)source arguments:(NSArray *)arguments timeout:(NSTimeInterval)timeout error:(NSError **)error {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/osascript"];
    task.arguments = [@[@"-e",source] arrayByAddingObjectsFromArray:arguments];
    NSPipe *output = [NSPipe pipe], *errors = [NSPipe pipe];
    task.standardInput = NSFileHandle.fileHandleWithNullDevice;
    task.standardOutput = output;
    task.standardError = errors;
    dispatch_group_t work = dispatch_group_create();
    dispatch_group_enter(work);
    task.terminationHandler = ^(__unused NSTask *unused) { dispatch_group_leave(work); };
    if (![task launchAndReturnError:error]) { dispatch_group_leave(work); return nil; }
    __block NSData *text, *details;
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY,0);
    dispatch_group_async(work,queue,^{ text = [output.fileHandleForReading readDataToEndOfFile]; });
    dispatch_group_async(work,queue,^{ details = [errors.fileHandleForReading readDataToEndOfFile]; });
    if (dispatch_group_wait(work,dispatch_time(DISPATCH_TIME_NOW,(int64_t)(timeout*NSEC_PER_SEC)))) {
        if (task.running) [task terminate];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),queue,^{
            if (task.running) kill(task.processIdentifier,SIGKILL);
        });
        RKTerminalFail(error,@"iTerm2 did not confirm the request before it timed out. Check iTerm2 before trying again.");
        return nil;
    }
    if (task.terminationStatus != 0) {
        NSString *message = [[[NSString alloc] initWithData:details encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        RKTerminalFail(error, message.length ? message : @"Could not reach iTerm2.");
        return nil;
    }
    return [[NSString alloc] initWithData:text encoding:NSUTF8StringEncoding] ?: @"";
}

// The command string handed to iTerm2. Exposed to tests with a substitute ssh.
+ (NSString *)terminalCommandForMetadata:(NSDictionary *)metadata target:(NSString *)target destination:(NSString *)destination ssh:(NSString *)ssh error:(NSError **)error {
    if (![metadata isKindOfClass:NSDictionary.class]) { RKTerminalFail(error, @"The remote host returned invalid attach metadata."); return nil; }
    NSString *binary = metadata[@"binary"], *session = metadata[@"sessionID"];
    if (!RKOnly(binary, @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._+-") || ![binary hasPrefix:@"/"] || [binary containsString:@"/../"] || [binary hasSuffix:@"/.."]) {
        RKTerminalFail(error, @"The remote host returned an invalid tmux path."); return nil;
    }
    NSString *socket = metadata[@"socketPath"];
    if (socket && (![socket isKindOfClass:NSString.class] || ![socket hasPrefix:@"/"] ||
        [socket rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound)) {
        RKTerminalFail(error, @"The remote host returned an invalid tmux socket path."); return nil;
    }
    if (!RKPrefixedNumber(session, @"$")) { RKTerminalFail(error, @"The remote host returned an invalid tmux session."); return nil; }
    NSArray *parts = [target isKindOfClass:NSString.class] ? [target componentsSeparatedByString:@"|"] : nil;
    if (parts.count != 3 || !RKPrefixedNumber(parts[0], @"%") || !RKOnly(parts[1], @"0123456789-") || !RKUUIDToken(parts[2])) {
        RKTerminalFail(error, @"Only a managed agent can be opened on the remote host."); return nil;
    }
    NSString *hostChars = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@:._-[]";
    if (!RKOnly(destination, hostChars) || [destination hasPrefix:@"-"]) { RKTerminalFail(error, @"The SSH destination is invalid."); return nil; }
    NSMutableArray *remote = [NSMutableArray arrayWithObjects:@"exec /bin/sh -c", RKQuote(RKRemoteGuard), @"fauxrk", nil];
    for (NSString *arg in @[binary, socket ?: @"", session, parts[0], parts[1], parts[2]]) [remote addObject:RKQuote(arg)];
    NSArray *local = @[@"/bin/sh", @"-c", RKQuote(RKLocalLauncher), @"fauxrk", RKQuote([[[remote componentsJoinedByString:@" "] dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0]), RKQuote(destination), RKQuote(ssh)];
    return [local componentsJoinedByString:@" "];
}

+ (BOOL)openAttachment:(NSDictionary *)metadata target:(NSString *)target destination:(NSString *)destination error:(NSError **)error {
    NSString *command = [self terminalCommandForMetadata:metadata target:target destination:destination ssh:@"/usr/bin/ssh" error:error];
    if (!command) return NO;
    NSString *script = @"on run argv\ntell application id \"com.googlecode.iterm2\"\nactivate\ncreate window with default profile command (item 1 of argv)\nend tell\nend run";
    return [self runScript:script arguments:@[command] timeout:30 error:error] != nil;
}

// Always start a fresh observation when possible. A late answer from an
// earlier snapshot is never reused for notification suppression.
+ (NSString *)boundedFocusProbe:(NSString *(^)(void))query {
    static RKFocusProbe *inFlight;
    RKFocusProbe *probe;
    @synchronized (RKRemoteTerminal.class) {
        if (!inFlight) {
            probe = [RKFocusProbe new];
            probe.finished = dispatch_group_create();
            dispatch_group_enter(probe.finished);
            inFlight = probe;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
                probe.token = RKUUIDToken(query()) ?: @"";
                @synchronized (RKRemoteTerminal.class) { inFlight = nil; }
                dispatch_group_leave(probe.finished);
            });
        } else probe = inFlight;
    }
    return dispatch_group_wait(probe.finished,dispatch_time(DISPATCH_TIME_NOW,150*NSEC_PER_MSEC)) ? @"" : probe.token;
}

+ (NSString *)focusedToken {
    return [self boundedFocusProbe:^NSString *{
        if (![NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier isEqual:RKITermBundle]) return @"";
        // Polling must never put an Apple Events consent dialog on screen.
        NSAppleEventDescriptor *app = [NSAppleEventDescriptor descriptorWithBundleIdentifier:RKITermBundle];
        if (AEDeterminePermissionToAutomateTarget(app.aeDesc,typeWildCard,typeWildCard,false) != noErr) return @"";
        NSString *script = @"with timeout of 1 second\ntell application id \"com.googlecode.iterm2\" to get id of current session of current window\nend timeout";
        NSString *output = [self runScript:script arguments:@[] timeout:2 error:nil];
        return [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }];
}

+ (NSString *)focusedPaneForToken:(NSString *)token core:(RKCore *)core {
    if (!RKUUIDToken(token) || !core) return nil;
    NSString *clients = [core tmux:@[@"list-clients", @"-F", @"#{client_pid}\t#{pane_id}\t#{client_flags}"] error:nil];
    NSString *registered = [core tmux:@[@"show-options", @"-s"] error:nil];
    if (!clients.length || !registered.length) return nil;
    NSMutableDictionary<NSString *, NSString *> *tokens = [NSMutableDictionary dictionary];
    for (NSString *line in [registered componentsSeparatedByString:@"\n"]) {
        NSArray *f = [line componentsSeparatedByString:@" "];
        if (f.count == 2 && [f[0] hasPrefix:@"@rk_iterm_"] && RKUUIDToken(f[1])) tokens[[f[0] substringFromIndex:10]] = f[1];
    }
    for (NSString *line in [clients componentsSeparatedByString:@"\n"]) {
        NSArray *f = [line componentsSeparatedByString:@"\t"];
        if (f.count != 3 || !RKOnly(f[0], @"0123456789") || !RKPrefixedNumber(f[1], @"%") || [f[2] containsString:@"control-mode"]) continue;
        NSString *registeredToken = tokens[f[0]];
        if (registeredToken && [registeredToken caseInsensitiveCompare:token] == NSOrderedSame) return f[1];
    }
    return nil;
}
@end
