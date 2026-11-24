#import "RKPaneOrder.h"

static NSDictionary *pane(NSString *ident, NSString *cmd, BOOL focus, double activity) {
    return @{@"id":ident, @"command":cmd, @"focused":@(focus), @"activity":@(activity)};
}
int main(void) {
    @autoreleasepool {
        RKPaneOrder *order = [RKPaneOrder new];
        double now = NSDate.date.timeIntervalSince1970;
        NSDictionary *a = pane(@"%1", @"zsh", YES, now-60);
        NSDictionary *b = pane(@"%2", @"claude.exe", NO, now-2);
        NSDictionary *c = pane(@"%3", @"zsh", NO, now);
        NSArray *ranked = [order arrange:@[c,b,a] resort:NO];
        NSCAssert(([ranked isEqual:@[a,b,c]]), @"Focused shell then active agent then remaining shell");
        c = pane(@"%3", @"zsh", YES, now);
        a = pane(@"%1", @"zsh", NO, now-60);
        NSDictionary *d = pane(@"%4", @"codex", NO, now);
        ranked = [order arrange:@[a,b,c,d] resort:NO];
        NSCAssert(([ranked isEqual:@[a,b,c,d]]), @"Polling must preserve row positions");
        ranked = [order arrange:@[a,b,c,d] resort:YES];
        NSCAssert(([ranked isEqual:@[c,d,b,a]]), @"Explicit sort uses current activity");
    }
    return 0;
}
