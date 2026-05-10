#import <UIKit/UIKit.h>

@class PHAsset;
@class PHCachingImageManager;
@class SATagStore;
@class SAQwenVLService;

NS_ASSUME_NONNULL_BEGIN

@interface SAPhotoDetailViewController : UIViewController

/**
 * @brief 使用详情页依赖初始化控制器。
 * @param asset 当前展示的相册资源。
 * @param imageManager 缩略图与原图读取管理器。
 * @param tagStore 标签存储对象。
 * @param qwenService 大模型分析服务。
 * @param completion 分析完成后的回调。
 * @return 详情页控制器。
 */
- (instancetype)initWithAsset:(PHAsset *)asset
                 imageManager:(PHCachingImageManager *)imageManager
                     tagStore:(SATagStore *)tagStore
                  qwenService:(SAQwenVLService *)qwenService
                   completion:(void (^ _Nullable)(void))completion;

@end

NS_ASSUME_NONNULL_END
