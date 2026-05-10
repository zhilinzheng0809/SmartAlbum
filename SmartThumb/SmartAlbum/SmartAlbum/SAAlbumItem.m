#import "SAAlbumItem.h"

@implementation SAAlbumItem

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
                     analyzedCount:(NSUInteger)analyzedCount {
    self = [super init];
    if (self) {
        _collection = collection;
        _title = [title copy];
        _assetCount = assetCount;
        _analyzedCount = analyzedCount;
    }
    return self;
}

@end
