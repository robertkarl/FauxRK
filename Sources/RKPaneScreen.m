#import "RKMonitorInternal.h"

BOOL RKMatches(NSString *s, NSString *pattern) {
    return [s rangeOfString:pattern options:NSRegularExpressionSearch|NSCaseInsensitiveSearch].location != NSNotFound;
}
NSArray<NSString *> *RKLines(NSString *screen) {
    NSMutableArray *lines = [NSMutableArray new];
    for (NSString *s in [screen componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *trimmed = RKTrim(s);
        if (trimmed.length) [lines addObject:trimmed];
    }
    return lines;
}
static BOOL RKChrome(NSString *s) {
    return RKMatches(s, @"^[─━═╭╮╰╯│┌┐└┘┆ ─-]+$|^[⠀-⣿ ]+$|^← for agents|^Worked for [0-9]|^[✻✶✳✽✢✦✧].+ for [0-9]|^\\? for shortcuts|^[⏵▶›▸ ]*(bypass permissions|accept edits|auto mode|plan mode) on|context (left|remaining)$|^gpt-[^ ]+.*[·•]|^[0-9]+% context|^shift\\+tab to|^(press )?(enter to (select|confirm)|esc to cancel)");
}
static BOOL RKPrompt(NSString *s) {
    return RKMatches(s, @"^[❯›>](\\s|$)");
}
NSArray<NSString *> *RKContent(NSArray<NSString *> *all) {
    NSMutableArray *body = [NSMutableArray new];
    for (NSUInteger i = 0; i < all.count; i++) {
        NSString *s = all[i];
        if (!RKChrome(s)) [body addObject:s];
        // Claude permits arbitrary user-written status lines. Its current input
        // field is enclosed by dividers and followed by these out-of-band lines.
        if (i && i + 1 < all.count && RKPrompt(s) && RKMatches(all[i-1], @"^[─━]{8,}$") &&
            RKMatches(all[i+1], @"^[─━]{8,}$") && all.count - i < 8) break;
    }
    return body;
}
BOOL RKBusy(NSArray *lines) {
    NSInteger i = (NSInteger)lines.count - 1;
    if (i >= 0 && RKPrompt(lines[i])) i--;
    if (i < 0) return NO;
    return RKMatches(lines[i], @"(?:esc to interrupt|esc to steer|ctrl[-+]c to interrupt)|^[✻✶✳✽✢✦✧⏺◐⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏].*(?:…|\\.\\.\\.)");
}
BOOL RKWelcome(NSArray *body, NSArray *screen) {
    if (!body.count || !RKPrompt(body.lastObject)) return NO;
    if (body.count == 1) return YES;
    NSString *s = [body componentsJoinedByString:@"\n"];
    BOOL hasReply = RKMatches(s, @"(?:^|\n)[•●⏺] ");
    if (hasReply) return NO;
    NSString *all = [screen componentsJoinedByString:@"\n"];
    return RKMatches(all, @"[⠀-⣿]{4}|Welcome to|Claude Code v|OpenAI Codex|Claude Code [v0-9]|Try .+/");
}
NSDictionary *RKAttentionRow(NSString *kind, NSString *question, NSArray *choices) {
    NSString *summary = RKLine(question, 210);
    return @{@"kind":kind, @"question":RKShort(question, 1500), @"summary":summary, @"choices":choices, @"choiceSource": choices.count ? @"terminal" : @"none"};
}
static NSArray *RKMenuChoices(NSArray<NSString *> *labels, NSInteger selected) {
    NSMutableArray *choices = [NSMutableArray new];
    for (NSUInteger index = 0; index < labels.count; index++) {
        NSInteger delta = (NSInteger)index - selected;
        NSMutableArray *keys = [NSMutableArray new];
        for (NSInteger step = 0; step < labs(delta); step++) [keys addObject:delta < 0 ? @"Up" : @"Down"];
        [keys addObject:@"Enter"];
        [choices addObject:@{@"label":RKShort(labels[index], 140), @"keys":keys}];
    }
    return choices;
}
NSDictionary *RKClassify(NSArray<NSString *> *all, NSDictionary *pane) {
    if (!all.count) return nil;
    BOOL navigableMenu = RKMatches(all.lastObject, @"^enter (?:to )?(?:select|continue|confirm).*(?:navigate|esc)");
    NSUInteger depth = navigableMenu ? all.count : MIN(all.count, 16);
    NSArray *tail = [all subarrayWithRange:NSMakeRange(all.count - depth, depth)];
    // The most recent checkbox heading marks the active question, even when
    // option descriptions fill more than a dozen lines of the screen.
    if (navigableMenu) {
        for (NSInteger i = (NSInteger)tail.count - 1; i >= 0; i--) {
            if (RKMatches(tail[i], @"^[☐☑] ")) {
                tail = [tail subarrayWithRange:NSMakeRange(i + 1, tail.count - i - 1)];
                break;
            }
        }
    }
    NSArray *lines = RKContent(tail);
    if (!lines.count) return nil;
    NSString *last = lines.lastObject;

    // Only interpret a literal response menu near the bottom. Never promote an example in scrollback.
    NSString *yn = @"(?:\\[|\\()(?:y\\s*/\\s*n|yes\\s*/\\s*no|n\\s*/\\s*y)(?:\\]|\\))\\s*[:?]?\\s*$";
    if (RKMatches(last, yn)) {
        NSString *question = last;
        if (last.length < 12 && lines.count > 1) question = [NSString stringWithFormat:@"%@ %@", lines[lines.count - 2], last];
        return RKAttentionRow(@"input", question, @[@{@"label":@"Yes", @"text":@"y"}, @{@"label":@"No", @"text":@"n"}]);
    }
    if (RKMatches(tail.lastObject, @"^Enter to confirm") && lines.count >= 2) {
        NSArray *trustOptions = [lines subarrayWithRange:NSMakeRange(lines.count - 2, 2)];
        NSMutableArray *labels = [NSMutableArray new];
        NSInteger selectedIndex = -1;
        for (NSString *line in trustOptions) {
            BOOL selected = RKPrompt(line);
            NSString *label = selected ? RKTrim([line substringFromIndex:1]) : line;
            if (selected) selectedIndex = (NSInteger)labels.count;
            [labels addObject:label];
        }
        if (selectedIndex >= 0 && [labels containsObject:@"No, exit"] && [labels containsObject:@"Yes, I trust this folder"]) {
            NSString *folder = RKString(pane[@"path"]);
            NSString *question = folder.length ? [NSString stringWithFormat:@"Trust this folder? %@", folder] : @"Trust this folder?";
            return RKAttentionRow(@"input", question, RKMenuChoices(labels, selectedIndex));
        }
    }
    // A selected numbered item distinguishes interactive menus from lists printed by an agent.
    NSRegularExpression *item = [NSRegularExpression regularExpressionWithPattern:@"^([❯›>→]?)\\s*([1-9])[.)]\\s+(.+)$" options:0 error:NULL];
    NSMutableArray *choices = [NSMutableArray new];
    NSInteger selected = -1;
    NSMutableArray *context = [NSMutableArray new];
    for (NSString *s in lines) {
        NSTextCheckingResult *m = [item firstMatchInString:s options:0 range:NSMakeRange(0,s.length)];
        if (m) {
            if ([m rangeAtIndex:1].length) selected = (NSInteger)choices.count;
            NSString *label = [s substringWithRange:[m rangeAtIndex:3]];
            [choices addObject:@{@"label":RKShort(label,140)}];
        } else if (!choices.count && !RKPrompt(s)) {
            [context addObject:s];
        } else if (choices.count && !navigableMenu && !RKMatches(s, @"enter to (select|confirm)|esc to cancel|tab to|↑|↓")) {
            // A new prompt/output after the menu means it is no longer current.
            [choices removeAllObjects]; selected = -1; [context removeAllObjects]; [context addObject:s];
        }
    }
    if (selected >= 0 && choices.count > 1) {
        // Menus in both supported CLIs offer arrow selection and Enter. A
        // displayed numeral can be an ordinal, not an immediately usable key.
        NSUInteger count = MIN(4, context.count);
        NSString *question = count ? [[context subarrayWithRange:NSMakeRange(context.count - count, count)] componentsJoinedByString:@"\n"] : @"Choose an option";
        return RKAttentionRow(@"input", question, RKMenuChoices([choices valueForKey:@"label"], selected));
    }

    if (RKBusy(lines) || RKWelcome(lines, tail)) return nil;

    BOOL prompt = RKPrompt(last);
    NSString *prior = lines.count > 1 ? lines[lines.count - 2] : @"";
    NSString *message = prompt ? prior : last;
    NSString *command = [RKString(pane[@"command"]) lastPathComponent].lowercaseString;
    BOOL shell = [@[@"zsh", @"-zsh", @"bash", @"-bash", @"fish", @"sh", @"login"] containsObject:command];
    if (shell && !prompt && RKMatches(last, @"[%$#❯➜]\\s*$")) return nil;
    if (!message.length) return nil;
    if (RKMatches(message, @"\\?\\s*$|awaiting (your |user )?(approval|input)|waiting for (your |user )?(approval|input)|press (enter|return) to (continue|proceed)|enter (your |a )?(choice|selection|password|passphrase)[: ]*$"))
        return RKAttentionRow(@"input", message, @[]);
    if (prompt && !shell && !RKMatches(prior, @"Welcome to|Claude Code v|OpenAI Codex|Tip:|What's new|/help for|^model:|^directory:"))
        return RKAttentionRow(@"complete", message, @[]);
    return nil;
}

