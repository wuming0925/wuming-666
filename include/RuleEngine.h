//
//  RuleEngine.h — 词表与规则（与 Android 版逻辑同源，纯 Foundation，无平台依赖）
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ACRuleMode) {
    ACRuleModeWholeText = 1,   // 命中关键词整条染色
    ACRuleModeKeywordOnly = 0, // 只染关键词
};

@interface ACRuleEngine : NSObject

@property (nonatomic, strong, readonly) NSArray<NSString *> *keywords;
@property (nonatomic, strong, readonly) NSArray<NSString *> *regions;
@property (nonatomic, strong, readonly) NSArray<NSString *> *dropRules;
@property (nonatomic, assign, readonly) UIColor *highlightColor;
@property (nonatomic, assign, readonly) ACRuleMode mode;
@property (nonatomic, assign, readonly) BOOL hideLocation;
@property (nonatomic, assign, readonly) BOOL sortByRegion;

+ (instancetype)shared;

- (void)reload;

/** 命中关键词的个数（重复出现只算一次，用于判断"是否要整条染色"） */
- (NSUInteger)countHits:(nullable NSString *)text;

/** 是否命中关键词 */
- (BOOL)containsKeyword:(nullable NSString *)text;

/** 评论是否应保留（定位过滤） */
- (BOOL)acceptText:(nullable NSString *)text
                uid:(nullable NSString *)uid
             avatar:(nullable NSString *)avatar
           location:(nullable NSString *)location;

/** location 是否命中地区白名单 */
- (BOOL)locationMatches:(nullable NSString *)location;

/** 去掉 "IP属地：xx" 尾巴；正文以属地开头时不改 */
- (nullable NSString *)stripLocation:(nullable NSString *)text;

/** 给 attributedString 打上颜色，返回新对象（输入不可变，不修改原对象） */
- (nullable NSAttributedString *)highlightAttributed:(nullable NSAttributedString *)input;

@end

NS_ASSUME_NONNULL_END
