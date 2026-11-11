//  ACProbeShower.m — 三指长按弹出探测结果（没有文件访问权限时的兜底通道）
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Probe.h"

@implementation ACProbeShower

+ (instancetype)sharedProxy {
    static ACProbeShower *p;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [ACProbeShower new]; });
    return p;
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;

    NSString *txt = ACReadProbeText();
    if (!txt.length) txt = @"(探测数据为空，稍后再试)";

    // 太长的话只显示前 3000 字
    if (txt.length > 3000) txt = [[txt substringToIndex:3000] stringByAppendingString:@"\n...(已截断)"];

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"aweme_comment 探测"
                                                              message:txt
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIPasteboard.generalPasteboard.string = txt;
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];

    UIWindow *win = UIApplication.sharedApplication.keyWindow;
    [win.rootViewController presentViewController:ac animated:YES completion:nil];
}

@end
