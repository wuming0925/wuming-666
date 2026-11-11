//
//  RuleEngine.m — 抖音评论区规则引擎
//  蓝字关键词 + 地区过滤，逻辑与 Android 版同源（已单测通过）
//

#import "RuleEngine.h"

static NSString *const kConfigPath   = @"/var/mobile/Library/Preferences/com.aweme.comment.plist";
static NSString *const kConfigPath2  = @"/var/jb/var/mobile/Library/Preferences/com.aweme.comment.plist";
static NSString *const kDefaultColor = @"#FF2B7FFF";

@interface ACRuleEngine ()
@property (nonatomic, strong) NSArray<NSString *> *keywords;
@property (nonatomic, strong) NSArray<NSString *> *regions;
@property (nonatomic, strong) NSArray<NSString *> *dropRules;
@property (nonatomic, strong) UIColor *highlightColor;
@property (nonatomic, assign) ACRuleMode mode;
@property (nonatomic, assign) BOOL hideLocation;
@property (nonatomic, assign) BOOL sortByRegion;
/** 地名别名：简写 → 全称片段（"内蒙" 的评论里常写 "内蒙古"） */
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *regionAlias;
@end

@implementation ACRuleEngine

+ (instancetype)shared {
    static ACRuleEngine *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [ACRuleEngine new]; });
    return inst;
}

- (instancetype)init {
    if (self = [super init]) {
        _regionAlias = @{
            @"北京": @"北京市", @"上海": @"上海市", @"天津": @"天津市", @"重庆": @"重庆市",
            @"内蒙": @"内蒙古", @"广西": @"壮族",   @"新疆": @"维吾尔", @"西藏": @"自治区",
            @"香港": @"香港",   @"澳门": @"澳门",   @"台湾": @"台湾",
        };
        [self reload];
    }
    return self;
}

- (UIColor *)colorFromHex:(NSString *)hex {
    if (!hex.length) return [UIColor blueColor];
    NSString *s = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (s.length == 6) s = [@"FF" stringByAppendingString:s];
    unsigned long long v = 0;
    NSScanner *sc = [NSScanner scannerWithString:s];
    [sc scanHexLongLong:&v];
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0
                           green:((v >> 8) & 0xFF) / 255.0
                            blue:(v & 0xFF) / 255.0
                           alpha:((v >> 24) & 0xFF) / 255.0];
}

- (void)reload {
    NSDictionary *cfg = nil;
    for (NSString *p in @[kConfigPath, kConfigPath2]) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if (d) { cfg = d; break; }
    }

    // 默认值：和截图里抖音场景对得上的一组词
    NSArray *kw = cfg[@"keywords"] ?: @[@"抽奖", @"福利", @"包邮", @"免费送"];
    NSArray *rg = cfg[@"regions"]  ?: @[];
    NSArray *dr = cfg[@"drop"]     ?: @[];
    NSString *hex = cfg[@"color"]  ?: kDefaultColor;

    self.keywords      = kw;
    self.regions       = rg;
    self.dropRules     = dr;
    self.highlightColor = [self colorFromHex:hex];
    self.mode          = cfg[@"whole_text"] ? [cfg[@"whole_text"] integerValue] : ACRuleModeWholeText;
    self.hideLocation  = cfg[@"hide_location"] ? [cfg[@"hide_location"] boolValue] : YES;
    self.sortByRegion  = cfg[@"sort_by_region"] ? [cfg[@"sort_by_region"] boolValue] : NO;
}

- (NSUInteger)countHits:(NSString *)text {
    if (!text.length) return 0;
    NSUInteger n = 0;
    for (NSString *k in self.keywords) {
        if (k.length && [text containsString:k]) n++;
    }
    return n;
}

- (BOOL)containsKeyword:(NSString *)text {
    return [self countHits:text] > 0;
}

- (BOOL)locationMatches:(NSString *)location {
    if (!location.length) return NO;
    for (NSString *r in self.regions) {
        if (!r.length) continue;
        if ([location containsString:r]) return YES;
        NSString *alias = self.regionAlias[r];
        if (alias && [location containsString:alias]) return YES;
    }
    return NO;
}

- (BOOL)acceptText:(NSString *)text uid:(NSString *)uid avatar:(NSString *)avatar location:(NSString *)location {
    // 1. 垃圾/广告规则
    for (NSString *d in self.dropRules) {
        if (!d.length) continue;
        if ((text && [text containsString:d]) || (uid && [uid containsString:d])) return NO;
    }
    // 2. 地区白名单（没配就不过滤）
    if (self.regions.count && location.length && ![self locationMatches:location]) return NO;
    return YES;
}

- (NSString *)stripLocation:(NSString *)text {
    if (!text.length) return text;
    NSArray *pats = @[@"IP属地", @"ip属地", @"IP 属地"];
    NSRange hit = NSMakeRange(NSNotFound, 0);
    for (NSString *p in pats) {
        NSRange r = [text rangeOfString:p];
        if (r.location != NSNotFound) { hit = r; break; }
    }
    if (hit.location == NSNotFound || hit.location == 0) return text;

    // 往前吃掉空白与分隔符（"·" "|" "-"）
    NSUInteger cut = hit.location;
    NSCharacterSet *sep = [NSCharacterSet characterSetWithCharactersInString:@" \t·|-\u00b7"];
    while (cut > 0) {
        unichar c = [text characterAtIndex:cut - 1];
        if ([sep characterIsMember:c]) { cut--; continue; }
        break;
    }
    if (cut == 0) return text;
    return [text substringToIndex:cut];
}

- (NSAttributedString *)highlightAttributed:(NSAttributedString *)input {
    if (!input.length) return input;
    NSString *plain = input.string;
    NSUInteger hits = [self countHits:plain];
    if (hits == 0) return input;

    NSMutableAttributedString *m = [input mutableCopy];

    if (self.mode == ACRuleModeWholeText) {
        [m addAttribute:NSForegroundColorAttributeName value:self.highlightColor
                   range:NSMakeRange(0, m.length)];
        return m;
    }

    // 只染关键词
    for (NSString *k in self.keywords) {
        if (!k.length) continue;
        NSRange search = NSMakeRange(0, plain.length);
        while (search.location < plain.length) {
            NSRange r = [plain rangeOfString:k options:0 range:search];
            if (r.location == NSNotFound) break;
            [m addAttribute:NSForegroundColorAttributeName value:self.highlightColor range:r];
            NSUInteger next = r.location + MAX(r.length, 1);
            if (next >= plain.length) break;
            search = NSMakeRange(next, plain.length - next);
        }
    }
    return m;
}

@end
