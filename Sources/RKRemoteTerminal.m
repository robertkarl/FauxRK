#import "RKRemoteTerminal.h"
#import "RKCore.h"
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

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

static NSString *RKRun(NSString *binary, NSArray *args, NSError **error) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:binary];
    task.arguments = args;
    NSPipe *output = [NSPipe pipe], *errors = [NSPipe pipe];
    task.standardInput = NSFileHandle.fileHandleWithNullDevice;
    task.standardOutput = output;
    task.standardError = errors;
    if (![task launchAndReturnError:error]) return nil;
    __block NSData *diagnostic;
    dispatch_group_t io = dispatch_group_create();
    dispatch_group_async(io, dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{ diagnostic = [errors.fileHandleForReading readDataToEndOfFile]; });
    NSData *data = [output.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    dispatch_group_wait(io, DISPATCH_TIME_FOREVER);
    if (task.terminationStatus != 0) {
        NSString *message = [[[NSString alloc] initWithData:diagnostic encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        RKTerminalFail(error, message.length ? message : @"Could not open iTerm2.");
        return nil;
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

// Runs on the remote host as: /bin/sh -c GUARD fauxrk TMUX SESSION PANE GENERATION UUID TOKEN.
// The state check repeats the helper's managed-lifetime validation at attach time. The
// registration names the client by $$, which exec preserves as the tmux client PID.
// Every attach first drops registrations whose client PID is no longer attached.
static NSString *const RKRemoteGuard =
    @"fail() { printf \"FauxRK: %s\\n\" \"$1\" >&2; printf \"Press Return to close.\" >&2; read -r _ || true; exit 1; }\n"
    "tmux=$1 sid=$2 pane=$3 gen=$4 uuid=$5 token=${6-}\n"
    "[ -x \"$tmux\" ] || fail \"tmux is not installed at $tmux.\"\n"
    "state=$(\"$tmux\" display-message -p -t \"$pane\" \"#{session_id}|#{pid}-#{start_time}-#{pane_pid}|#{@rk_id}|#{@rk_pane}|#{@rk_managed}\" 2>/dev/null) || fail \"This agent is no longer running.\"\n"
    "[ \"$state\" = \"$sid|$gen|$uuid|$pane|1\" ] || fail \"This agent changed. Refresh FauxRK and open it again.\"\n"
    "case $token in *[!0-9A-Fa-f-]*) token= ;; [0-9A-Fa-f]*-*-*-*-*) ;; *) token= ;; esac\n"
    "live=\" $(\"$tmux\" list-clients -F \"#{client_pid}\" 2>/dev/null | tr \"\\n\" \" \") \"\n"
    "\"$tmux\" show-options -s 2>/dev/null | while read -r name _; do\n"
    "  case $name in @rk_iterm_*) case $live in *\" ${name#@rk_iterm_} \"*) ;; *) \"$tmux\" set-option -su \"$name\" ;; esac ;; esac\n"
    "done\n"
    "[ -z \"$token\" ] || \"$tmux\" set-option -s \"@rk_iterm_$$\" \"$token\" 2>/dev/null || true\n"
    "exec \"$tmux\" attach-session -t \"$sid\"\n";

// Runs locally in the new iTerm2 session as: /bin/sh -c LAUNCHER fauxrk BASE64(REMOTE) DESTINATION SSH.
// iTerm2 splits its command string itself, so every argument is a single-quoted run with no
// embedded quotes. The session ID is expanded here and reduced to UUID characters before ssh.
static NSString *const RKLocalLauncher =
    @"r=$(printf %s \"$1\" | /usr/bin/base64 -D) || exit 1\n"
    "t=${ITERM_SESSION_ID#*:}\n"
    "case $t in \"\"|*[!0-9A-Fa-f-]*) t=- ;; esac\n"
    "exec \"$3\" -t -- \"$2\" \"$r $t\"\n";

@implementation RKRemoteTerminal

// The command string handed to iTerm2. Exposed to tests with a substitute ssh.
+ (NSString *)terminalCommandForMetadata:(NSDictionary *)metadata target:(NSString *)target destination:(NSString *)destination ssh:(NSString *)ssh error:(NSError **)error {
    if (![metadata isKindOfClass:NSDictionary.class]) { RKTerminalFail(error, @"The remote host returned invalid attach metadata."); return nil; }
    NSString *binary = metadata[@"binary"], *session = metadata[@"sessionID"];
    if (!RKOnly(binary, @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._+-") || ![binary hasPrefix:@"/"] || [binary containsString:@"/../"] || [binary hasSuffix:@"/.."]) {
        RKTerminalFail(error, @"The remote host returned an invalid tmux path."); return nil;
    }
    if (!RKPrefixedNumber(session, @"$")) { RKTerminalFail(error, @"The remote host returned an invalid tmux session."); return nil; }
    NSArray *parts = [target isKindOfClass:NSString.class] ? [target componentsSeparatedByString:@"|"] : nil;
    if (parts.count != 3 || !RKPrefixedNumber(parts[0], @"%") || !RKOnly(parts[1], @"0123456789-") || !RKUUIDToken(parts[2])) {
        RKTerminalFail(error, @"Only a managed agent can be opened on the remote host."); return nil;
    }
    NSString *hostChars = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@:._-[]";
    if (!RKOnly(destination, hostChars) || [destination hasPrefix:@"-"]) { RKTerminalFail(error, @"The SSH destination is invalid."); return nil; }
    NSMutableArray *remote = [NSMutableArray arrayWithObjects:@"exec /bin/sh -c", RKQuote(RKRemoteGuard), @"fauxrk", nil];
    for (NSString *arg in @[binary, session, parts[0], parts[1], parts[2]]) [remote addObject:RKQuote(arg)];
    NSArray *local = @[@"/bin/sh", @"-c", RKQuote(RKLocalLauncher), @"fauxrk", RKQuote([[[remote componentsJoinedByString:@" "] dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0]), RKQuote(destination), RKQuote(ssh)];
    return [local componentsJoinedByString:@" "];
}

+ (BOOL)openAttachment:(NSDictionary *)metadata target:(NSString *)target destination:(NSString *)destination error:(NSError **)error {
    NSString *command = [self terminalCommandForMetadata:metadata target:target destination:destination ssh:@"/usr/bin/ssh" error:error];
    if (!command) return NO;
    NSString *script = @"on run argv\ntell application id \"com.googlecode.iterm2\"\nactivate\ncreate window with default profile command (item 1 of argv)\nend tell\nend run";
    return RKRun(@"/usr/bin/osascript", @[@"-e", script, command], error) != nil;
}

+ (NSString *)focusedToken {
    if (![NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier isEqual:RKITermBundle]) return @"";
    // Polling must never put an Apple Events consent dialog on screen.
    NSAppleEventDescriptor *app = [NSAppleEventDescriptor descriptorWithBundleIdentifier:RKITermBundle];
    if (AEDeterminePermissionToAutomateTarget(app.aeDesc, typeWildCard, typeWildCard, false) != noErr) return @"";
    NSString *script = @"with timeout of 1 second\ntell application id \"com.googlecode.iterm2\" to get id of current session of current window\nend timeout";
    NSString *output = [RKRun(@"/usr/bin/osascript", @[@"-e", script], nil) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return RKUUIDToken(output) ?: @"";
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
