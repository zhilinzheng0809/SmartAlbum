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

@interface SAAutoAnalysisManager () <PHPhotoLibraryChangeObserver>

@property (nonatomic, strong) PHCachingImageManager *imageManager;
@property (nonatomic, strong) SATagStore *tagStore;
@property (nonatomic, strong) SAQwenVLService *qwenService;
@property (nonatomic, strong) PHFetchResult<PHAsset *> *allImageAssetsFetchResult;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *pendingAssetIdentifiers;
@property (nonatomic, strong) NSMutableSet<NSString *> *processingAssetIdentifiers;
@property (nonatomic, assign, readwrite) BOOL autoAnalysisEnabled;
@property (nonatomic, assign, readwrite) BOOL isAnalyzing;
@property (nonatomic, assign) NSInteger totalCount;
@property (nonatomic, assign) NSInteger completedCount;
@property (nonatomic, assign) NSInteger failedCount;
@property (nonatomic, copy, nullable) NSString *currentAnalyzingIdentifier;
@property (nonatomic, copy) NSString *statusText;
@property (nonatomic, assign) BOOL hasRegisteredPhotoObserver;

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
        _processingAssetIdentifiers = [NSMutableSet set];
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
        self.completedCount = 0;
        self.failedCount = 0;
        self.totalCount = 0;
        self.currentAnalyzingIdentifier = nil;
    }

    NSInteger appendedCount = 0;
    for (PHAsset *asset in assets) {
        if (asset.mediaType != PHAssetMediaTypeImage) {
            continue;
        }

        NSString *identifier = asset.localIdentifier ?: @"";
        if (identifier.length == 0 ||
            [self.tagStore hasClassificationForIdentifier:identifier] ||
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
        self.statusText = self.pendingAssetIdentifiers.count > 0 ? @"自动分析已开启，正在后台准备照片分析任务。" : @"自动分析已开启，新增照片会自动分析。";
    }
    [self notifyProgressChanged];
}

/**
 * @brief 在当前没有任务执行时启动下一张照片的后台分析。
 */
- (void)startNextAnalysisIfNeeded {
    if (!self.autoAnalysisEnabled || self.isAnalyzing || self.pendingAssetIdentifiers.count == 0) {
        if (self.autoAnalysisEnabled && !self.isAnalyzing && self.pendingAssetIdentifiers.count == 0 && self.totalCount > 0) {
            self.statusText = self.failedCount > 0 ? @"后台自动分析已完成，部分照片分析失败。" : @"后台自动分析已完成，后续新增照片会继续自动分析。";
            [self notifyProgressChanged];
        }
        return;
    }

    if (self.imageManager == nil || self.tagStore == nil || self.qwenService == nil || ![self.qwenService isConfigured]) {
        self.statusText = @"自动分析未启动，请先完成 Qwen 配置。";
        [self notifyProgressChanged];
        return;
    }

    NSString *identifier = self.pendingAssetIdentifiers.firstObject;
    [self.pendingAssetIdentifiers removeObjectAtIndex:0];
    if (identifier.length == 0) {
        [self startNextAnalysisIfNeeded];
        return;
    }

    PHFetchResult<PHAsset *> *result = [PHAsset fetchAssetsWithLocalIdentifiers:@[identifier] options:nil];
    PHAsset *asset = result.firstObject;
    if (asset == nil || asset.mediaType != PHAssetMediaTypeImage || [self.tagStore hasClassificationForIdentifier:identifier]) {
        self.completedCount += 1;
        [self startNextAnalysisIfNeeded];
        [self notifyProgressChanged];
        return;
    }

    self.isAnalyzing = YES;
    self.currentAnalyzingIdentifier = identifier;
    [self.processingAssetIdentifiers addObject:identifier];
    self.statusText = [NSString stringWithFormat:@"后台正在分析第 %ld / %ld 张照片，不影响你继续浏览和搜索。",
                       (long)(self.completedCount + 1),
                       (long)MAX(self.totalCount, 1)];
    [self notifyProgressChanged];

    __weak typeof(self) weakSelf = self;
    [self requestOptimizedImageDataForAsset:asset completion:^(NSData * _Nullable imageData) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        if (imageData.length == 0) {
            [strongSelf finishAutoAnalysisForIdentifier:identifier classification:nil error:[NSError errorWithDomain:@"SAAutoAnalysisManager"
                                                                                                                  code:2001
                                                                                                              userInfo:@{NSLocalizedDescriptionKey: @"照片读取失败"}]];
            return;
        }

        [strongSelf.qwenService analyzeImageData:imageData localIdentifier:identifier completion:^(SAPhotoClassification * _Nullable classification, NSError * _Nullable error) {
            [strongSelf finishAutoAnalysisForIdentifier:identifier classification:classification error:error];
        }];
    }];
}

/**
 * @brief 完成单张照片后台分析后更新进度，并继续处理队列。
 * @param identifier 当前照片标识。
 * @param classification 分析结果。
 * @param error 错误对象。
 */
- (void)finishAutoAnalysisForIdentifier:(NSString *)identifier
                         classification:(SAPhotoClassification * _Nullable)classification
                                  error:(NSError * _Nullable)error {
    [self.processingAssetIdentifiers removeObject:identifier];
    self.completedCount += 1;
    if (classification != nil) {
        [self.tagStore saveClassification:classification];
    } else {
        self.failedCount += 1;
    }

    self.isAnalyzing = NO;
    self.currentAnalyzingIdentifier = nil;
    self.statusText = error != nil ? @"后台分析继续进行中，刚刚有照片分析失败。" : @"后台分析继续进行中。";
    [self notifyProgressChanged];
    [self startNextAnalysisIfNeeded];
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
    options.version = PHImageRequestOptionsVersionCurrent;

    [self.imageManager requestImageDataAndOrientationForAsset:asset
                                                      options:options
                                                resultHandler:^(NSData * _Nullable imageData, NSString * _Nullable dataUTI, CGImagePropertyOrientation orientation, NSDictionary * _Nullable info) {
        if (imageData.length == 0) {
            completion(nil);
            return;
        }

        UIImage *image = [UIImage imageWithData:imageData];
        NSData *compressedData = [self compressedJPEGDataFromImage:image maxPixel:1280];
        completion(compressedData ?: imageData);
    }];
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
