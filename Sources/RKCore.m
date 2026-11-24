#import "RKCore.h"
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <unistd.h>

static NSError *RKFailure(NSString *message) {
    return [NSError errorWithDomain:@"RK.Tmux" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

static id RKFail(NSError **error, NSString *message) {
    if (error) *error = RKFailure(message);
    return nil;
}

static NSString *trim(NSString *s) {
    return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *shellQuote(NSString *s) {
    return [NSString stringWithFormat:@"'%@'", [s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

static BOOL numericID(NSString *s, unichar prefix) {
    if (s.length < 2 || [s characterAtIndex:0] != prefix) return NO;
    for (NSUInteger i = 1; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c < '0' || c > '9') return NO;
    }
    return YES;
}

// Directory names and terminal-controlled titles may contain tabs/newlines.
// #{n:...} is the UTF-8 byte length, so even control characters round-trip.
static NSString *recordFormat(NSArray<NSString *> *variables) {
    NSMutableString *format = [NSMutableString string];
    for (NSString *v in variables) [format appendFormat:@"#{n:%@}:#{%@}", v, v];
    return format;
}

static NSArray *readRecords(NSString *output, NSUInteger width) {
    NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
    const unsigned char *bytes = data.bytes;
    NSUInteger i = 0;
    NSMutableArray *records = [NSMutableArray array];
    while (i < data.length) {
        NSMutableArray *fields = [NSMutableArray arrayWithCapacity:width];
        for (NSUInteger j = 0; j < width; j++) {
            NSUInteger start = i, size = 0;
            while (i < data.length && bytes[i] >= '0' && bytes[i] <= '9') {
                if (size > (NSUIntegerMax - 9) / 10) return nil;
                size = size * 10 + bytes[i++] - '0';
            }
            if (i == start || i == data.length || bytes[i++] != ':' || size > data.length-i) return nil;
            NSString *field = [[NSString alloc] initWithBytes:bytes+i length:size encoding:NSUTF8StringEncoding];
            if (!field) return nil;
            [fields addObject:field];
            i += size;
        }
        [records addObject:fields];
        if (i < data.length && bytes[i++] != '\n') return nil;
    }
    return records;
}

static NSString *paneNumber(NSString *target) {
    return [target componentsSeparatedByString:@"|"].firstObject;
}

static NSString *generationFormat(void) {
    return @"#{pid}-#{start_time}-#{pane_pid}";
}

static NSString *liveTarget(NSString *pid, NSString *generation, NSString *uuid) {
    return [@[pid,generation,uuid ?: @""] componentsJoinedByString:@"|"];
}

static BOOL RKRefuse(NSError **error, NSString *message) {
    RKFail(error, message);
    return NO;
}

static NSString *runTask(NSString *binary, NSArray<NSString *> *args, NSData *input, NSError **error) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:binary];
    task.arguments = args;
    NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
    [env removeObjectsForKeys:@[@"TMUX", @"TMUX_PANE"]];
    task.environment = env;
    NSPipe *output = [NSPipe pipe], *errors = [NSPipe pipe];
    NSPipe *in = input ? [NSPipe pipe] : nil;
    task.standardInput = in ?: NSFileHandle.fileHandleWithNullDevice;
    task.standardOutput = output;
    task.standardError = errors;
    dispatch_semaphore_t exited = dispatch_semaphore_create(0);
    task.terminationHandler = ^(__unused NSTask *finished) { dispatch_semaphore_signal(exited); };
    if (![task launchAndReturnError:error]) return nil;
    __block NSData *diagnostic;
    dispatch_group_t io = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    dispatch_group_async(io, queue, ^{ diagnostic = [errors.fileHandleForReading readDataToEndOfFile]; });
    if (in) {
        dispatch_group_async(io, queue, ^{
            [in.fileHandleForWriting writeData:input error:nil];
            [in.fileHandleForWriting closeFile];
        });
    }
    NSData *result = [output.fileHandleForReading readDataToEndOfFile];
    dispatch_semaphore_wait(exited, DISPATCH_TIME_FOREVER);
    dispatch_group_wait(io, DISPATCH_TIME_FOREVER);
    if (task.terminationStatus != 0) {
        NSString *message = trim([[NSString alloc] initWithData:diagnostic encoding:NSUTF8StringEncoding] ?: @"");
        return RKFail(error, message.length ? message : [NSString stringWithFormat:@"%@ exited with status %d.", binary.lastPathComponent, task.terminationStatus]);
    }
    return [[NSString alloc] initWithData:result encoding:NSUTF8StringEncoding] ?: @"";
}

static NSDictionary *presets(void) {
    return @{
        @"Astra Medium": @[@"codex", @"--remote", @"unix://", @"-m", @"gpt-6.2-astra", @"-c", @"model_reasoning_effort=medium"],
        @"Luna Medium": @[@"codex", @"--remote", @"unix://", @"-m", @"gpt-6-luna", @"-c", @"model_reasoning_effort=medium"],
        @"Fable Medium": @[@"claude", @"--model", @"fable", @"--effort", @"medium"],
        @"Opus": @[@"claude", @"--model", @"opus"]
    };
}

static NSString *safeName(NSString *source) {
    NSMutableArray *parts = [NSMutableArray array];
    NSCharacterSet *letters = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789"];
    for (NSString *part in [source.lowercaseString componentsSeparatedByCharactersInSet:letters.invertedSet]) {
        if (part.length) [parts addObject:part];
    }
    NSString *slug = [parts componentsJoinedByString:@"-"];
    if (!slug.length) slug = @"agent";
    return [slug substringToIndex:MIN(slug.length, 35)];
}

@implementation RKCore

- (NSString *)binary {
    for (NSString *path in @[@"/opt/homebrew/bin/tmux", @"/usr/local/bin/tmux", @"/opt/local/bin/tmux"]) {
        if ([NSFileManager.defaultManager isExecutableFileAtPath:path]) return path;
    }
    return @"/opt/homebrew/bin/tmux";
}

- (NSArray *)socketArguments {
    NSString *socket = NSProcessInfo.processInfo.environment[@"RK_TMUX_SOCKET"];
    if (!socket.length) return @[];
    return @[socket.isAbsolutePath ? @"-S" : @"-L", socket];
}

- (NSString *)tmux:(NSArray *)args input:(NSData *)input error:(NSError **)error {
    return runTask(self.binary, [self.socketArguments arrayByAddingObjectsFromArray:args], input, error);
}

- (NSString *)tmux:(NSArray *)args error:(NSError **)error {
    return [self tmux:args input:nil error:error];
}

- (NSString *)focusedPane {
    NSString *front = NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier;
    if (![@[@"com.googlecode.iterm2", @"com.apple.Terminal", @"com.mitchellh.ghostty", @"net.kovidgoyal.kitty", @"org.alacritty"] containsObject:front ?: @""]) return nil;
    NSString *output = [self tmux:@[@"list-clients", @"-F", @"#{pane_id}\t#{client_tty}\t#{client_flags}\t#{client_activity}\t#{focus-events}"] error:nil];
    NSMutableArray *clients = [NSMutableArray array];
    for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
        NSArray *fields = [line componentsSeparatedByString:@"\t"];
        if (fields.count == 5 && ![fields[2] containsString:@"control-mode"]) [clients addObject:fields];
    }
    if (!clients.count) return nil;
    // Read the front window's exact TTY when Automation is already authorized.
    // Polling by itself must never put an Apple Events consent dialog on screen.
    if ([front isEqual:@"com.googlecode.iterm2"] || [front isEqual:@"com.apple.Terminal"]) {
        NSAppleEventDescriptor *target = [NSAppleEventDescriptor descriptorWithBundleIdentifier:front];
        if (AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false) == noErr) {
            NSString *script = [front isEqual:@"com.googlecode.iterm2"] ?
                @"with timeout of 1 second\ntell application id \"com.googlecode.iterm2\" to get tty of current session of current window\nend timeout" :
                @"with timeout of 1 second\ntell application id \"com.apple.Terminal\" to get tty of selected tab of front window\nend timeout";
            NSString *tty = trim(runTask(@"/usr/bin/osascript", @[@"-e",script], nil, nil));
            if (tty.length) {
                for (NSArray *fields in clients) if ([fields[1] isEqual:tty]) return fields[0];
                return nil;
            }
        }
    }
    // Without terminal automation, prefer focus events, then actual recent typing.
    NSArray *winner = nil;
    for (NSArray *fields in clients) {
        BOOL reportedFocus = [fields[4] boolValue] && [[fields[2] componentsSeparatedByString:@","] containsObject:@"focused"];
        BOOL recentInput = NSDate.date.timeIntervalSince1970 - [fields[3] doubleValue] <= 3;
        if ((reportedFocus || recentInput) && (!winner || [fields[3] doubleValue] > [winner[3] doubleValue])) winner = fields;
    }
    return winner.firstObject;
}

- (NSArray<NSDictionary *> *)panes:(NSError **)error {
    NSArray *fields = @[@"pane_id",@"session_name",@"window_name",@"pane_current_command",@"pane_current_path",
        @"pane_title",@"window_activity",@"@rk_managed",@"@rk_pane",@"@rk_id",@"@rk_preset",
        @"session_attached",@"session_id",@"window_id",@"pane_pid",@"pid",@"start_time"];
    NSString *format = recordFormat(fields);
    NSError *listError;
    NSString *output = [self tmux:@[@"-N", @"list-panes", @"-a", @"-F", format] error:&listError];
    if (!output) {
        NSString *msg = listError.localizedDescription;
        if ([msg containsString:@"no server running"] || ([msg containsString:@"No such file or directory"] && [msg containsString:@"connecting to"])) return @[];
        if (error) *error = listError;
        return nil;
    }
    NSMutableArray *rows = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSString *focus = [self focusedPane];
    NSArray *records = readRecords(output, fields.count);
    if (!records) return RKFail(error, @"Could not decode the tmux inventory.");
    for (NSArray *f in records) {
        if (!numericID(f[0], '%') || [seen containsObject:f[0]]) continue;
        NSString *gen = [@[f[15],f[16],f[14]] componentsJoinedByString:@"-"];
        [seen addObject:f[0]];
        BOOL managed = [f[7] isEqual:@"1"] && [f[8] isEqual:f[0]] && [f[9] length];
        [rows addObject:@{@"id":f[0], @"session":f[1], @"window":f[2],
            @"command":f[3], @"path":f[4], @"title":f[5],
            @"activity":f[6], @"managed":@(managed), @"focused":@([f[0] isEqual:focus]), @"attached":@([f[11] integerValue] > 0),
            @"target":liveTarget(f[0],gen,managed ? f[9] : nil), @"sessionID":f[12], @"windowID":f[13], @"panePID":f[14], @"rkID":managed ? f[9] : @"", @"preset":managed ? f[10] : @""}];
    }
    return rows;
}

- (NSDictionary *)metadata:(NSString *)target managed:(BOOL)required error:(NSError **)error {
    NSString *pid = paneNumber(target);
    if (!numericID(pid, '%')) return RKFail(error, @"Invalid tmux pane identifier.");
    NSArray *fields = @[@"session_id",@"@rk_managed",@"@rk_pane",@"pane_current_command",@"window_name",
        @"pane_current_path",@"@rk_id",@"session_windows",@"window_panes",@"pid",@"start_time",@"pane_pid"];
    NSString *line = [self tmux:@[@"display-message",@"-p",@"-t",pid,recordFormat(fields)] error:error];
    if (!line) return nil;
    NSArray *f = [readRecords(line,fields.count) firstObject];
    if (!f || !numericID(f[0], '$')) return RKFail(error, @"This pane is no longer available.");
    NSString *gen = [@[f[9],f[10],f[11]] componentsJoinedByString:@"-"];
    BOOL managed = [f[1] isEqual:@"1"] && [f[2] isEqual:pid];
    NSString *live = liveTarget(pid, gen, managed ? f[6] : nil);
    if (![target isEqual:pid] && ![target isEqual:live]) return RKFail(error, @"This pane has changed. Refresh the card before acting.");
    if (required && !managed) return RKFail(error, @"This pane is no longer managed by RK.");
    return @{@"target":live, @"single":@([f[7] isEqual:@"1"] && [f[8] isEqual:@"1"]), @"sessionID":f[0], @"managed":@(managed), @"command":f[3], @"window":f[4], @"path":f[5]};
}

// The condition and its command execute in the tmux server's command queue.
// The data in command is fixed syntax, numeric IDs or generated UUIDs.
- (NSString *)checkedCommand:(NSString *)command target:(NSString *)target single:(BOOL)single error:(NSError **)error {
    NSArray *parts = [target componentsSeparatedByString:@"|"];
    if (parts.count != 3 || !numericID(parts[0], '%')) return RKFail(error,@"Invalid pane identity.");
    NSString *generation = parts[1], *uuid = parts[2], *pid = parts[0];
    NSCharacterSet *numbers = [NSCharacterSet characterSetWithCharactersInString:@"0123456789-"];
    if (!generation.length || [generation rangeOfCharacterFromSet:numbers.invertedSet].location != NSNotFound)
        return RKFail(error,@"Invalid pane generation.");
    NSString *ownership;
    if (uuid.length) {
        if (![[NSUUID alloc] initWithUUIDString:uuid]) return RKFail(error, @"Invalid ownership marker.");
        ownership = [NSString stringWithFormat:@"#{&&:#{==:#{@rk_id},%@},#{&&:#{==:#{@rk_pane},%@},#{==:#{@rk_managed},1}}}",uuid,pid];
    } else {
        ownership = [NSString stringWithFormat:@"#{!=:#{@rk_pane},%@}",pid];
    }
    NSString *check = [NSString stringWithFormat:@"#{&&:#{==:%@,%@},%@}",generationFormat(),generation,ownership];
    if (single) check = [NSString stringWithFormat:@"#{&&:%@,#{&&:#{==:#{session_windows},1},#{==:#{window_panes},1}}}",check];
    NSString *stale = NSUUID.UUID.UUIDString;
    NSString *otherwise = [@"display-message -p " stringByAppendingString:stale];
    NSString *result = [self tmux:@[@"if-shell",@"-F",@"-t",pid,check,command,otherwise] error:error];
    if ([trim(result) isEqual:stale]) return RKFail(error,@"This pane or session changed. Refresh the card before acting.");
    return result;
}

- (BOOL)apply:(NSString *)command meta:(NSDictionary *)meta single:(BOOL)single error:(NSError **)error {
    return [self checkedCommand:command target:meta[@"target"] single:single error:error] != nil;
}

- (NSString *)spawnPreset:(NSString *)preset directory:(NSString *)directory prompt:(NSString *)prompt error:(NSError **)error {
    NSArray *args = presets()[preset];
    if (!args) return RKFail(error, @"Unknown agent preset.");
    BOOL isDir = NO;
    NSString *cwd = directory.stringByExpandingTildeInPath.stringByStandardizingPath;
    if (!cwd.isAbsolutePath || ![NSFileManager.defaultManager fileExistsAtPath:cwd isDirectory:&isDir] || !isDir) return RKFail(error, @"Choose an existing project directory.");
    NSString *uuid = NSUUID.UUID.UUIDString.lowercaseString;
    NSString *name = [NSString stringWithFormat:@"rk-%@-%@",safeName(cwd.lastPathComponent),[uuid substringToIndex:8]];
    // A login shell loads the user's fnm/CLI paths. The prompt is a positional
    // argument, including newlines and quotes; it is never evaluated as code.
    NSMutableArray *argv = [args mutableCopy];
    if (prompt.length) [argv addObjectsFromArray:@[@"--",prompt]];
    // Codex CLI 0.171 otherwise switches to embedded mode for -c, losing
    // access to the local daemon's shell executor. Its start command is idempotent.
    NSString *entry = [args.firstObject isEqual:@"codex"] ?
        @"codex app-server daemon start >/dev/null && exec \"$@\"" : @"exec \"$@\"";
    NSMutableString *launch = [NSMutableString stringWithFormat:@"exec /bin/zsh -lic %@ rk",shellQuote(entry)];
    for (NSString *arg in argv) [launch appendFormat:@" %@",shellQuote(arg)];
    NSString *target = [NSString stringWithFormat:@"=%@:",name];
    NSString *tmuxCwd = [[cwd stringByReplacingOccurrencesOfString:@"#" withString:@"##"] stringByAppendingString:@"/."];
    NSArray *cmd = @[@"new-session",@"-d",@"-P",@"-F",@"#{pane_id}",@"-s",name,@"-n",safeName(preset),@"-c",tmuxCwd,@"-x",@"112",@"-y",@"38",launch,
        @";",@"set-option",@"-t",target,@"@rk_managed",@"1",
        @";",@"set-option",@"-F",@"-t",target,@"@rk_pane",@"#{pane_id}",
        @";",@"set-option",@"-t",target,@"@rk_id",uuid,
        @";",@"set-option",@"-t",target,@"@rk_preset",preset];
    NSString *result = [self tmux:cmd error:error];
    if (!result) return nil;
    NSString *pid = trim(result);
    if (!numericID(pid,'%')) return RKFail(error,@"tmux did not return the new pane identifier.");
    return pid;
}

- (BOOL)capture:(NSString *)targetID error:(NSError **)error {
    @synchronized (self) {
        NSString *pid = paneNumber(targetID);
        NSDictionary *meta = [self metadata:targetID managed:NO error:error];
        if (!meta) return NO;
        if ([meta[@"managed"] boolValue]) return YES;
        NSString *uuid = NSUUID.UUID.UUIDString.lowercaseString;
        NSString *name = [NSString stringWithFormat:@"rk-%@-%@",safeName([meta[@"path"] lastPathComponent]),[uuid substringToIndex:8]];
        NSString *target = [NSString stringWithFormat:@"=%@:",name];
        // Break/join always requires somewhere to move. The staging pane expires
        // independently if the app is closed between these two requests.
        NSString *newID = [self tmux:@[@"new-session",@"-d",@"-P",@"-F",@"#{pane_id}",@"-s",name,@"-n",safeName(meta[@"window"]),@"-x",@"112",@"-y",@"38",@"/bin/sleep 30"] error:error];
        if (!newID) return NO;
        NSString *staging = trim(newID);
        if (!numericID(staging, '%')) return RKRefuse(error,@"Invalid staging pane.");
        NSString *sourceGeneration = [meta[@"target"] componentsSeparatedByString:@"|"][1];
        NSString *check = [NSString stringWithFormat:@"#{&&:#{==:%@,%@},#{!=:#{@rk_pane},%@}}",generationFormat(),sourceGeneration,pid];
        NSString *move = [NSString stringWithFormat:@"join-pane -d -s %@ -t %@",pid,staging];
        NSArray *cmd = @[@"set-option",@"-t",target,@"@rk_managed",@"1",
            @";",@"set-option",@"-t",target,@"@rk_pane",pid,
            @";",@"set-option",@"-t",target,@"@rk_id",uuid,
            @";",@"if-shell",@"-F",@"-t",pid,check,move,@"display-message -p RK_TARGET_CHANGED",
            @";",@"kill-pane",@"-t",staging];
        NSString *result = [self tmux:cmd error:error];
        if (!result) return NO; // Only our expiring placeholder can remain.
        if ([trim(result) isEqual:@"RK_TARGET_CHANGED"]) return RKRefuse(error,@"This pane changed before RK could capture it.");
        return YES;
    }
}

- (BOOL)sendText:(NSString *)text toPane:(NSString *)targetID error:(NSError **)error {
    @synchronized (self) {
        NSString *pid = paneNumber(targetID);
        NSDictionary *m = [self metadata:targetID managed:YES error:error];
        if (!m) return NO;
        if (!text.length) return RKRefuse(error,@"Enter a message first.");
        NSString *cmd = [m[@"command"] lastPathComponent];
        if ([@[@"zsh",@"bash",@"sh",@"fish",@"dash",@"tcsh",@"ksh",@"login"] containsObject:[cmd stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-"]]]) {
            return RKRefuse(error,@"This pane is at a shell prompt. Open it in a new window to start the agent.");
        }
        // Bracketed paste prevents multiline prompts being split into multiple
        // terminal submissions. Keep user text out of tmux command syntax.
        NSString *buffer = [@"rk-" stringByAppendingString:NSUUID.UUID.UUIDString];
        NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
        if (![self tmux:@[@"load-buffer",@"-b",buffer,@"-"] input:data error:error]) return NO;
        if (![self apply:[NSString stringWithFormat:@"paste-buffer -dpr -b %@ -t %@",buffer,pid] meta:m single:NO error:error]) {
            [self tmux:@[@"delete-buffer",@"-b",buffer] error:nil];
            return NO;
        }
        // Interactive clients classify very rapid typing (including Return) as a
        // paste burst. Send Return in a distinct input cycle.
        usleep(85000);
        return [self apply:[NSString stringWithFormat:@"send-keys -t %@ Enter",pid] meta:m single:NO error:error];
    }
}

- (BOOL)sendKeys:(NSArray<NSString *> *)keys toPane:(NSString *)targetID error:(NSError **)error {
    if (!keys.count || keys.count > 16) return RKRefuse(error,@"Invalid number of prompt keys.");
    for (NSString *key in keys) {
        if (![key isKindOfClass:NSString.class]) return RKRefuse(error,@"Unsupported prompt key.");
        BOOL printable = key.length == 1 && [@"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" containsString:key];
        if (!printable && ![@[@"Enter",@"Space",@"Up",@"Down",@"Left",@"Right",@"Tab",@"BTab",@"Escape",@"C-c"] containsObject:key]) return RKRefuse(error,@"Unsupported prompt key.");
    }
    @synchronized (self) {
        NSString *pid = paneNumber(targetID);
        NSDictionary *m = [self metadata:targetID managed:YES error:error];
        if (!m) return NO;
        NSString *sequence = [keys componentsJoinedByString:@" "];
        return [self apply:[NSString stringWithFormat:@"send-keys -t %@ %@",pid,sequence] meta:m single:NO error:error];
    }
}

- (BOOL)sendKey:(NSString *)key toPane:(NSString *)targetID error:(NSError **)error {
    return [self sendKeys:key ? @[key] : @[] toPane:targetID error:error];
}

- (NSString *)screen:(NSString *)targetID error:(NSError **)error {
    NSString *pid = paneNumber(targetID);
    if (!numericID(pid, '%')) return RKFail(error,@"Invalid tmux pane identifier.");
    if ([targetID isEqual:pid]) return [self tmux:@[@"capture-pane",@"-p",@"-J",@"-t",pid] error:error];
    NSString *command = [NSString stringWithFormat:@"capture-pane -p -J -t %@",pid];
    return [self checkedCommand:command target:targetID single:NO error:error];
}

- (BOOL)interrupt:(NSString *)pid error:(NSError **)error {
    return [self sendKey:@"C-c" toPane:pid error:error];
}

- (BOOL)end:(NSString *)targetID error:(NSError **)error {
    @synchronized (self) {
        NSString *pid = paneNumber(targetID);
        NSDictionary *meta = [self metadata:targetID managed:YES error:error];
        if (!meta) return NO;
        if (![meta[@"single"] boolValue]) return RKRefuse(error,@"This session now contains additional windows or panes. Close those before ending this RK session.");
        NSString *live = meta[@"target"];
        for (NSUInteger n = 0; n < 2; n++) {
            if (![self apply:[NSString stringWithFormat:@"send-keys -t %@ C-c",pid] meta:meta single:YES error:error]) return ![self metadata:live managed:NO error:nil];
            usleep(160000);
            if (![self metadata:live managed:NO error:nil]) return YES;
        }
        // A one-pane window/session disappears with the pane. If the user added
        // siblings in tmux, ending the card preserves those unrelated processes.
        return [self apply:[NSString stringWithFormat:@"kill-pane -t %@",pid] meta:meta single:YES error:error] || ![self metadata:live managed:NO error:nil];
    }
}

- (NSDictionary *)attachMetadata:(NSString *)target error:(NSError **)error {
    NSDictionary *meta = [self metadata:target managed:YES error:error];
    if (!meta) return nil;
    return @{@"binary":self.binary, @"sessionID":meta[@"sessionID"]};
}

- (BOOL)openWindow:(NSString *)target error:(NSError **)error {
    NSDictionary *meta = [self attachMetadata:target error:error];
    if (!meta) return NO;
    NSMutableArray *argv = [NSMutableArray arrayWithObject:meta[@"binary"]];
    [argv addObjectsFromArray:self.socketArguments];
    [argv addObjectsFromArray:@[@"attach-session",@"-t",meta[@"sessionID"]]];
    NSMutableArray *quoted = [NSMutableArray array];
    for (NSString *arg in argv) [quoted addObject:shellQuote(arg)];
    NSString *command = [@"/bin/sh -c " stringByAppendingString:shellQuote([@"exec " stringByAppendingString:[quoted componentsJoinedByString:@" "]])];
    NSString *script = @"on run argv\ntell application id \"com.googlecode.iterm2\"\nactivate\ncreate window with default profile command (item 1 of argv)\nend tell\nend run";
    return runTask(@"/usr/bin/osascript", @[@"-e",script,command], nil, error) != nil;
}
@end
