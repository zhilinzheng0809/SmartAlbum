#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SAPhotoGridCell : UICollectionViewCell

/**
 * @brief 配置单元格展示内容。
 * @param image 缩略图。
 * @param title 主标题文案。
 * @param subtitle 副标题文案。
 */
- (void)configureWithImage:(nullable UIImage *)image
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle;

/**
 * @brief 控制单元格是否展示“分析中”遮罩。
 * @param shows 是否展示分析状态。
 */
- (void)setShowsAnalyzingState:(BOOL)shows;

@end

NS_ASSUME_NONNULL_END
