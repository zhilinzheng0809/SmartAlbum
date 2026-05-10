#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SAPhotoClassification : NSObject

@property (nonatomic, copy) NSString *localIdentifier;
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, copy) NSArray<NSString *> *tags;
@property (nonatomic, strong) NSDate *analyzedAt;

/**
 * @brief 使用基础字段初始化照片标签结果。
 * @param localIdentifier 相册资源唯一标识。
 * @param summary 照片摘要描述。
 * @param tags 照片标签数组。
 * @param analyzedAt 分析完成时间。
 * @return 照片标签结果对象。
 */
- (instancetype)initWithLocalIdentifier:(NSString *)localIdentifier
                                summary:(NSString *)summary
                                   tags:(NSArray<NSString *> *)tags
                             analyzedAt:(NSDate *)analyzedAt;

/**
 * @brief 将对象转换为可持久化字典。
 * @return 字典结构。
 */
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

/**
 * @brief 通过字典恢复照片标签结果。
 * @param dictionary 持久化字典。
 * @return 照片标签结果对象。
 */
+ (nullable instancetype)classificationWithDictionary:(NSDictionary<NSString *, id> *)dictionary;

/**
 * @brief 判断当前结果是否匹配搜索关键字。
 * @param keyword 用户输入的搜索词。
 * @return 是否匹配。
 */
- (BOOL)matchesKeyword:(NSString *)keyword;

@end

NS_ASSUME_NONNULL_END
