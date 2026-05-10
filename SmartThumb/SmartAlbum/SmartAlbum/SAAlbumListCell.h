#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SAAlbumListCell : UITableViewCell

/**
 * @brief 配置相册列表单元格。
 * @param image 相册封面图。
 * @param title 相册标题。
 * @param subtitle 相册副标题。
 */
- (void)configureWithImage:(nullable UIImage *)image
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle;

@end

NS_ASSUME_NONNULL_END
