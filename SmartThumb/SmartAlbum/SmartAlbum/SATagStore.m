#import "SATagStore.h"
#import "SAPhotoClassification.h"

@interface SATagStore ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, SAPhotoClassification *> *cache;

@end

@implementation SATagStore

/**
 * @brief 初始化本地标签仓储并加载缓存数据。
 * @return 仓储实例。
 */
- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [[self readPersistedCache] mutableCopy];
    }
    return self;
}

/**
 * @brief 加载本地已缓存的全部照片标签结果。
 * @return 以照片标识为 key 的结果字典。
 */
- (NSDictionary<NSString *,SAPhotoClassification *> *)loadAllClassifications {
    return self.cache.copy;
}

/**
 * @brief 保存或更新单张照片的标签结果。
 * @param classification 照片标签结果。
 */
- (void)saveClassification:(SAPhotoClassification *)classification {
    if (classification.localIdentifier.length == 0) {
        return;
    }

    self.cache[classification.localIdentifier] = classification;
    [self persistCache];
}

/**
 * @brief 根据照片标识获取标签结果。
 * @param localIdentifier 相册资源唯一标识。
 * @return 标签结果，若不存在则返回 nil。
 */
- (SAPhotoClassification *)classificationForIdentifier:(NSString *)localIdentifier {
    return self.cache[localIdentifier];
}

/**
 * @brief 判断指定照片是否已经分析。
 * @param localIdentifier 相册资源唯一标识。
 * @return 是否已分析。
 */
- (BOOL)hasClassificationForIdentifier:(NSString *)localIdentifier {
    return [self classificationForIdentifier:localIdentifier] != nil;
}

/**
 * @brief 按关键字搜索命中的照片标识。
 * @param keyword 搜索关键字。
 * @return 命中的照片标识集合。
 */
- (NSSet<NSString *> *)searchIdentifiersWithKeyword:(NSString *)keyword {
    NSString *trimmed = [keyword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return [NSSet setWithArray:self.cache.allKeys];
    }

    NSMutableSet<NSString *> *matched = [NSMutableSet set];
    [self.cache enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, SAPhotoClassification * _Nonnull obj, BOOL * _Nonnull stop) {
        if ([obj matchesKeyword:trimmed]) {
            [matched addObject:key];
        }
    }];
    return matched.copy;
}

/**
 * @brief 将缓存持久化到本地 JSON 文件。
 */
- (void)persistCache {
    NSMutableDictionary<NSString *, NSDictionary *> *dictionary = [NSMutableDictionary dictionary];
    [self.cache enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, SAPhotoClassification * _Nonnull obj, BOOL * _Nonnull stop) {
        dictionary[key] = [obj dictionaryRepresentation];
    }];

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:NSJSONWritingPrettyPrinted error:&error];
    if (data == nil || error != nil) {
        return;
    }

    [data writeToURL:[self storeURL] atomically:YES];
}

/**
 * @brief 从本地 JSON 文件恢复缓存。
 * @return 缓存字典。
 */
- (NSDictionary<NSString *, SAPhotoClassification *> *)readPersistedCache {
    NSData *data = [NSData dataWithContentsOfURL:[self storeURL]];
    if (data.length == 0) {
        return @{};
    }

    NSError *error = nil;
    NSDictionary<NSString *, NSDictionary *> *raw = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![raw isKindOfClass:[NSDictionary class]] || error != nil) {
        return @{};
    }

    NSMutableDictionary<NSString *, SAPhotoClassification *> *result = [NSMutableDictionary dictionary];
    [raw enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSDictionary * _Nonnull obj, BOOL * _Nonnull stop) {
        SAPhotoClassification *classification = [SAPhotoClassification classificationWithDictionary:obj];
        if (classification != nil) {
            result[key] = classification;
        }
    }];
    return result.copy;
}

/**
 * @brief 返回本地标签缓存文件路径。
 * @return 缓存文件 URL。
 */
- (NSURL *)storeURL {
    NSURL *libraryURL = [[[NSFileManager defaultManager] URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask] firstObject];
    NSURL *directoryURL = [libraryURL URLByAppendingPathComponent:@"SmartAlbumCache" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:directoryURL withIntermediateDirectories:YES attributes:nil error:nil];
    return [directoryURL URLByAppendingPathComponent:@"photo-tags.json"];
}

@end
