#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

NS_ASSUME_NONNULL_BEGIN

@interface SAAlbumItem : NSObject

@property (nonatomic, strong) PHAssetCollection *collection;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) NSUInteger assetCount;
@property (nonatomic, assign) NSUInteger analyzedCount;

/**
 * @brief 使用相册集合初始化相册列表项。
 * @param collection 系统相册集合。
 * @param title 相册标题。
 * @param assetCount 相册照片数量。
 * @param analyzedCount 已分析照片数量。
 * @return 相册列表项对象。
 */
- (instancetype)initWithCollection:(PHAssetCollection *)collection
                             title:(NSString *)title
                        assetCount:(NSUInteger)assetCount
                     analyzedCount:(NSUInteger)analyzedCount;

@end

NS_ASSUME_NONNULL_END
