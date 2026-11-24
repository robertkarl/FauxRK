#import "RKCore.h"

NSString *RKString(id value);
NSString *RKTrim(NSString *s);
NSString *RKShort(NSString *s, NSUInteger limit);
NSString *RKLine(id value, NSUInteger limit);
NSError *RKMonitorError(NSString *message);
BOOL RKMatches(NSString *s, NSString *pattern);
NSArray<NSString *> *RKLines(NSString *screen);
NSArray<NSString *> *RKContent(NSArray<NSString *> *all);
BOOL RKBusy(NSArray *lines);
BOOL RKWelcome(NSArray *body, NSArray *screen);
NSDictionary *RKAttentionRow(NSString *kind, NSString *question, NSArray *choices);
NSDictionary *RKClassify(NSArray<NSString *> *all, NSDictionary *pane);
NSString *RKProvider(void);
NSString *RKLocalModel(void);
NSDictionary *RKInfer(RKCore *core, NSString *screen, NSString *provider, NSError **error);
