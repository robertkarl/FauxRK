#import "RKPaneOrder.h"

static NSInteger priority(NSDictionary *pane, NSTimeInterval now) {
    if ([pane[@"focused"] boolValue]) return 2;
    NSString *command = [pane[@"command"] lowercaseString];
    BOOL agent = [command containsString:@"claude"] || [command containsString:@"codex"] || [command isEqual:@"pi"];
    return agent && now - [pane[@"activity"] doubleValue] < 30 ? 1 : 0;
}

@implementation RKPaneOrder {
    NSArray<NSString *> *_order;
}
- (NSArray<NSDictionary *> *)arrange:(NSArray<NSDictionary *> *)panes resort:(BOOL)resort {
    NSMutableDictionary *remaining = [NSMutableDictionary dictionary];
    for (NSDictionary *pane in panes) remaining[pane[@"id"]] = pane;
    NSMutableArray *ordered = [NSMutableArray array];
    if (!resort) {
        for (NSString *paneID in _order) {
            if (remaining[paneID]) [ordered addObject:remaining[paneID]];
            [remaining removeObjectForKey:paneID];
        }
    }
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSArray *arrivals = [remaining.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult rank = [@(priority(b, now)) compare:@(priority(a, now))];
        if (rank != NSOrderedSame) return rank;
        NSComparisonResult activity = [@([b[@"activity"] doubleValue]) compare:@([a[@"activity"] doubleValue])];
        return activity != NSOrderedSame ? activity : [a[@"id"] localizedStandardCompare:b[@"id"]];
    }];
    [ordered addObjectsFromArray:arrivals];
    _order = [ordered valueForKey:@"id"];
    return ordered;
}
@end
