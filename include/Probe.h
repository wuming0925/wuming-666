#ifndef AC_PROBE_H
#define AC_PROBE_H

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/** 立即执行一次类扫描探测, 结果写入三个路径并打日志 */
void ACRunProbe(void);

/** 读取上次探测结果 (按写入优先级倒序查找), 找不到返回 nil */
NSString *ACReadProbeText(void);

/** 三指长按弹窗 (单例, 只用来当手势 target) */
@interface ACProbeShower : NSObject
+ (instancetype)sharedProxy;
- (void)handleLongPress:(UILongPressGestureRecognizer *)g;
@end

#endif
