#import "SAAlbumPhotosViewController.h"
#import "SAPhotoClassification.h"
#import "SAPhotoDetailViewController.h"
#import "SAPhotoGridCell.h"
#import "SAVisionLLMService.h"
#import "SASpeechRecognizerService.h"
#import "SATagStore.h"
#import <Photos/Photos.h>

static NSString * const SAAlbumPhotoGridCellIdentifier = @"SAAlbumPhotoGridCellIdentifier";
static NSInteger const SAAlbumAnalyzeBatchSize = 10;
static NSInteger const SAAlbumAnalyzeMaxConcurrentBatches = 10;
static CGFloat const SAAlbumAnalyzeImageMaxPixel = 960.0;
static CGFloat const SAAlbumAnalyzeJPEGQuality = 0.68;

@interface SAAlbumPhotosViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UISearchResultsUpdating, UISearchBarDelegate>

@property (nonatomic, strong) PHAssetCollection *albumCollection;
@property (nonatomic, strong) PHCachingImageManager *imageManager;
@property (nonatomic, strong) SATagStore *tagStore;
@property (nonatomic, strong) SAVisionLLMService *visionService;
@property (nonatomic, copy, nullable) void (^completionHandler)(void);
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *analyzeUnlabeledButton;
@property (nonatomic, strong) UIButton *analyzeAllButton;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSArray<PHAsset *> *allAssets;
@property (nonatomic, strong) NSArray<PHAsset *> *filteredAssets;
@property (nonatomic, copy) NSString *searchKeyword;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *analyzingAssetIdentifiers;
@property (nonatomic, assign) BOOL isManagingPhotos;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *selectedAssetIdentifiers;
@property (nonatomic, strong) SASpeechRecognizerService *speechService;
@property (nonatomic, assign) BOOL isAnalyzing;
@property (nonatomic, assign) NSInteger analyzeTotalCount;
@property (nonatomic, assign) NSInteger analyzeCompletedCount;
@property (nonatomic, assign) NSInteger analyzeFailedCount;
@property (nonatomic, strong) NSMutableArray<PHAsset *> *pendingAnalysisAssets;
@property (nonatomic, assign) NSInteger runningAnalyzeBatchCount;

@end

@implementation SAAlbumPhotosViewController

/**
 * @brief 使用相册级依赖初始化照片列表页。
 * @param albumCollection 当前相册集合。
 * @param imageManager 图片读取管理器。
 * @param tagStore 标签存储对象。
 * @param visionService 大模型分析服务。
 * @param completion 相册数据变更后的回调。
 * @return 相册照片页控制器。
 */
- (instancetype)initWithAlbumCollection:(PHAssetCollection *)albumCollection
                           imageManager:(PHCachingImageManager *)imageManager
                               tagStore:(SATagStore *)tagStore
                          visionService:(SAVisionLLMService *)visionService
                             completion:(void (^)(void))completion {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _albumCollection = albumCollection;
        _imageManager = imageManager;
        _tagStore = tagStore;
        _visionService = visionService;
        _completionHandler = [completion copy];
        _allAssets = @[];
        _filteredAssets = @[];
        _searchKeyword = @"";
        _analyzingAssetIdentifiers = [NSMutableOrderedSet orderedSet];
        _selectedAssetIdentifiers = [NSMutableOrderedSet orderedSet];
        _speechService = [[SASpeechRecognizerService alloc] initWithLocaleIdentifier:@"zh-CN"];
        _pendingAnalysisAssets = [NSMutableArray array];
    }
    return self;
}

/**
 * @brief 页面加载后初始化导航、界面与相册照片数据。
 */
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    [self setupNavigationBar];
    [self setupViews];
    [self loadAssets];
}

/**
 * @brief 页面离开时停止可能仍在进行的语音识别。
 * @param animated 是否带动画。
 */
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.speechService stopRecognition];
    [self updateSpeechSearchButtonAppearance];
}

/**
 * @brief 配置导航栏搜索能力。
 */
- (void)setupNavigationBar {
    self.title = self.albumCollection.localizedTitle ?: @"相册";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"管理"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(toggleManageModeTapped)];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchResultsUpdater = self;
    self.searchController.searchBar.placeholder = @"搜索当前相册中的标签或摘要";
    self.searchController.searchBar.delegate = self;
    self.searchController.searchBar.showsBookmarkButton = YES;
    [self.searchController.searchBar setImage:[UIImage systemImageNamed:@"mic.fill"]
                            forSearchBarIcon:UISearchBarIconBookmark
                                       state:UIControlStateNormal];
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    [self updateSpeechSearchButtonAppearance];
}

/**
 * @brief 构建相册照片页视图。
 */
- (void)setupViews {
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont systemFontOfSize:13];
    self.statusLabel.textColor = [UIColor secondaryLabelColor];

    self.analyzeUnlabeledButton = [self primaryButtonWithTitle:@"分析未标记" action:@selector(analyzeUnlabeledTapped)];
    self.analyzeAllButton = [self secondaryButtonWithTitle:@"分析当前相册" action:@selector(analyzeAllTapped)];

    UIStackView *buttonStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.analyzeUnlabeledButton, self.analyzeAllButton]];
    buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
    buttonStack.axis = UILayoutConstraintAxisHorizontal;
    buttonStack.spacing = 12.0;
    buttonStack.distribution = UIStackViewDistributionFillEqually;

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 12.0;
    layout.minimumInteritemSpacing = 12.0;

    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.collectionView.backgroundColor = [UIColor systemBackgroundColor];
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    [self.collectionView registerClass:[SAPhotoGridCell class] forCellWithReuseIdentifier:SAAlbumPhotoGridCellIdentifier];

    [self.view addSubview:self.statusLabel];
    [self.view addSubview:buttonStack];
    [self.view addSubview:self.collectionView];

    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [buttonStack.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:12],
        [buttonStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [buttonStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [self.collectionView.topAnchor constraintEqualToAnchor:buttonStack.bottomAnchor constant:12],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

/**
 * @brief 创建主要操作按钮。
 * @param title 按钮标题。
 * @param action 点击事件。
 * @return 按钮实例。
 */
- (UIButton *)primaryButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.backgroundColor = [UIColor systemBlueColor];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    button.layer.cornerRadius = 10.0;
    [button.heightAnchor constraintEqualToConstant:44].active = YES;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

/**
 * @brief 创建次要操作按钮。
 * @param title 按钮标题。
 * @param action 点击事件。
 * @return 按钮实例。
 */
- (UIButton *)secondaryButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.backgroundColor = [UIColor tertiarySystemFillColor];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    button.layer.cornerRadius = 10.0;
    [button.heightAnchor constraintEqualToConstant:44].active = YES;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

/**
 * @brief 读取当前相册中的照片并刷新列表。
 */
- (void)loadAssets {
    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
    PHFetchResult<PHAsset *> *result = [PHAsset fetchAssetsInAssetCollection:self.albumCollection options:options];

    NSMutableArray<PHAsset *> *assets = [NSMutableArray array];
    [result enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [assets addObject:obj];
    }];
    self.allAssets = assets.copy;
    [self.selectedAssetIdentifiers removeAllObjects];
    [self applyFilter];
    [self updateStatusWithText:[NSString stringWithFormat:@"当前相册共 %lu 张照片，已标记 %lu 张。",
                                (unsigned long)self.allAssets.count,
                                (unsigned long)[self analyzedCountInAssets:self.allAssets]]];
}

/**
 * @brief 根据当前搜索关键字刷新照片结果。
 */
- (void)applyFilter {
    NSString *trimmed = [self.searchKeyword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        self.filteredAssets = self.allAssets;
    } else {
        NSSet<NSString *> *matchedIdentifiers = [self.tagStore searchIdentifiersWithKeyword:trimmed];
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(PHAsset *evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
            return [matchedIdentifiers containsObject:evaluatedObject.localIdentifier];
        }];
        self.filteredAssets = [self.allAssets filteredArrayUsingPredicate:predicate];
    }

    [self.collectionView reloadData];
    self.title = [NSString stringWithFormat:@"%@（%lu）", self.albumCollection.localizedTitle ?: @"相册", (unsigned long)self.filteredAssets.count];
}

/**
 * @brief 统计指定照片数组中的已分析数量。
 * @param assets 照片数组。
 * @return 已分析数量。
 */
- (NSUInteger)analyzedCountInAssets:(NSArray<PHAsset *> *)assets {
    NSUInteger count = 0;
    for (PHAsset *asset in assets) {
        if ([self.tagStore hasClassificationForIdentifier:asset.localIdentifier]) {
            count += 1;
        }
    }
    return count;
}

/**
 * @brief 更新顶部状态文案。
 * @param text 状态文本。
 */
- (void)updateStatusWithText:(NSString *)text {
    self.statusLabel.text = text;
}

/**
 * @brief 点击右上角按钮切换管理模式。
 */
- (void)toggleManageModeTapped {
    if (self.isAnalyzing) {
        [self updateStatusWithText:@"批量分析进行中，暂时无法进入管理模式。"];
        return;
    }

    [self setManagingPhotos:!self.isManagingPhotos];
}

/**
 * @brief 切换相册照片管理模式。
 * @param managing 是否进入管理模式。
 */
- (void)setManagingPhotos:(BOOL)managing {
    _isManagingPhotos = managing;
    [self.selectedAssetIdentifiers removeAllObjects];
    self.collectionView.allowsMultipleSelection = managing;
    self.collectionView.allowsSelection = YES;

    if (!managing) {
        for (NSIndexPath *indexPath in self.collectionView.indexPathsForSelectedItems.copy) {
            [self.collectionView deselectItemAtIndexPath:indexPath animated:NO];
        }
    }

    self.navigationItem.rightBarButtonItem.title = managing ? @"完成" : @"管理";
    self.navigationItem.hidesBackButton = managing;
    self.navigationItem.leftBarButtonItem = managing ? [[UIBarButtonItem alloc] initWithTitle:@"删除(0)"
                                                                                          style:UIBarButtonItemStylePlain
                                                                                         target:self
                                                                                         action:@selector(deleteSelectedPhotosTapped)] : nil;
    self.navigationItem.leftBarButtonItem.tintColor = managing ? [UIColor systemRedColor] : nil;
    self.navigationItem.leftBarButtonItem.enabled = NO;
    self.analyzeUnlabeledButton.hidden = managing;
    self.analyzeAllButton.hidden = managing;
    [self.collectionView reloadData];

    if (managing) {
        [self updateStatusWithText:@"已进入管理模式，选择照片后可删除。"];
    } else {
        [self updateStatusWithText:[NSString stringWithFormat:@"当前相册共 %lu 张照片，已标记 %lu 张。",
                                    (unsigned long)self.allAssets.count,
                                    (unsigned long)[self analyzedCountInAssets:self.allAssets]]];
    }
}

/**
 * @brief 更新删除按钮文案与可用状态。
 */
- (void)updateDeleteButtonState {
    if (!self.isManagingPhotos) {
        return;
    }

    NSUInteger count = self.selectedAssetIdentifiers.count;
    self.navigationItem.leftBarButtonItem.title = [NSString stringWithFormat:@"删除(%lu)", (unsigned long)count];
    self.navigationItem.leftBarButtonItem.enabled = (count > 0);
}

/**
 * @brief 处理“分析未标记”按钮点击。
 */
- (void)analyzeUnlabeledTapped {
    NSArray<PHAsset *> *targets = [self assetsNeedingAnalysisFromAssets:self.filteredAssets];
    [self startBatchAnalysisWithAssets:targets title:@"分析相册中未标记照片"];
}

/**
 * @brief 处理“分析当前相册”按钮点击。
 */
- (void)analyzeAllTapped {
    [self startBatchAnalysisWithAssets:self.filteredAssets title:@"分析当前相册照片"];
}

/**
 * @brief 点击删除按钮后删除当前已选照片。
 */
- (void)deleteSelectedPhotosTapped {
    if (self.selectedAssetIdentifiers.count == 0) {
        return;
    }

    NSArray<PHAsset *> *selectedAssets = [self selectedAssetsFromIdentifiers];
    NSString *message = [NSString stringWithFormat:@"确定删除选中的 %lu 张照片吗？此操作会从系统相册中移除这些照片。", (unsigned long)selectedAssets.count];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"删除照片" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self deleteAssets:selectedAssets];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

/**
 * @brief 根据已选标识恢复对应照片数组。
 * @return 当前选中的照片数组。
 */
- (NSArray<PHAsset *> *)selectedAssetsFromIdentifiers {
    NSMutableArray<PHAsset *> *assets = [NSMutableArray array];
    for (NSString *identifier in self.selectedAssetIdentifiers) {
        NSUInteger index = [self.allAssets indexOfObjectPassingTest:^BOOL(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            return [obj.localIdentifier isEqualToString:identifier];
        }];
        if (index != NSNotFound) {
            [assets addObject:self.allAssets[index]];
        }
    }
    return assets.copy;
}

/**
 * @brief 调用系统相册接口删除选中的照片。
 * @param assets 待删除照片数组。
 */
- (void)deleteAssets:(NSArray<PHAsset *> *)assets {
    if (assets.count == 0) {
        return;
    }

    [self updateStatusWithText:[NSString stringWithFormat:@"正在删除 %lu 张照片...", (unsigned long)assets.count]];
    __weak typeof(self) weakSelf = self;
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        [PHAssetChangeRequest deleteAssets:assets];
    } completionHandler:^(BOOL success, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }

            if (success) {
                [strongSelf setManagingPhotos:NO];
                [strongSelf loadAssets];
                [strongSelf updateStatusWithText:@"已删除所选照片。"];
                if (strongSelf.completionHandler != nil) {
                    strongSelf.completionHandler();
                }
            } else {
                [strongSelf updateStatusWithText:[NSString stringWithFormat:@"删除失败：%@", error.localizedDescription ?: @"未知错误"]];
            }
        });
    }];
}

/**
 * @brief 从给定照片数组中过滤出尚未分析的照片。
 * @param assets 待筛选照片数组。
 * @return 未分析照片数组。
 */
- (NSArray<PHAsset *> *)assetsNeedingAnalysisFromAssets:(NSArray<PHAsset *> *)assets {
    NSMutableArray<PHAsset *> *result = [NSMutableArray array];
    for (PHAsset *asset in assets) {
        if (![self.tagStore hasClassificationForIdentifier:asset.localIdentifier]) {
            [result addObject:asset];
        }
    }
    return result.copy;
}

/**
 * @brief 发起相册级批量分析前的校验与确认。
 * @param assets 目标照片数组。
 * @param title 操作标题。
 */
- (void)startBatchAnalysisWithAssets:(NSArray<PHAsset *> *)assets title:(NSString *)title {
    if (self.isAnalyzing) {
        [self updateStatusWithText:@"当前已有分析任务在执行，请稍候。"];
        return;
    }

    if (![self.visionService isConfigured]) {
        [self showAlertWithTitle:@"未配置分析模型" message:[self.visionService configurationMessage]];
        return;
    }

    if (![self.visionService supportsPhotoAnalysis]) {
        [self showAlertWithTitle:@"当前模型暂不支持照片分析" message:[self.visionService photoAnalysisAvailabilityMessage]];
        return;
    }

    if (assets.count == 0) {
        [self updateStatusWithText:@"当前相册没有可分析的照片。"];
        return;
    }

    NSString *message = [NSString stringWithFormat:@"即将调用 %@（%@）分析当前相册中的 %lu 张照片，可能产生接口费用。是否继续？",
                         [self.visionService providerDisplayName],
                         [self.visionService providerModelName],
                         (unsigned long)assets.count];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"继续" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self beginBatchAnalysisWithAssets:assets];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

/**
 * @brief 启动微批量并发分析流程。
 * @param assets 待分析照片数组。
 */
- (void)beginBatchAnalysisWithAssets:(NSArray<PHAsset *> *)assets {
    self.isAnalyzing = YES;
    [self.analyzingAssetIdentifiers removeAllObjects];
    self.analyzeTotalCount = (NSInteger)assets.count;
    self.analyzeCompletedCount = 0;
    self.analyzeFailedCount = 0;
    self.runningAnalyzeBatchCount = 0;
    self.pendingAnalysisAssets = [assets mutableCopy];
    [self updateAnalyzeButtonsEnabled:NO];
    [self startNextAnalyzeBatchIfNeeded];
}

/**
 * @brief 在可用并发槽位下启动下一批相册照片分析。
 */
- (void)startNextAnalyzeBatchIfNeeded {
    while (self.runningAnalyzeBatchCount < SAAlbumAnalyzeMaxConcurrentBatches && self.pendingAnalysisAssets.count > 0) {
        NSArray<PHAsset *> *batchAssets = [self dequeuePendingAnalysisAssetsWithLimit:SAAlbumAnalyzeBatchSize];
        if (batchAssets.count == 0) {
            continue;
        }

        self.runningAnalyzeBatchCount += 1;
        for (PHAsset *asset in batchAssets) {
            [self.analyzingAssetIdentifiers addObject:asset.localIdentifier];
        }
        [self refreshVisibleAnalyzingState];
        [self scrollToAssetIfNeeded:batchAssets.firstObject];
        [self updateStatusWithText:[NSString stringWithFormat:@"正在批量分析当前相册，已完成 %ld / %ld，当前批次 %lu 张，并发 %ld 批。",
                                    (long)self.analyzeCompletedCount,
                                    (long)MAX(self.analyzeTotalCount, 1),
                                    (unsigned long)batchAssets.count,
                                    (long)self.runningAnalyzeBatchCount]];

        __weak typeof(self) weakSelf = self;
        [self requestOptimizedAnalyzeItemsForAssets:batchAssets completion:^(NSArray<SAVisionAnalyzeItem *> * _Nonnull items, NSArray<NSString *> * _Nonnull failedReadIdentifiers) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            [strongSelf handlePreparedAnalyzeItems:items failedReadIdentifiers:failedReadIdentifiers];
        }];
    }

    [self completeAnalyzeFlowIfNeeded];
}

/**
 * @brief 从待分析数组中取出下一批照片。
 * @param limit 批次大小上限。
 * @return 当前批次照片数组。
 */
- (NSArray<PHAsset *> *)dequeuePendingAnalysisAssetsWithLimit:(NSInteger)limit {
    NSInteger count = MIN(limit, self.pendingAnalysisAssets.count);
    if (count <= 0) {
        return @[];
    }

    NSArray<PHAsset *> *batchAssets = [self.pendingAnalysisAssets subarrayWithRange:NSMakeRange(0, count)];
    [self.pendingAnalysisAssets removeObjectsInRange:NSMakeRange(0, count)];
    return batchAssets;
}

/**
 * @brief 读取一批照片并压缩为适合提交给模型的请求项。
 * @param assets 待读取照片数组。
 * @param completion 请求项及读取失败标识回调。
 */
- (void)requestOptimizedAnalyzeItemsForAssets:(NSArray<PHAsset *> *)assets
                                   completion:(void (^)(NSArray<SAVisionAnalyzeItem *> *items, NSArray<NSString *> *failedReadIdentifiers))completion {
    NSMutableArray<SAVisionAnalyzeItem *> *preparedItems = [NSMutableArray array];
    NSMutableArray<NSString *> *failedIdentifiers = [NSMutableArray array];
    [self requestOptimizedAnalyzeItemsForAssets:assets
                                          index:0
                                  preparedItems:preparedItems
                              failedIdentifiers:failedIdentifiers
                                     completion:completion];
}

/**
 * @brief 按顺序逐张准备一批图片请求项，避免同时解码整批大图造成内存峰值过高。
 * @param assets 待读取照片数组。
 * @param index 当前处理下标。
 * @param preparedItems 已准备好的请求项容器。
 * @param failedIdentifiers 读取失败标识容器。
 * @param completion 全部完成回调。
 */
- (void)requestOptimizedAnalyzeItemsForAssets:(NSArray<PHAsset *> *)assets
                                        index:(NSInteger)index
                                preparedItems:(NSMutableArray<SAVisionAnalyzeItem *> *)preparedItems
                            failedIdentifiers:(NSMutableArray<NSString *> *)failedIdentifiers
                                   completion:(void (^)(NSArray<SAVisionAnalyzeItem *> *items, NSArray<NSString *> *failedReadIdentifiers))completion {
    if (index >= (NSInteger)assets.count) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(preparedItems.copy, failedIdentifiers.copy);
        });
        return;
    }

    PHAsset *asset = assets[(NSUInteger)index];
    __weak typeof(self) weakSelf = self;
    [self requestOptimizedImageDataForAsset:asset completion:^(NSData * _Nullable imageData) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        @autoreleasepool {
            if (imageData.length > 0) {
                SAVisionAnalyzeItem *item = [[SAVisionAnalyzeItem alloc] initWithImageData:imageData localIdentifier:asset.localIdentifier];
                [preparedItems addObject:item];
            } else {
                [failedIdentifiers addObject:asset.localIdentifier ?: @""];
            }
        }

        [strongSelf requestOptimizedAnalyzeItemsForAssets:assets
                                                    index:index + 1
                                            preparedItems:preparedItems
                                        failedIdentifiers:failedIdentifiers
                                               completion:completion];
    }];
}

/**
 * @brief 处理已准备好的批量请求项，并在必要时降级为逐张重试。
 * @param items 已准备好的请求项数组。
 * @param failedReadIdentifiers 图片读取失败的资源标识数组。
 */
- (void)handlePreparedAnalyzeItems:(NSArray<SAVisionAnalyzeItem *> *)items
             failedReadIdentifiers:(NSArray<NSString *> *)failedReadIdentifiers {
    if (failedReadIdentifiers.count > 0) {
        [self.analyzingAssetIdentifiers removeObjectsInArray:failedReadIdentifiers];
        self.analyzeCompletedCount += failedReadIdentifiers.count;
        self.analyzeFailedCount += failedReadIdentifiers.count;
        [self refreshVisibleAnalyzingState];
    }

    if (items.count == 0) {
        self.runningAnalyzeBatchCount = MAX(0, self.runningAnalyzeBatchCount - 1);
        [self updateStatusWithText:@"部分照片读取失败，批量分析继续进行中。"];
        [self startNextAnalyzeBatchIfNeeded];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self.visionService analyzeBatchItems:items completion:^(NSDictionary<NSString *,SAPhotoClassification *> * _Nonnull classifications, NSArray<NSString *> * _Nonnull failedIdentifiers, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        if (error != nil && items.count > 1) {
            [strongSelf analyzeItemsIndividually:items completion:^(NSDictionary<NSString *,SAPhotoClassification *> * _Nonnull fallbackClassifications, NSArray<NSString *> * _Nonnull fallbackFailedIdentifiers) {
                [strongSelf finishAnalyzeBatchItems:items
                                     classifications:fallbackClassifications
                                  failedIdentifiers:fallbackFailedIdentifiers
                                              error:error];
            }];
            return;
        }

        [strongSelf finishAnalyzeBatchItems:items
                             classifications:classifications
                          failedIdentifiers:failedIdentifiers
                                      error:error];
    }];
}

/**
 * @brief 将一批请求项降级为逐张分析，以降低整批失败的影响。
 * @param items 待降级请求项数组。
 * @param completion 完成回调。
 */
- (void)analyzeItemsIndividually:(NSArray<SAVisionAnalyzeItem *> *)items
                      completion:(void (^)(NSDictionary<NSString *, SAPhotoClassification *> *classifications, NSArray<NSString *> *failedIdentifiers))completion {
    if (items.count == 0) {
        completion(@{}, @[]);
        return;
    }

    NSMutableDictionary<NSString *, SAPhotoClassification *> *classifications = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *failedIdentifiers = [NSMutableArray array];
    dispatch_group_t group = dispatch_group_create();

    for (SAVisionAnalyzeItem *item in items) {
        dispatch_group_enter(group);
        [self.visionService analyzeImageData:item.imageData localIdentifier:item.localIdentifier completion:^(SAPhotoClassification * _Nullable classification, NSError * _Nullable error) {
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
 * @brief 处理一批照片的最终分析结果并刷新相册分析进度。
 * @param items 当前批次请求项。
 * @param classifications 成功结果映射。
 * @param failedIdentifiers 失败资源标识数组。
 * @param error 错误对象。
 */
- (void)finishAnalyzeBatchItems:(NSArray<SAVisionAnalyzeItem *> *)items
                 classifications:(NSDictionary<NSString *, SAPhotoClassification *> *)classifications
              failedIdentifiers:(NSArray<NSString *> *)failedIdentifiers
                          error:(NSError * _Nullable)error {
    NSMutableArray<NSString *> *processedIdentifiers = [NSMutableArray array];
    for (SAVisionAnalyzeItem *item in items) {
        [processedIdentifiers addObject:item.localIdentifier];
        SAPhotoClassification *classification = classifications[item.localIdentifier];
        if (classification != nil) {
            [self.tagStore saveClassification:classification];
            [self reloadAssetIfVisibleWithIdentifier:item.localIdentifier];
        }
    }

    [self.analyzingAssetIdentifiers removeObjectsInArray:processedIdentifiers];
    self.analyzeCompletedCount += processedIdentifiers.count;
    self.analyzeFailedCount += failedIdentifiers.count;
    self.runningAnalyzeBatchCount = MAX(0, self.runningAnalyzeBatchCount - 1);
    [self refreshVisibleAnalyzingState];

    if (error != nil && failedIdentifiers.count > 0) {
        [self updateStatusWithText:@"当前批次已自动降级重试，但仍有部分照片分析失败。"];
    } else if (failedIdentifiers.count > 0) {
        [self updateStatusWithText:@"当前批次已完成，但有部分照片分析失败。"];
    } else {
        [self updateStatusWithText:[NSString stringWithFormat:@"批量分析继续进行中，已完成 %ld / %ld。",
                                    (long)self.analyzeCompletedCount,
                                    (long)MAX(self.analyzeTotalCount, 1)]];
    }

    [self startNextAnalyzeBatchIfNeeded];
}

/**
 * @brief 在所有批次结束后收尾分析流程并刷新页面状态。
 */
- (void)completeAnalyzeFlowIfNeeded {
    if (self.pendingAnalysisAssets.count > 0 || self.runningAnalyzeBatchCount > 0) {
        return;
    }

    if (!self.isAnalyzing) {
        return;
    }

    self.isAnalyzing = NO;
    [self.analyzingAssetIdentifiers removeAllObjects];
    [self updateAnalyzeButtonsEnabled:YES];
    [self refreshVisibleAnalyzingState];
    [self applyFilter];
    [self updateStatusWithText:[NSString stringWithFormat:@"分析完成，共 %ld 张，成功 %ld 张，失败 %ld 张。",
                                (long)self.analyzeTotalCount,
                                (long)(self.analyzeCompletedCount - self.analyzeFailedCount),
                                (long)self.analyzeFailedCount]];
    if (self.completionHandler != nil) {
        self.completionHandler();
    }
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
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            @autoreleasepool {
                UIImage *image = [UIImage imageWithData:imageData];
                NSData *compressedData = [self compressedJPEGDataFromImage:image maxPixel:SAAlbumAnalyzeImageMaxPixel];
                completion(compressedData ?: imageData);
            }
        });
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
        return UIImageJPEGRepresentation(image, SAAlbumAnalyzeJPEGQuality);
    }

    CGFloat scale = maxPixel / maxSide;
    CGSize targetSize = CGSizeMake(size.width * scale, size.height * scale);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:targetSize];
    UIImage *resized = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        [image drawInRect:CGRectMake(0, 0, targetSize.width, targetSize.height)];
    }];
    return UIImageJPEGRepresentation(resized, SAAlbumAnalyzeJPEGQuality);
}

/**
 * @brief 若单元格当前可见则刷新对应位置。
 * @param localIdentifier 刚完成分析的照片资源标识。
 */
- (void)reloadAssetIfVisibleWithIdentifier:(NSString *)localIdentifier {
    NSUInteger index = [self.filteredAssets indexOfObjectPassingTest:^BOOL(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return [obj.localIdentifier isEqualToString:localIdentifier];
    }];
    if (index != NSNotFound) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:index inSection:0];
        if ([[self.collectionView indexPathsForVisibleItems] containsObject:indexPath]) {
            [self.collectionView reloadItemsAtIndexPaths:@[indexPath]];
        } else {
            [self applyFilter];
        }
    } else if (self.searchKeyword.length > 0) {
        [self applyFilter];
    }
}

/**
 * @brief 刷新当前可见单元格的“分析中”展示状态。
 */
- (void)refreshVisibleAnalyzingState {
    for (NSIndexPath *indexPath in self.collectionView.indexPathsForVisibleItems) {
        SAPhotoGridCell *cell = (SAPhotoGridCell *)[self.collectionView cellForItemAtIndexPath:indexPath];
        if (![cell isKindOfClass:[SAPhotoGridCell class]]) {
            continue;
        }

        PHAsset *asset = self.filteredAssets[indexPath.item];
        BOOL showsAnalyzing = [self.analyzingAssetIdentifiers containsObject:asset.localIdentifier];
        [cell setShowsAnalyzingState:showsAnalyzing];
    }
}

/**
 * @brief 将当前分析中的照片尽量滚动到可视区域，便于观察进度。
 * @param asset 正在分析的照片资源。
 */
- (void)scrollToAssetIfNeeded:(PHAsset *)asset {
    NSUInteger index = [self.filteredAssets indexOfObjectPassingTest:^BOOL(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return [obj.localIdentifier isEqualToString:asset.localIdentifier];
    }];
    if (index == NSNotFound) {
        return;
    }

    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:index inSection:0];
    [self.collectionView scrollToItemAtIndexPath:indexPath atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:YES];
}

/**
 * @brief 更新分析按钮的可用状态。
 * @param enabled 是否可点击。
 */
- (void)updateAnalyzeButtonsEnabled:(BOOL)enabled {
    self.analyzeUnlabeledButton.enabled = enabled;
    self.analyzeAllButton.enabled = enabled;
    self.analyzeUnlabeledButton.alpha = enabled ? 1.0 : 0.5;
    self.analyzeAllButton.alpha = enabled ? 1.0 : 0.5;
}

/**
 * @brief 展示简单提示弹窗。
 * @param title 标题。
 * @param message 文案。
 */
- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UICollectionViewDataSource

/**
 * @brief 返回当前相册宫格项目数量。
 * @param collectionView 宫格视图。
 * @param section 分区索引。
 * @return 照片数量。
 */
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.filteredAssets.count;
}

/**
 * @brief 构建并配置相册内照片宫格单元格。
 * @param collectionView 宫格视图。
 * @param indexPath 位置索引。
 * @return 单元格对象。
 */
- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    SAPhotoGridCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:SAAlbumPhotoGridCellIdentifier forIndexPath:indexPath];
    PHAsset *asset = self.filteredAssets[indexPath.item];
    SAPhotoClassification *classification = [self.tagStore classificationForIdentifier:asset.localIdentifier];

    NSString *title = classification.tags.count > 0 ? [classification.tags componentsJoinedByString:@" · "] : @"未分析";
    NSString *subtitle = classification.summary.length > 0 ? classification.summary : [self fallbackSubtitleForAsset:asset];
    [cell configureWithImage:nil title:title subtitle:subtitle];
    [cell setShowsAnalyzingState:[self.analyzingAssetIdentifiers containsObject:asset.localIdentifier]];
    BOOL showsSelectedState = (self.isManagingPhotos &&
                               [self.selectedAssetIdentifiers containsObject:asset.localIdentifier]);
    cell.selected = showsSelectedState;
    cell.accessibilityIdentifier = asset.localIdentifier;

    CGSize size = [self cellImageSize];
    __weak typeof(self) weakSelf = self;
    [self.imageManager requestImageForAsset:asset
                                 targetSize:size
                                contentMode:PHImageContentModeAspectFill
                                    options:nil
                              resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        SAPhotoGridCell *visibleCell = (SAPhotoGridCell *)[strongSelf.collectionView cellForItemAtIndexPath:indexPath];
        if ([visibleCell.accessibilityIdentifier isEqualToString:asset.localIdentifier]) {
            [visibleCell configureWithImage:result title:title subtitle:subtitle];
        }
    }];
    return cell;
}

#pragma mark - UICollectionViewDelegate

/**
 * @brief 点击相册内照片后进入照片详情页。
 * @param collectionView 宫格视图。
 * @param indexPath 位置索引。
 */
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    PHAsset *asset = self.filteredAssets[indexPath.item];
    if (self.isManagingPhotos) {
        [self.selectedAssetIdentifiers addObject:asset.localIdentifier];
        [self updateDeleteButtonState];
        SAPhotoGridCell *cell = (SAPhotoGridCell *)[collectionView cellForItemAtIndexPath:indexPath];
        cell.selected = YES;
        return;
    }

    [collectionView deselectItemAtIndexPath:indexPath animated:NO];
    SAPhotoGridCell *cell = (SAPhotoGridCell *)[collectionView cellForItemAtIndexPath:indexPath];
    cell.selected = NO;

    __weak typeof(self) weakSelf = self;
    SAPhotoDetailViewController *detailViewController = [[SAPhotoDetailViewController alloc] initWithAsset:asset
                                                                                               imageManager:self.imageManager
                                                                                                   tagStore:self.tagStore
                                                                                             visionService:self.visionService
                                                                                                 completion:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        [strongSelf applyFilter];
        [strongSelf updateStatusWithText:@"已更新当前照片的 AI 标签结果。"];
        if (strongSelf.completionHandler != nil) {
            strongSelf.completionHandler();
        }
    }];
    [self.navigationController pushViewController:detailViewController animated:YES];
}

/**
 * @brief 管理模式下取消选中照片时同步更新删除按钮状态。
 * @param collectionView 宫格视图。
 * @param indexPath 位置索引。
 */
- (void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.isManagingPhotos) {
        return;
    }

    PHAsset *asset = self.filteredAssets[indexPath.item];
    [self.selectedAssetIdentifiers removeObject:asset.localIdentifier];
    [self updateDeleteButtonState];
    SAPhotoGridCell *cell = (SAPhotoGridCell *)[collectionView cellForItemAtIndexPath:indexPath];
    cell.selected = NO;
}

#pragma mark - UICollectionViewDelegateFlowLayout

/**
 * @brief 计算宫格单元格尺寸。
 * @param collectionView 宫格视图。
 * @param collectionViewLayout 布局对象。
 * @param indexPath 位置索引。
 * @return 单元格尺寸。
 */
- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat width = floor((collectionView.bounds.size.width - 12.0) / 2.0);
    return CGSizeMake(width, width * 1.25);
}

#pragma mark - UISearchResultsUpdating

/**
 * @brief 响应搜索框变化并刷新结果。
 * @param searchController 搜索控制器。
 */
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchKeyword = searchController.searchBar.text ?: @"";
    [self applyFilter];
}

#pragma mark - UISearchBarDelegate

/**
 * @brief 点击搜索框麦克风按钮后切换语音识别状态。
 * @param searchBar 当前搜索栏。
 */
- (void)searchBarBookmarkButtonClicked:(UISearchBar *)searchBar {
    __weak typeof(self) weakSelf = self;
    [self.speechService toggleRecognitionWithResultHandler:^(NSString *recognizedText) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        strongSelf.searchController.active = YES;
        strongSelf.searchController.searchBar.text = recognizedText;
        strongSelf.searchKeyword = recognizedText;
        [strongSelf applyFilter];
    } stateHandler:^(BOOL isRecognizing) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        [strongSelf updateSpeechSearchButtonAppearance];
        if (isRecognizing) {
            [strongSelf updateStatusWithText:@"正在语音识别，请直接说出搜索内容。"];
        } else if (strongSelf.isManagingPhotos) {
            [strongSelf updateStatusWithText:@"已退出语音识别，可继续管理当前相册照片。"];
        } else if (strongSelf.searchController.isActive) {
            [strongSelf updateStatusWithText:@"已停止语音识别，可继续编辑搜索内容。"];
        }
    } errorHandler:^(NSString *message) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        [strongSelf updateSpeechSearchButtonAppearance];
        [strongSelf showAlertWithTitle:@"语音搜索不可用" message:message];
    }];
}

/**
 * @brief 点击搜索框关闭按钮时结束语音识别并恢复当前相册完整列表。
 * @param searchBar 当前搜索栏。
 */
- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    [self.speechService stopRecognition];
    [self updateSpeechSearchButtonAppearance];
    self.searchKeyword = @"";
    searchBar.text = @"";
    [self applyFilter];
}

#pragma mark - Helper

/**
 * @brief 更新搜索栏麦克风按钮的图标状态。
 */
- (void)updateSpeechSearchButtonAppearance {
    NSString *iconName = self.speechService.isRecognizing ? @"stop.circle.fill" : @"mic.fill";
    [self.searchController.searchBar setImage:[UIImage systemImageNamed:iconName]
                            forSearchBarIcon:UISearchBarIconBookmark
                                       state:UIControlStateNormal];
}

/**
 * @brief 生成宫格缩略图目标尺寸。
 * @return 目标像素尺寸。
 */
- (CGSize)cellImageSize {
    CGFloat width = floor((self.collectionView.bounds.size.width - 12.0) / 2.0);
    CGFloat scale = self.view.window.windowScene.screen.scale ?: self.view.traitCollection.displayScale;
    if (scale <= 0) {
        scale = self.view.traitCollection.displayScale;
    }
    return CGSizeMake(width * scale, width * 1.25 * scale);
}

/**
 * @brief 为未分析照片生成默认副标题。
 * @param asset 相册资源。
 * @return 展示文案。
 */
- (NSString *)fallbackSubtitleForAsset:(PHAsset *)asset {
    NSDate *date = asset.creationDate ?: [NSDate date];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm";
    return [formatter stringFromDate:date];
}

@end
