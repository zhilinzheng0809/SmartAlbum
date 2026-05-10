#import "SAAutoAnalysisManager.h"
#import "SAPhotoClassification.h"
#import "SAQwenVLService.h"
#import "SATagStore.h"
#import <UIKit/UIKit.h>

NSString * const SAAutoAnalysisProgressDidChangeNotification = @"SAAutoAnalysisProgressDidChangeNotification";
NSString * const SAAutoAnalysisIsRunningKey = @"isRunning";
NSString * const SAAutoAnalysisEnabledKey = @"isEnabled";
NSString * const SAAutoAnalysisTotalCountKey = @"totalCount";
NSString * const SAAutoAnalysisCompletedCountKey = @"completedCount";
NSString * const SAAutoAnalysisFailedCountKey = @"failedCount";
NSString * const SAAutoAnalysisPendingCountKey = @"pendingCount";
NSString * const SAAutoAnalysisCurrentIdentifierKey = @"currentIdentifier";
NSString * const SAAutoAnalysisStatusTextKey = @"statusText";

static NSString * const SAAutoAnalysisPromptHandledDefaultsKey = @"SAAutoAnalysisPromptHandledDefaultsKey";
static NSString * const SAAutoAnalysisEnabledDefaultsKey = @"SAAutoAnalysisEnabledDefaultsKey";
static NSInteger const SAAutoAnalysisBatchSize = 10;
static NSInteger const SAAutoAnalysisMaxConcurrentBatches = 10;

@interface SAAutoAnalysisManager () <PHPhotoLibraryChangeObserver>

@property (nonatomic, strong) PHCachingImageManager *imageManager;
@property (nonatomic, strong) SATagStore *tagStore;
@property (nonatomic, strong) SAQwenVLService *qwenService;
@property (nonatomic, strong) PHFetchResult<PHAsset *> *allImageAssetsFetchResult;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *pendingAssetIdentifiers;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *processingAssetIdentifiers;
@property (nonatomic, strong) NSMutableSet<NSString *> *failedAssetIdentifiers;
@property (nonatomic, assign, readwrite) BOOL autoAnalysisEnabled;
@property (nonatomic, assign, readwrite) BOOL isAnalyzing;
@property (nonatomic, assign) NSInteger totalCount;
@property (nonatomic, assign) NSInteger completedCount;
@property (nonatomic, assign) NSInteger failedCount;
@property (nonatomic, copy, nullable) NSString *currentAnalyzingIdentifier;
@property (nonatomic, copy) NSString *statusText;
@property (nonatomic, assign) BOOL hasRegisteredPhotoObserver;
@property (nonatomic, assign) NSInteger runningBatchCount;

@end

@implementation SAAutoAnalysisManager

/**
 * @brief 返回自动分析管理器单例。
 * @return 管理器实例。
 */
+ (instancetype)sharedManager {
    static SAAutoAnalysisManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[SAAutoAnalysisManager alloc] init];
    });
    return manager;
}

/**
 * @brief 初始化基础状态并监听应用活跃事件。
 * @return 管理器实例。
 */
- (instancetype)init {
    self = [super init];
    if (self) {
        _pendingAssetIdentifiers = [NSMutableOrderedSet orderedSet];
        _processingAssetIdentifiers = [NSMutableOrderedSet orderedSet];
        _failedAssetIdentifiers = [NSMutableSet set];
        _autoAnalysisEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:SAAutoAnalysisEnabledDefaultsKey];
        _statusText = @"自动分析未开启。";
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];
    }
    return self;
}

/**
 * @brief 销毁前移除通知监听。
 */
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (self.hasRegisteredPhotoObserver) {
        [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
    }
}

/**
 * @brief 注入自动分析所需依赖，并准备监听图库变化。
 * @param imageManager 图片读取管理器。
 * @param tagStore 标签存储对象。
 * @param qwenService 大模型分析服务。
 */
- (void)configureWithImageManager:(PHCachingImageManager *)imageManager
                         tagStore:(SATagStore *)tagStore
                      qwenService:(SAQwenVLService *)qwenService {
    self.imageManager = imageManager;
    self.tagStore = tagStore;
    self.qwenService = qwenService;
    [self refreshAllImageAssetsFetchResult];
    [self registerPhotoLibraryObserverIfNeeded];

    if (self.autoAnalysisEnabled) {
        [self enqueueUnanalyzedAssetsFromCurrentLibraryResetProgress:NO];
        [self startNextAnalysisIfNeeded];
    } else {
        self.statusText = @"自动分析未开启。";
        [self notifyProgressChanged];
    }
}

/**
 * @brief 判断当前是否应该展示首次自动分析提醒。
 * @return 是否需要提醒用户。
 */
- (BOOL)shouldPresentAutoAnalysisPrompt {
    if (self.autoAnalysisEnabled) {
        return NO;
    }

    if (self.tagStore == nil || self.qwenService == nil || ![self.qwenService isConfigured]) {
        return NO;
    }

    if (![self hasPhotoLibraryAccess]) {
        return NO;
    }

    return ![[NSUserDefaults standardUserDefaults] boolForKey:SAAutoAnalysisPromptHandledDefaultsKey];
}

/**
 * @brief 标记首次提醒已处理，避免重复弹出。
 */
- (void)markAutoAnalysisPromptHandled {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:SAAutoAnalysisPromptHandledDefaultsKey];
}

/**
 * @brief 开启自动分析，并立即将未分析照片加入后台任务。
 */
- (void)enableAutoAnalysisAndStart {
    [self markAutoAnalysisPromptHandled];
    self.autoAnalysisEnabled = YES;
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:SAAutoAnalysisEnabledDefaultsKey];
    self.totalCount = 0;
    self.completedCount = 0;
    self.failedCount = 0;
    self.runningBatchCount = 0;
    [self enqueueUnanalyzedAssetsFromCurrentLibraryResetProgress:YES];
    [self startNextAnalysisIfNeeded];
}

/**
 * @brief 返回当前自动分析进度快照。
 * @return 进度信息字典。
 */
- (NSDictionary<NSString *,id> *)progressSnapshot {
    return @{
        SAAutoAnalysisIsRunningKey: @(self.isAnalyzing),
        SAAutoAnalysisEnabledKey: @(self.autoAnalysisEnabled),
        SAAutoAnalysisTotalCountKey: @(self.totalCount),
        SAAutoAnalysisCompletedCountKey: @(self.completedCount),
        SAAutoAnalysisFailedCountKey: @(self.failedCount),
        SAAutoAnalysisPendingCountKey: @(self.pendingAssetIdentifiers.count),
        SAAutoAnalysisCurrentIdentifierKey: self.currentAnalyzingIdentifier ?: @"",
        SAAutoAnalysisStatusTextKey: self.statusText ?: @""
    };
}

/**
 * @brief 应用回到前台后恢复自动分析任务。
 */
- (void)applicationDidBecomeActive {
    if (!self.autoAnalysisEnabled) {
        return;
    }

    [self refreshAllImageAssetsFetchResult];
    [self enqueueUnanalyzedAssetsFromCurrentLibraryResetProgress:NO];
    [self startNextAnalysisIfNeeded];
}

/**
 * @brief 监听图库变化并将新增照片加入自动分析队列。
 * @param changeInstance 图库变更信息。
 */
- (void)photoLibraryDidChange:(PHChange *)changeInstance {
    PHFetchResultChangeDetails<PHAsset *> *changeDetails = [changeInstance changeDetailsForFetchResult:self.allImageAssetsFetchResult];
    if (changeDetails == nil) {
        return;
    }

    self.allImageAssetsFetchResult = changeDetails.fetchResultAfterChanges;
    if (!self.autoAnalysisEnabled) {
        return;
    }

    NSArray<PHAsset *> *insertedAssets = changeDetails.insertedObjects ?: @[];
    if (insertedAssets.count == 0) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self enqueueAssetsIfNeeded:insertedAssets resetProgress:NO];
        [self startNextAnalysisIfNeeded];
    });
}

/**
 * @brief 刷新当前图库中的全部图片抓取结果。
 */
- (void)refreshAllImageAssetsFetchResult {
    if (![self hasPhotoLibraryAccess]) {
        self.allImageAssetsFetchResult = nil;
        return;
    }

    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
    self.allImageAssetsFetchResult = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:options];
}

/**
 * @brief 如有权限则注册图库变化监听。
 */
- (void)registerPhotoLibraryObserverIfNeeded {
    if (self.hasRegisteredPhotoObserver || ![self hasPhotoLibraryAccess]) {
        return;
    }

    [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
    self.hasRegisteredPhotoObserver = YES;
}

/**
 * @brief 判断当前是否已获得相册访问权限。
 * @return 是否可访问。
 */
- (BOOL)hasPhotoLibraryAccess {
    if (@available(iOS 14, *)) {
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
        return status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited;
    }

    return [PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusAuthorized;
}

/**
 * @brief 将图库中尚未分析的照片加入后台队列。
 * @param resetProgress 是否重置本轮进度。
 */
- (void)enqueueUnanalyzedAssetsFromCurrentLibraryResetProgress:(BOOL)resetProgress {
    if (self.allImageAssetsFetchResult == nil) {
        [self refreshAllImageAssetsFetchResult];
    }

    NSMutableArray<PHAsset *> *assets = [NSMutableArray array];
    [self.allImageAssetsFetchResult enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [assets addObject:obj];
    }];
    [self enqueueAssetsIfNeeded:assets.copy resetProgress:resetProgress];
}

/**
 * @brief 将指定照片数组加入待分析队列，并更新进度总量。
 * @param assets 待入队照片数组。
 * @param resetProgress 是否重置本轮进度。
 */
- (void)enqueueAssetsIfNeeded:(NSArray<PHAsset *> *)assets resetProgress:(BOOL)resetProgress {
    if (resetProgress) {
        [self.pendingAssetIdentifiers removeAllObjects];
        [self.processingAssetIdentifiers removeAllObjects];
        [self.failedAssetIdentifiers removeAllObjects];
        self.completedCount = 0;
        self.failedCount = 0;
        self.totalCount = 0;
        self.currentAnalyzingIdentifier = nil;
        self.runningBatchCount = 0;
        self.isAnalyzing = NO;
    }

    NSInteger appendedCount = 0;
    for (PHAsset *asset in assets) {
        if (asset.mediaType != PHAssetMediaTypeImage) {
            continue;
        }

        NSString *identifier = asset.localIdentifier ?: @"";
        if (identifier.length == 0 ||
            [self.tagStore hasClassificationForIdentifier:identifier] ||
            [self.failedAssetIdentifiers containsObject:identifier] ||
            [self.pendingAssetIdentifiers containsObject:identifier] ||
            [self.processingAssetIdentifiers containsObject:identifier]) {
            continue;
        }

        [self.pendingAssetIdentifiers addObject:identifier];
        appendedCount += 1;
    }

    if (appendedCount > 0) {
        self.totalCount += appendedCount;
    }

    if (self.autoAnalysisEnabled) {
        self.statusText = self.pendingAssetIdentifiers.count > 0 ? @"自动分析已开启，正在后台准备批量分析任务。" : @"自动分析已开启，新增照片会自动分析。";
    }
    [self notifyProgressChanged];
}

/**
 * @brief 在可用并发槽位下启动下一批后台分析任务。
 */
- (void)startNextAnalysisIfNeeded {
    if (!self.autoAnalysisEnabled) {
        return;
    }

    if (self.imageManager == nil || self.tagStore == nil || self.qwenService == nil || ![self.qwenService isConfigured]) {
        self.statusText = @"自动分析未启动，请先完成 Qwen 配置。";
        [self refreshRunningState];
        [self notifyProgressChanged];
        return;
    }

    while (self.runningBatchCount < SAAutoAnalysisMaxConcurrentBatches && self.pendingAssetIdentifiers.count > 0) {
        NSArray<NSString *> *batchIdentifiers = [self dequeuePendingIdentifiersWithLimit:SAAutoAnalysisBatchSize];
        NSArray<PHAsset *> *batchAssets = [self validAssetsForIdentifiers:batchIdentifiers];
        if (batchAssets.count == 0) {
            continue;
        }

        for (PHAsset *asset in batchAssets) {
            [self.processingAssetIdentifiers addObject:asset.localIdentifier];
        }
        self.runningBatchCount += 1;
        [self refreshRunningState];
        self.statusText = [NSString stringWithFormat:@"后台批量分析进行中，已完成 %ld / %ld，当前并发 %ld 批。",
                           (long)self.completedCount,
                           (long)MAX(self.totalCount, 1),
                           (long)self.runningBatchCount];
        [self notifyProgressChanged];

        __weak typeof(self) weakSelf = self;
        [self requestOptimizedAnalyzeItemsForAssets:batchAssets completion:^(NSArray<SAQwenAnalyzeItem *> * _Nonnull items, NSArray<NSString *> * _Nonnull failedReadIdentifiers) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            [strongSelf handlePreparedBatchItems:items
                           failedReadIdentifiers:failedReadIdentifiers];
        }];
    }

    [self refreshRunningState];
    if (!self.isAnalyzing && self.pendingAssetIdentifiers.count == 0 && self.totalCount > 0) {
        self.statusText = self.failedCount > 0 ? @"后台自动分析已完成，部分照片分析失败。" : @"后台自动分析已完成，后续新增照片会继续自动分析。";
        [self notifyProgressChanged];
    }
}

/**
 * @brief 从待分析队列中取出下一批资源标识。
 * @param limit 批次大小上限。
 * @return 资源标识数组。
 */
- (NSArray<NSString *> *)dequeuePendingIdentifiersWithLimit:(NSInteger)limit {
    NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
    NSInteger count = MIN(limit, self.pendingAssetIdentifiers.count);
    for (NSInteger index = 0; index < count; index += 1) {
        NSString *identifier = self.pendingAssetIdentifiers.firstObject;
        if (identifier.length > 0) {
            [identifiers addObject:identifier];
        }
        [self.pendingAssetIdentifiers removeObjectAtIndex:0];
    }
    return identifiers.copy;
}

/**
 * @brief 将资源标识映射回仍需分析的有效图片资源。
 * @param identifiers 资源标识数组。
 * @return 可分析图片资源数组。
 */
- (NSArray<PHAsset *> *)validAssetsForIdentifiers:(NSArray<NSString *> *)identifiers {
    NSMutableArray<PHAsset *> *assets = [NSMutableArray array];
    NSInteger skippedCount = 0;
    for (NSString *identifier in identifiers) {
        if (identifier.length == 0) {
            skippedCount += 1;
            continue;
        }

        PHFetchResult<PHAsset *> *result = [PHAsset fetchAssetsWithLocalIdentifiers:@[identifier] options:nil];
        PHAsset *asset = result.firstObject;
        if (asset == nil || asset.mediaType != PHAssetMediaTypeImage || [self.tagStore hasClassificationForIdentifier:identifier]) {
            skippedCount += 1;
            continue;
        }
        [assets addObject:asset];
    }

    if (skippedCount > 0) {
        self.completedCount += skippedCount;
    }
    return assets.copy;
}

/**
 * @brief 读取一批照片并压缩为适合提交给模型的请求项。
 * @param assets 待读取照片数组。
 * @param completion 请求项及读取失败标识回调。
 */
- (void)requestOptimizedAnalyzeItemsForAssets:(NSArray<PHAsset *> *)assets
                                   completion:(void (^)(NSArray<SAQwenAnalyzeItem *> *items, NSArray<NSString *> *failedReadIdentifiers))completion {
    NSMutableArray<SAQwenAnalyzeItem *> *preparedItems = [NSMutableArray array];
    NSMutableArray<NSString *> *failedIdentifiers = [NSMutableArray array];
    [self prepareAnalyzeItemsFromAssets:assets
                                  index:0
                          preparedItems:preparedItems
                      failedIdentifiers:failedIdentifiers
                             completion:completion];
}

/**
 * @brief 按顺序准备批次请求项，避免同一批里同时解码过多图片导致内存峰值过高。
 * @param assets 当前批次照片数组。
 * @param index 当前处理索引。
 * @param preparedItems 已准备好的请求项数组。
 * @param failedIdentifiers 读取失败标识数组。
 * @param completion 完成回调。
 */
- (void)prepareAnalyzeItemsFromAssets:(NSArray<PHAsset *> *)assets
                                index:(NSUInteger)index
                        preparedItems:(NSMutableArray<SAQwenAnalyzeItem *> *)preparedItems
                    failedIdentifiers:(NSMutableArray<NSString *> *)failedIdentifiers
                           completion:(void (^)(NSArray<SAQwenAnalyzeItem *> *items, NSArray<NSString *> *failedReadIdentifiers))completion {
    if (index >= assets.count) {
        completion(preparedItems.copy, failedIdentifiers.copy);
        return;
    }

    PHAsset *asset = assets[index];
    __weak typeof(self) weakSelf = self;
    [self requestOptimizedImageDataForAsset:asset completion:^(NSData * _Nullable imageData) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        if (imageData.length > 0) {
            SAQwenAnalyzeItem *item = [[SAQwenAnalyzeItem alloc] initWithImageData:imageData localIdentifier:asset.localIdentifier];
            [preparedItems addObject:item];
        } else {
            [failedIdentifiers addObject:asset.localIdentifier ?: @""];
        }

        [strongSelf prepareAnalyzeItemsFromAssets:assets
                                            index:index + 1
                                    preparedItems:preparedItems
                                failedIdentifiers:failedIdentifiers
                                       completion:completion];
    }];
}

/**
 * @brief 处理已准备好的批量请求项，并在必要时自动降级为单张重试。
 * @param items 已准备好的请求项数组。
 * @param failedReadIdentifiers 图片读取失败的资源标识数组。
 */
- (void)handlePreparedBatchItems:(NSArray<SAQwenAnalyzeItem *> *)items
           failedReadIdentifiers:(NSArray<NSString *> *)failedReadIdentifiers {
    if (failedReadIdentifiers.count > 0) {
        [self.failedAssetIdentifiers addObjectsFromArray:failedReadIdentifiers];
        [self.processingAssetIdentifiers removeObjectsInArray:failedReadIdentifiers];
        self.completedCount += failedReadIdentifiers.count;
        self.failedCount += failedReadIdentifiers.count;
    }

    if (items.count == 0) {
        self.runningBatchCount = MAX(0, self.runningBatchCount - 1);
        [self refreshRunningState];
        self.statusText = @"后台分析继续进行中，刚刚有照片读取失败。";
        [self notifyProgressChanged];
        [self startNextAnalysisIfNeeded];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self.qwenService analyzeBatchItems:items completion:^(NSDictionary<NSString *,SAPhotoClassification *> * _Nonnull classifications, NSArray<NSString *> * _Nonnull failedIdentifiers, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        if (error != nil && items.count > 1) {
            [strongSelf analyzeItemsIndividually:items completion:^(NSDictionary<NSString *,SAPhotoClassification *> * _Nonnull fallbackClassifications, NSArray<NSString *> * _Nonnull fallbackFailedIdentifiers) {
                [strongSelf finishBatchItems:items
                              classifications:fallbackClassifications
                           failedIdentifiers:fallbackFailedIdentifiers
                                       error:error];
            }];
            return;
        }

        [strongSelf finishBatchItems:items
                      classifications:classifications
                   failedIdentifiers:failedIdentifiers
                               error:error];
    }];
}

/**
 * @brief 将一批请求项降级为逐张分析，以降低批量失败带来的损失。
 * @param items 待降级的请求项数组。
 * @param completion 完成回调。
 */
- (void)analyzeItemsIndividually:(NSArray<SAQwenAnalyzeItem *> *)items
                      completion:(void (^)(NSDictionary<NSString *, SAPhotoClassification *> *classifications, NSArray<NSString *> *failedIdentifiers))completion {
    if (items.count == 0) {
        completion(@{}, @[]);
        return;
    }

    NSMutableDictionary<NSString *, SAPhotoClassification *> *classifications = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *failedIdentifiers = [NSMutableArray array];
    dispatch_group_t group = dispatch_group_create();

    for (SAQwenAnalyzeItem *item in items) {
        dispatch_group_enter(group);
        [self.qwenService analyzeImageData:item.imageData localIdentifier:item.localIdentifier completion:^(SAPhotoClassification * _Nullable classification, NSError * _Nullable error) {
            if (classification != nil) {
                classifications[item.localIdentifier] = classification;
            } else {
                [failedIdentifiers addObject:item.localIdentifier];
            }
            dispatch_group_leave(group);
        }];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        completion(classifications.copy, failedIdentifiers.copy);
    });
}

/**
 * @brief 处理一批照片的最终分析结果并刷新整体进度。
 * @param items 当前批次请求项。
 * @param classifications 成功结果映射。
 * @param failedIdentifiers 失败资源标识数组。
 * @param error 错误对象。
 */
- (void)finishBatchItems:(NSArray<SAQwenAnalyzeItem *> *)items
          classifications:(NSDictionary<NSString *, SAPhotoClassification *> *)classifications
       failedIdentifiers:(NSArray<NSString *> *)failedIdentifiers
                   error:(NSError * _Nullable)error {
    NSMutableArray<NSString *> *processedIdentifiers = [NSMutableArray array];
    for (SAQwenAnalyzeItem *item in items) {
        [processedIdentifiers addObject:item.localIdentifier];
        SAPhotoClassification *classification = classifications[item.localIdentifier];
        if (classification != nil) {
            [self.failedAssetIdentifiers removeObject:item.localIdentifier];
            [self.tagStore saveClassification:classification];
        } else {
            [self.failedAssetIdentifiers addObject:item.localIdentifier];
        }
    }

    [self.processingAssetIdentifiers removeObjectsInArray:processedIdentifiers];
    self.completedCount += processedIdentifiers.count;
    self.failedCount += failedIdentifiers.count;
    self.runningBatchCount = MAX(0, self.runningBatchCount - 1);
    [self refreshRunningState];

    if (error != nil && failedIdentifiers.count > 0) {
        self.statusText = @"后台批量分析继续进行中，部分照片已降级重试但仍失败。";
    } else if (failedIdentifiers.count > 0) {
        self.statusText = @"后台批量分析继续进行中，部分照片分析失败。";
    } else {
        self.statusText = @"后台批量分析继续进行中。";
    }

    [self notifyProgressChanged];
    [self startNextAnalysisIfNeeded];
}

/**
 * @brief 根据当前处理集合刷新运行态和当前分析标识。
 */
- (void)refreshRunningState {
    self.isAnalyzing = self.runningBatchCount > 0;
    self.currentAnalyzingIdentifier = self.processingAssetIdentifiers.firstObject;
}

/**
 * @brief 读取照片数据并压缩为适合发送给模型的 JPEG。
 * @param asset 相册资源。
 * @param completion 图片数据回调。
 */
- (void)requestOptimizedImageDataForAsset:(PHAsset *)asset completion:(void (^)(NSData * _Nullable imageData))completion {
    PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
    options.networkAccessAllowed = YES;
    options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    options.resizeMode = PHImageRequestOptionsResizeModeExact;
    options.version = PHImageRequestOptionsVersionCurrent;

    CGSize targetSize = [self analysisTargetSize];
    [self.imageManager requestImageForAsset:asset
                                 targetSize:targetSize
                                contentMode:PHImageContentModeAspectFit
                                    options:options
                              resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if ([info[PHImageCancelledKey] boolValue]) {
            completion(nil);
            return;
        }

        if ([info[PHImageResultIsDegradedKey] boolValue]) {
            return;
        }

        if (result == nil) {
            completion(nil);
            return;
        }

        @autoreleasepool {
            NSData *compressedData = [self compressedJPEGDataFromImage:result maxPixel:1280];
            completion(compressedData);
        }
    }];
}

/**
 * @brief 返回分析阶段请求的目标图片尺寸，避免先加载原始大图再压缩。
 * @return 目标像素尺寸。
 */
- (CGSize)analysisTargetSize {
    return CGSizeMake(1280, 1280);
}

/**
 * @brief 将图片压缩到适合模型分析的尺寸，降低带宽和费用。
 * @param image 原始图片。
 * @param maxPixel 最大边长。
 * @return JPEG 数据。
 */
- (NSData * _Nullable)compressedJPEGDataFromImage:(UIImage *)image maxPixel:(CGFloat)maxPixel {
    if (image == nil) {
        return nil;
    }

    CGSize size = image.size;
    CGFloat maxSide = MAX(size.width, size.height);
    if (maxSide <= maxPixel) {
        return UIImageJPEGRepresentation(image, 0.75);
    }

    CGFloat scale = maxPixel / maxSide;
    CGSize targetSize = CGSizeMake(size.width * scale, size.height * scale);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:targetSize];
    UIImage *resized = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        [image drawInRect:CGRectMake(0, 0, targetSize.width, targetSize.height)];
    }];
    return UIImageJPEGRepresentation(resized, 0.72);
}

/**
 * @brief 将最新自动分析进度通过通知广播给界面层。
 */
- (void)notifyProgressChanged {
    NSDictionary *snapshot = [self progressSnapshot];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SAAutoAnalysisProgressDidChangeNotification
                                                            object:self
                                                          userInfo:snapshot];
    });
}

@end
