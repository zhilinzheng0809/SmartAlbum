#import <UIKit/UIKit.h>

@class PHAssetCollection;
@class PHCachingImageManager;
@class SATagStore;
@class SAQwenVLService;

NS_ASSUME_NONNULL_BEGIN

@interface SAAlbumPhotosViewController : UIViewController

/**
 * @brief 使用相册级依赖初始化照片列表页。
 * @param albumCollection 当前相册集合。
 * @param imageManager 图片读取管理器。
 * @param tagStore 标签存储对象。
 * @param qwenService 大模型分析服务。
 * @param completion 相册数据变更后的回调。
 * @return 相册照片页控制器。
 */
- (instancetype)initWithAlbumCollection:(PHAssetCollection *)albumCollection
                           imageManager:(PHCachingImageManager *)imageManager
                               tagStore:(SATagStore *)tagStore
                            qwenService:(SAQwenVLService *)qwenService
                             completion:(void (^ _Nullable)(void))completion;

@end

NS_ASSUME_NONNULL_END
