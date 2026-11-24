#import "../Sources/RKCore.h"

@interface Fixture : RKCore
@property(copy) NSString *page;
@property(copy) NSString *sent;
@property NSUInteger reads;
@end
@implementation Fixture
- (NSString *)screen:(NSString *)pid error:(NSError **)error { self.reads++; return self.page; }
- (BOOL)sendText:(NSString *)text toPane:(NSString *)pid error:(NSError **)error { self.sent = text; return YES; }
- (BOOL)sendKey:(NSString *)key toPane:(NSString *)pid error:(NSError **)error { self.sent = key; return YES; }
@end

#define Check(cond, text) do { if (!(cond)) { NSLog(@"FAIL: %s", text); return 1; } } while(0)
int main(int argc, const char **argv) { @autoreleasepool {
    NSString *provider = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"off";
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{@"RKHelperProvider":provider} forName:NSArgumentDomain];
    NSDictionary *pane = @{@"id":@"%1", @"managed":@YES, @"rkID":NSUUID.UUID.UUIDString, @"command":@"codex", @"session":@"fixture"};
    NSArray *panes = @[pane, @{@"id":@"%2",@"managed":@NO}];
    Fixture *core = [Fixture new];
    RKMonitor *m = [[RKMonitor alloc] initWithCore:(RKCore *)core];
    core.page = @"The scratchpad is ready.\nInstall the missing dependency and retry? [y/N]";
    if (![provider isEqual:@"off"]) {
        NSString *summary = [m preview:@"%1" error:NULL];
        if ([summary hasPrefix:@"Screen excerpt"]) NSLog(@"%@", summary);
        Check(summary.length && ![summary hasPrefix:@"Screen excerpt"], "live helper did not return a summary");
        NSLog(@"%@ helper, synthetic preview: %@", provider, summary);
        return 0;
    }
    NSDictionary *row = [m update:panes][@"%1"];
    Check(core.reads == 1, "read an uncaptured pane");
    Check([row[@"kind"] isEqual:@"input"] && [row[@"choices"] count] == 2, "startup yes/no blocker missing");
    [m markRead:@"%1" fingerprint:row[@"fingerprint"]];
    Check([m update:panes].count == 1, "viewing dismissed blocker");
    NSDictionary *original = row;
    core.page = @"Delete the second release? [y/N]";
    Check(![m answer:original[@"choices"][0] pane:@"%1" fingerprint:original[@"fingerprint"] error:NULL], "stale choice was accepted");
    row = [m update:panes][@"%1"];
    Check(![original[@"fingerprint"] isEqual:row[@"fingerprint"]], "different prompts shared an identity");
    Check((![m answer:@{@"key":@"y",@"label":@"Injected"} pane:@"%1" fingerprint:row[@"fingerprint"] error:NULL]), "unoffered action accepted");
    Check([m answer:row[@"choices"][1] pane:@"%1" fingerprint:row[@"fingerprint"] error:NULL] && [core.sent isEqual:@"n"], "no action sent");
    Check(![m answer:row[@"choices"][0] pane:@"%1" fingerprint:row[@"fingerprint"] error:NULL], "double click sent twice");
    m = [[RKMonitor alloc] initWithCore:(RKCore *)core];
    row = [m update:panes][@"%1"];
    Check([row[@"responseSent"] boolValue] && ![m answer:row[@"choices"][0] pane:@"%1" fingerprint:row[@"fingerprint"] error:NULL], "reconnect repeated a just-sent answer");
    core.page = @"Which folder should I use?";
    row = [m update:panes][@"%1"];
    NSDictionary *draft = @{@"label":@"Reply", @"text":@"The demo project", @"draft":@YES};
    Check([row[@"kind"] isEqual:@"input"] && [row[@"choices"] count] == 0, "missing open question");
    core.page = @"Which user should own the files?";
    Check(![m answer:draft pane:@"%1" fingerprint:row[@"fingerprint"] error:NULL], "stale draft was accepted");
    row = [m update:panes][@"%1"];
    Check([m answer:draft pane:@"%1" fingerprint:row[@"fingerprint"] error:NULL], "edited draft rejected");
    core.page = @"Should I run tests?\n› 1. Yes, proceed (y)\n  2. No (n)\nPress enter to confirm or esc to cancel";
    row = [m update:panes][@"%1"];
    Check([row[@"choices"] count] == 2 && [row[@"choices"][0][@"keys"] isEqual:@[@"Enter"]], "missing terminal menu choices");
    core.page = @"☐ Fixture\nWhich fixture label?\n❯ 1. Alpha\n     Use the Alpha fixture label.\n  2. Beta\n     Use the Beta fixture label.\n  3. Type something.\n─────────────────\n  4. Chat about this\nEnter to select · ↑/↓ to navigate · Esc to cancel";
    row = [m update:panes][@"%1"];
    NSArray *betaKeys = @[@"Down", @"Enter"];
    Check([row[@"kind"] isEqual:@"input"] && [row[@"choices"] count] == 4 &&
          [row[@"question"] isEqual:@"Which fixture label?"] && [row[@"choices"][1][@"keys"] isEqual:betaKeys], "Claude described question menu failed");
    core.page = @"⏺ RK-LIVE-CHOSEN Beta\n✻ Churned for 4s · done 7:12 AM\n─────────────────\n❯ \n─────────────────\n[Fable 5.2] 📁 fable\n░░░░░░░░░░ 3% | $0.81 | ⏱️ 3m 3s\n⏵⏵ auto mode on (shift+tab to cycle) · ← 2 agents";
    row = [m update:panes][@"%1"];
    Check([row[@"kind"] isEqual:@"complete"] && [row[@"summary"] containsString:@"RK-LIVE-CHOSEN Beta"], "Claude custom status line hid completion");
    core.page = @"Select Model and Effort\n  1. GPT-6.2-Sol\n› 2. GPT-6.2-Astra (current)\n  3. GPT-6-Luna\n↓\nenter select · esc back";
    row = [m update:panes][@"%1"];
    Check([row[@"kind"] isEqual:@"input"] && [row[@"choices"] count] == 3 &&
          [row[@"choices"][2][@"keys"] isEqual:betaKeys], "Codex model picker lost its options");
    core.page = @"Update available\n› 1. Update now\n2. Skip\n3. Skip until next version\nenter continue · esc skip";
    row = [m update:panes][@"%1"];
    Check([row[@"choices"] count] == 3 && [row[@"choices"][1][@"keys"] isEqual:betaKeys], "Codex update picker was not recognized");
    core.sent = nil;
    Check(![m steer:@"/model" toTarget:@"%1" error:NULL] && !core.sent, "ordinary steer selected update default");
    core.page = @"This may be a new renderer.\nenter select · esc back";
    Check(![m steer:@"input" toTarget:@"%1" error:NULL] && !core.sent, "ordinary steer selected an unparsed menu");
    core.page = @"• Working (esc to interrupt)\n› Ask Codex to do anything";
    Check([m steer:@"keep going" toTarget:@"%1" error:NULL] && [core.sent isEqual:@"keep going"], "working agent steer was refused");
    core.page = @"Running the tests\nWorking (esc to interrupt)";
    Check([m update:panes].count == 0, "resumed agent still marked blocked");
    core.page = @"• All 82 tests passed.\n Worked for 6s • 7:04 AM\n› Ask Codex to do anything\n GPT-6.2-Astra medium · /tmp · weekly 60% left · Context 3% used\n ← for agents · ? for shortcuts    ⚠ 3 warnings · f2 to view";
    row = [m update:panes][@"%1"];
    Check([row[@"kind"] isEqual:@"complete"] && [row[@"summary"] containsString:@"82 tests"], "turn completion missing");
    [m markRead:@"%1" fingerprint:row[@"fingerprint"]];
    Check([m update:panes].count == 0, "read completion still visible");
    m = [[RKMonitor alloc] initWithCore:(RKCore *)core];
    Check([m update:panes].count == 0, "read state lost on restart");
    core.page = @"Working (esc to interrupt)";
    [m update:panes];
    core.page = @"• All 82 tests passed.\n Worked for 6s • 7:04 AM\n› Ask Codex to do anything\n GPT-6.2-Astra medium · /tmp · weekly 60% left · Context 3% used\n ← for agents · ? for shortcuts    ⚠ 3 warnings · f2 to view";
    Check([m update:panes].count == 1, "later identical turn suppressed");
    core.page = @"Pick one of the deployment branches to continue.";
    [m update:panes];
    [NSThread sleepForTimeInterval:1.5];
    Check([[m update:panes][@"%1"][@"kind"] isEqual:@"maybe"], "unrecognized stationary blocker hidden");
    core.page = @"⠈⠙⠛⠿⠿⠿⠛⠉\n› Ask Codex to do anything\n? for shortcuts";
    [m update:panes];
    [NSThread sleepForTimeInterval:1.5];
    Check(![m update:panes].count, "Codex logo triggered handoff");
    NSLog(@"Monitor fixtures passed");
    return 0;
}}
