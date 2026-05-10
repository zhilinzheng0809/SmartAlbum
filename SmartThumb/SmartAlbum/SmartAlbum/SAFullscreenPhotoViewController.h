#import <UIKit/UIKit.h>

@class PHAsset;
@class PHCachingImageManager;

NS_ASSUME_NONNULL_BEGIN

@interface SAFullscreenPhotoViewController : UIViewController

/**
 * @brief 使用照片资源和图片管理器初始化全屏浏览控制器。
 * @param asset 当前展示的相册资源。
 * @param imageManager 图片读取管理器。
 * @param placeholderImage 进入全屏前的占位图片。
 * @return 全屏浏览控制器实例。
 */
- (instancetype)initWithAsset:(PHAsset *)asset
                 imageManager:(PHCachingImageManager *)imageManager
             placeholderImage:(nullable UIImage *)placeholderImage;

@end

NS_ASSUME_NONNULL_END
