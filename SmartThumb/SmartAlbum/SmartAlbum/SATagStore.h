#import <Foundation/Foundation.h>

@class SAPhotoClassification;

NS_ASSUME_NONNULL_BEGIN

@interface SATagStore : NSObject

/**
 * @brief 加载本地已缓存的全部照片标签结果。
 * @return 以照片标识为 key 的结果字典。
 */
- (NSDictionary<NSString *, SAPhotoClassification *> *)loadAllClassifications;

/**
 * @brief 保存或更新单张照片的标签结果。
 * @param classification 照片标签结果。
 */
- (void)saveClassification:(SAPhotoClassification *)classification;

/**
 * @brief 根据照片标识获取标签结果。
 * @param localIdentifier 相册资源唯一标识。
 * @return 标签结果，若不存在则返回 nil。
 */
- (nullable SAPhotoClassification *)classificationForIdentifier:(NSString *)localIdentifier;

/**
 * @brief 判断指定照片是否已经分析。
 * @param localIdentifier 相册资源唯一标识。
 * @return 是否已分析。
 */
- (BOOL)hasClassificationForIdentifier:(NSString *)localIdentifier;

/**
 * @brief 按关键字搜索命中的照片标识。
 * @param keyword 搜索关键字。
 * @return 命中的照片标识集合。
 */
- (NSSet<NSString *> *)searchIdentifiersWithKeyword:(NSString *)keyword;

@end

NS_ASSUME_NONNULL_END
