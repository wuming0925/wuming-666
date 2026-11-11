//
//  Tweak.m — 抖音评论区 dylib
//
//  功能：
//    [1] 蓝字 —— 评论区文本命中关键词时染色
//    [2] 探测 —— 扫描疑似评论模型类，把类名/字段写到文件
//    [3] 定位 —— 拿到 ipLocation 字段后过滤（首版仅探测，不删）
//
//  注入：LCsign 之类的工具会把它加进主二进制 LC_LOAD_DYLIB，
//        所以不依赖 CydiaSubstrate，用 constructor + method_setImplementation。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "RuleEngine.h"
#import "Probe.h"

#define AC_LOG(fmt, ...) NSLog(@"[aweme_comment] " fmt, ##__VA_ARGS__)

#pragma mark - 探测

NSArray<NSString *> *ACProbeFilePaths(void) {
    NSString *doc = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSMutableArray *a = [NSMutableArray array];
    if (doc) [a addObject:[doc stringByAppendingPathComponent:@"acprobe.txt"]];
    [a addObject:@"/tmp/acprobe.txt"];
    [a addObject:@"/var/mobile/Documents/acprobe.txt"];
    return a;
}

static NSMutableString *gProbe;
static BOOL gProbing;

/** 判断一个类是否像"评论模型"：类名含 Comment，且有多个 NSString 字段 */
static void ACInspectClass(Class cls, NSMutableString *out) {
    const char *name = class_getName(cls);
    if (!name || !strcasestr(name, "comment")) return;

    unsigned ivarCount = 0;
    Ivar *ivars = class_copyIvarList(cls, &ivarCount);
    if (!ivars) return;
    if (ivarCount == 0) { free(ivars); return; }

    NSMutableArray *strFields = [NSMutableArray array];
    for (unsigned i = 0; i < ivarCount; i++) {
        const char *tn = ivar_getTypeEncoding(ivars[i]);
        const char *in = ivar_getName(ivars[i]);
        if (!tn || !in) continue;
        if (strstr(tn, "@\"NSString\"")) {
            [strFields addObject:[NSString stringWithUTF8String:in]];
        }
    }
    free(ivars);

    if (strFields.count < 2) return;   // 至少两个字符串字段才像模型

    [out appendFormat:@"\n[CLASS] %s  (ivars=%u, strings=%lu)\n",
                      name, ivarCount, (unsigned long) strFields.count];
    for (NSString *f in strFields) [out appendFormat:@"    %@\n", f];
}

void ACRunProbe(void) {
    if (gProbing) return;
    gProbing = YES;

    NSMutableString *out = [NSMutableString string];
    [out appendString:@"=== aweme_comment probe ===\n"];
    [out appendFormat:@"date   : %@\n", [NSDate date]];
    [out appendFormat:@"bundle : %@\n", [[NSBundle mainBundle] bundleIdentifier]];
    [out appendFormat:@"ver    : %@\n", [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"]];
    [out appendFormat:@"ios    : %@\n", [[UIDevice currentDevice] systemVersion]];

    unsigned count = 0;
    Class *classes = objc_copyClassList(&count);
    NSUInteger matched = 0;
    if (classes) {
        for (unsigned i = 0; i < count; i++) {
            @autoreleasepool {
                Class c = classes[i];
                if (!c) continue;
                const char *n = class_getName(c);
                if (n && strcasestr(n, "comment")) {
                    matched++;
                    ACInspectClass(c, out);
                }
            }
        }
        free(classes);
    }
    [out appendFormat:@"\n=== summary: %u classes, %lu matched ===\n", count, (unsigned long) matched];

    gProbe = out;

    NSData *data = [out dataUsingEncoding:NSUTF8StringEncoding];
    for (NSString *p in ACProbeFilePaths()) {
        NSString *dir = [p stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];
        BOOL ok = [data writeToFile:p atomically:YES];
        AC_LOG(@"probe -> %@ : %@", p, ok ? @"OK" : @"FAIL");
    }
    AC_LOG(@"%@", out);
    gProbing = NO;
}

NSString *ACReadProbeText(void) {
    if (gProbe.length) return gProbe;
    for (NSString *p in ACProbeFilePaths()) {
        NSString *t = [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:NULL];
        if (t.length) return t;
    }
    return nil;
}

#pragma mark - 蓝字 hook

// 原始实现（只在 UILabel 上取一次，其余类复用）
static IMP g_origSetAttributed;
static IMP g_origSetText;

static void ac_setAttributedText(id self, SEL _cmd, NSAttributedString *text) {
    NSAttributedString *out = [[ACRuleEngine shared] highlightAttributed:text];
    if (g_origSetAttributed) {
        ((void (*)(id, SEL, NSAttributedString *)) g_origSetAttributed)(self, _cmd, out ?: text);
    }
}

static void ac_setText(id self, SEL _cmd, NSString *text) {
    if ([[ACRuleEngine shared] containsKeyword:text] &&
        [self respondsToSelector:@selector(setAttributedText:)]) {
        NSAttributedString *base = [[NSAttributedString alloc] initWithString:text];
        NSAttributedString *hi = [[ACRuleEngine shared] highlightAttributed:base];
        if (hi && hi != base) {
            ((void (*)(id, SEL, NSAttributedString *)) objc_msgSend)(self, @selector(setAttributedText:), hi);
            return;
        }
    }
    if (g_origSetText) ((void (*)(id, SEL, NSString *)) g_origSetText)(self, _cmd, text);
}

static void ACHookClass(Class cls, SEL sel, IMP newImp, IMP *origOut) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    if (origOut && !*origOut) *origOut = method_getImplementation(m);
    method_setImplementation(m, newImp);
}

static void ACInstallHooks(void) {
    Class uiLabel  = objc_getClass("UILabel");
    Class uiTV     = objc_getClass("UITextView");
    Class yyLabel  = objc_getClass("YYLabel");

    ACHookClass(uiLabel, @selector(setAttributedText:), (IMP) ac_setAttributedText, &g_origSetAttributed);
    ACHookClass(uiLabel, @selector(setText:),           (IMP) ac_setText,           &g_origSetText);
    ACHookClass(uiTV,    @selector(setAttributedText:), (IMP) ac_setAttributedText, NULL);
    ACHookClass(uiTV,    @selector(setText:),           (IMP) ac_setText,           NULL);
    ACHookClass(yyLabel, @selector(setAttributedText:), (IMP) ac_setAttributedText, NULL);

    AC_LOG(@"hooks: UILabel=%p UITextView=%p YYLabel=%p", uiLabel, uiTV, yyLabel);
}

#pragma mark - 三指长按弹窗（文件读不到时的兜底）

static void ACInstallLongPress(void) {
    UIWindow *win = UIApplication.sharedApplication.keyWindow;
    if (!win) {
        // 窗口还没准备好，稍后再来
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ ACInstallLongPress(); });
        return;
    }
    UILongPressGestureRecognizer *lp =
        [[UILongPressGestureRecognizer alloc] initWithTarget:[ACProbeShower sharedProxy]
                                                      action:@selector(handleLongPress:)];
    lp.minimumPressDuration = 1.5;
    lp.numberOfTouchesRequired = 3;
    [win addGestureRecognizer:lp];
    AC_LOG(@"long-press installed (3 fingers / 1.5s)");
}

#pragma mark - 启动

__attribute__((constructor))
static void ACInit(void) {
    @autoreleasepool {
        AC_LOG(@"loaded pid=%d", getpid());

        // 延迟装 hook，避开和别的插件抢顺序
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            ACInstallHooks();
            ACInstallLongPress();
        });

        // 后台跑探测，不阻塞启动
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            ACRunProbe();
        });
    }
}
