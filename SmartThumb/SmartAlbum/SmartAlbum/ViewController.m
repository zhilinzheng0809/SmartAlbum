//
//  ViewController.m
//  SmartAlbum
//
//  Created by zheng zhilin on 2026/5/10.
//

#import "ViewController.h"
#import "SAAlbumItem.h"
#import "SAAutoAnalysisManager.h"
#import "SAAlbumListCell.h"
#import "SAAlbumPhotosViewController.h"
#import "SAPhotoClassification.h"
#import "SAPhotoDetailViewController.h"
#import "SAPhotoGridCell.h"
#import "SAVisionLLMService.h"
#import "SASpeechRecognizerService.h"
#import "SATagStore.h"
#import <Photos/Photos.h>

static NSString * const SAAlbumListCellIdentifier = @"SAAlbumListCellIdentifier";
static NSString * const SAHomeSearchPhotoCellIdentifier = @"SAHomeSearchPhotoCellIdentifier";

@interface ViewController () <UITableViewDataSource, UITableViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UISearchResultsUpdating, UISearchBarDelegate>

@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIView *autoAnalysisCardView;
@property (nonatomic, strong) UILabel *autoAnalysisTitleLabel;
@property (nonatomic, strong) UILabel *autoAnalysisDetailLabel;
@property (nonatomic, strong) UIProgressView *autoAnalysisProgressView;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) PHCachingImageManager *imageManager;
@property (nonatomic, strong) SATagStore *tagStore;
@property (nonatomic, strong) SAVisionLLMService *visionService;
@property (nonatomic, strong) SASpeechRecognizerService *speechService;
@property (nonatomic, strong) NSArray<SAAlbumItem *> *allAlbums;
@property (nonatomic, strong) NSArray<SAAlbumItem *> *filteredAlbums;
@property (nonatomic, strong) NSArray<PHAsset *> *allPhotoAssets;
@property (nonatomic, strong) NSArray<PHAsset *> *searchResultAssets;
@property (nonatomic, copy) NSString *searchKeyword;
@property (nonatomic, assign) BOOL hasPresentedAutoAnalysisPrompt;
@property (nonatomic, assign) BOOL autoAnalysisWasRunning;

@end

@implementation ViewController

/**
 * @brief 页面加载后初始化依赖、界面与相册列表数据。
 */
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.imageManager = [[PHCachingImageManager alloc] init];
    self.tagStore = [[SATagStore alloc] init];
    self.visionService = [[SAVisionLLMService alloc] init];
    self.speechService = [[SASpeechRecognizerService alloc] initWithLocaleIdentifier:@"zh-CN"];
    self.allAlbums = @[];
    self.filteredAlbums = @[];
    self.allPhotoAssets = @[];
    self.searchResultAssets = @[];
    self.searchKeyword = @"";
    self.hasPresentedAutoAnalysisPrompt = NO;
    self.autoAnalysisWasRunning = NO;

    [self setupNavigationBar];
    [self setupViews];
    [self registerForAutoAnalysisNotifications];
    [self configureAutoAnalysisManager];
    [self requestPhotoAccessAndLoadAlbums];
}

/**
 * @brief 页面即将显示时刷新相册分析状态。
 */
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.allAlbums.count > 0) {
        [self loadAlbums];
    }
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
 * @brief 控制器销毁前移除自动分析通知监听。
 */
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/**
 * @brief 配置导航栏搜索能力。
 */
- (void)setupNavigationBar {
    self.title = @"智能相册";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"模型"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(modelButtonTapped)];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchResultsUpdater = self;
    self.searchController.searchBar.placeholder = @"搜索所有照片的标签或摘要";
    self.searchController.searchBar.delegate = self;
    self.searchController.searchBar.showsBookmarkButton = YES;
    [self.searchController.searchBar setImage:[UIImage systemImageNamed:@"mic.fill"]
                            forSearchBarIcon:UISearchBarIconBookmark
                                       state:UIControlStateNormal];
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    [self updateSpeechSearchButtonAppearance];
    [self updateModelSelectionButton];
}

/**
 * @brief 构建首页相册列表视图。
 */
- (void)setupViews {
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont systemFontOfSize:13];
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    self.statusLabel.text = @"正在读取系统相册...";

    self.autoAnalysisCardView = [[UIView alloc] init];
    self.autoAnalysisCardView.translatesAutoresizingMaskIntoConstraints = NO;
    self.autoAnalysisCardView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.autoAnalysisCardView.layer.cornerRadius = 14.0;
    self.autoAnalysisCardView.hidden = YES;

    self.autoAnalysisTitleLabel = [[UILabel alloc] init];
    self.autoAnalysisTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.autoAnalysisTitleLabel.font = [UIFont boldSystemFontOfSize:15];
    self.autoAnalysisTitleLabel.textColor = [UIColor labelColor];
    self.autoAnalysisTitleLabel.text = @"自动分析";

    self.autoAnalysisDetailLabel = [[UILabel alloc] init];
    self.autoAnalysisDetailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.autoAnalysisDetailLabel.numberOfLines = 0;
    self.autoAnalysisDetailLabel.font = [UIFont systemFontOfSize:13];
    self.autoAnalysisDetailLabel.textColor = [UIColor secondaryLabelColor];

    self.autoAnalysisProgressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.autoAnalysisProgressView.translatesAutoresizingMaskIntoConstraints = NO;
    self.autoAnalysisProgressView.progressTintColor = [UIColor systemBlueColor];
    self.autoAnalysisProgressView.trackTintColor = [UIColor systemGray5Color];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 92.0;
    self.tableView.backgroundColor = [UIColor systemBackgroundColor];
    [self.tableView registerClass:[SAAlbumListCell class] forCellReuseIdentifier:SAAlbumListCellIdentifier];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 12.0;
    layout.minimumInteritemSpacing = 12.0;

    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.collectionView.backgroundColor = [UIColor systemBackgroundColor];
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.hidden = YES;
    [self.collectionView registerClass:[SAPhotoGridCell class] forCellWithReuseIdentifier:SAHomeSearchPhotoCellIdentifier];

    [self.view addSubview:self.statusLabel];
    [self.view addSubview:self.autoAnalysisCardView];
    [self.view addSubview:self.tableView];
    [self.view addSubview:self.collectionView];
    [self.autoAnalysisCardView addSubview:self.autoAnalysisTitleLabel];
    [self.autoAnalysisCardView addSubview:self.autoAnalysisDetailLabel];
    [self.autoAnalysisCardView addSubview:self.autoAnalysisProgressView];

    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [self.autoAnalysisCardView.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:10],
        [self.autoAnalysisCardView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.autoAnalysisCardView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [self.autoAnalysisTitleLabel.topAnchor constraintEqualToAnchor:self.autoAnalysisCardView.topAnchor constant:12],
        [self.autoAnalysisTitleLabel.leadingAnchor constraintEqualToAnchor:self.autoAnalysisCardView.leadingAnchor constant:12],
        [self.autoAnalysisTitleLabel.trailingAnchor constraintEqualToAnchor:self.autoAnalysisCardView.trailingAnchor constant:-12],

        [self.autoAnalysisDetailLabel.topAnchor constraintEqualToAnchor:self.autoAnalysisTitleLabel.bottomAnchor constant:6],
        [self.autoAnalysisDetailLabel.leadingAnchor constraintEqualToAnchor:self.autoAnalysisCardView.leadingAnchor constant:12],
        [self.autoAnalysisDetailLabel.trailingAnchor constraintEqualToAnchor:self.autoAnalysisCardView.trailingAnchor constant:-12],

        [self.autoAnalysisProgressView.topAnchor constraintEqualToAnchor:self.autoAnalysisDetailLabel.bottomAnchor constant:10],
        [self.autoAnalysisProgressView.leadingAnchor constraintEqualToAnchor:self.autoAnalysisCardView.leadingAnchor constant:12],
        [self.autoAnalysisProgressView.trailingAnchor constraintEqualToAnchor:self.autoAnalysisCardView.trailingAnchor constant:-12],
        [self.autoAnalysisProgressView.bottomAnchor constraintEqualToAnchor:self.autoAnalysisCardView.bottomAnchor constant:-12],

        [self.tableView.topAnchor constraintEqualToAnchor:self.autoAnalysisCardView.bottomAnchor constant:8],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.collectionView.topAnchor constraintEqualToAnchor:self.autoAnalysisCardView.bottomAnchor constant:8],
        [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

/**
 * @brief 请求相册权限并加载系统相册列表。
 */
- (void)requestPhotoAccessAndLoadAlbums {
    if (@available(iOS 14, *)) {
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
        if (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited) {
            [self loadAlbums];
            return;
        }

        [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus requestStatus) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (requestStatus == PHAuthorizationStatusAuthorized || requestStatus == PHAuthorizationStatusLimited) {
                    [self loadAlbums];
                } else {
                    self.statusLabel.text = @"未获得相册权限，请前往系统设置开启后重试。";
                }
            });
        }];
    } else {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (status == PHAuthorizationStatusAuthorized) {
                    [self loadAlbums];
                } else {
                    self.statusLabel.text = @"未获得相册权限，请前往系统设置开启后重试。";
                }
            });
        }];
    }
}

/**
 * @brief 读取系统相册并生成首页列表数据。
 */
- (void)loadAlbums {
    [self configureAutoAnalysisManager];
    NSMutableArray<SAAlbumItem *> *albums = [NSMutableArray array];
    [albums addObjectsFromArray:[self albumItemsFromFetchResult:[PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeAny options:nil]]];
    [albums addObjectsFromArray:[self albumItemsFromFetchResult:[PHCollectionList fetchTopLevelUserCollectionsWithOptions:nil]]];

    self.allAlbums = albums.copy;
    self.allPhotoAssets = [self loadAllPhotoAssets];
    [self applyFilter];
    self.statusLabel.text = [NSString stringWithFormat:@"已加载 %lu 个相册。进入相册后可对其中照片进行 AI 分析。", (unsigned long)self.allAlbums.count];
    [self presentAutoAnalysisPromptIfNeeded];
    [self syncAutoAnalysisProgressUI];
}

/**
 * @brief 读取系统图库中的全部资源，供首页全局搜索使用。
 * @return 全部资源数组。
 */
- (NSArray<PHAsset *> *)loadAllPhotoAssets {
    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
    PHFetchResult<PHAsset *> *result = [PHAsset fetchAssetsWithOptions:options];
    NSMutableArray<PHAsset *> *assets = [NSMutableArray array];
    [result enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [assets addObject:obj];
    }];
    return assets.copy;
}

/**
 * @brief 将系统集合结果转换为首页相册列表项。
 * @param fetchResult 系统集合查询结果。
 * @return 相册列表项数组。
 */
- (NSArray<SAAlbumItem *> *)albumItemsFromFetchResult:(PHFetchResult *)fetchResult {
    NSMutableArray<SAAlbumItem *> *items = [NSMutableArray array];
    PHFetchOptions *assetOptions = [[PHFetchOptions alloc] init];

    [fetchResult enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (![obj isKindOfClass:[PHAssetCollection class]]) {
            return;
        }

        PHAssetCollection *collection = (PHAssetCollection *)obj;
        PHFetchResult<PHAsset *> *assetsResult = [PHAsset fetchAssetsInAssetCollection:collection options:assetOptions];
        if (assetsResult.count == 0) {
            return;
        }

        NSUInteger analyzedCount = [self analyzedCountForAssetsResult:assetsResult];
        NSString *title = collection.localizedTitle.length > 0 ? collection.localizedTitle : @"未命名相册";
        SAAlbumItem *item = [[SAAlbumItem alloc] initWithCollection:collection
                                                              title:title
                                                         assetCount:assetsResult.count
                                                      analyzedCount:analyzedCount];
        [items addObject:item];
    }];

    return items.copy;
}

/**
 * @brief 统计某个相册结果中的已分析照片数量。
 * @param assetsResult 相册照片结果。
 * @return 已分析数量。
 */
- (NSUInteger)analyzedCountForAssetsResult:(PHFetchResult<PHAsset *> *)assetsResult {
    __block NSUInteger analyzedCount = 0;
    [assetsResult enumerateObjectsUsingBlock:^(PHAsset * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([self.tagStore hasClassificationForIdentifier:obj.localIdentifier]) {
            analyzedCount += 1;
        }
    }];
    return analyzedCount;
}

/**
 * @brief 根据搜索关键字刷新首页展示结果。
 */
- (void)applyFilter {
    NSString *trimmed = [self.searchKeyword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        self.filteredAlbums = self.allAlbums;
        self.searchResultAssets = @[];
        self.tableView.hidden = NO;
        self.collectionView.hidden = YES;
        [self.tableView reloadData];
        self.title = [NSString stringWithFormat:@"智能相册（%lu）", (unsigned long)self.filteredAlbums.count];
        self.statusLabel.text = [NSString stringWithFormat:@"已加载 %lu 个相册。进入相册后可对其中照片进行 AI 分析。", (unsigned long)self.allAlbums.count];
    } else {
        NSSet<NSString *> *matchedIdentifiers = [self.tagStore searchIdentifiersWithKeyword:trimmed];
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(PHAsset *evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
            return [matchedIdentifiers containsObject:evaluatedObject.localIdentifier];
        }];
        self.searchResultAssets = [self.allPhotoAssets filteredArrayUsingPredicate:predicate];
        self.tableView.hidden = YES;
        self.collectionView.hidden = NO;
        [self.collectionView reloadData];
        self.title = [NSString stringWithFormat:@"搜索结果（%lu）", (unsigned long)self.searchResultAssets.count];
        self.statusLabel.text = [NSString stringWithFormat:@"已搜索全部照片，命中 %lu 张。", (unsigned long)self.searchResultAssets.count];
    }
}

/**
 * @brief 注册自动分析进度通知。
 */
- (void)registerForAutoAnalysisNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleAutoAnalysisProgressChanged:)
                                                 name:SAAutoAnalysisProgressDidChangeNotification
                                               object:nil];
}

/**
 * @brief 配置自动分析管理器，供首次提醒和后台任务使用。
 */
- (void)configureAutoAnalysisManager {
    [[SAAutoAnalysisManager sharedManager] configureWithImageManager:self.imageManager
                                                           tagStore:self.tagStore
                                                      visionService:self.visionService];
}

/**
 * @brief 在首次进入应用时提醒用户是否开启后台自动分析。
 */
- (void)presentAutoAnalysisPromptIfNeeded {
    SAAutoAnalysisManager *manager = [SAAutoAnalysisManager sharedManager];
    if (self.hasPresentedAutoAnalysisPrompt || ![manager shouldPresentAutoAnalysisPrompt] || self.presentedViewController != nil) {
        return;
    }

    self.hasPresentedAutoAnalysisPrompt = YES;
    NSString *message = [NSString stringWithFormat:@"是否现在开始对相册中的照片进行后台自动分析？分析会在后台批量进行，不影响你继续浏览、搜索和管理照片，后续新增照片也会自动分析。该过程会调用 %@（%@），可能产生接口费用。",
                         [self.visionService providerDisplayName],
                         [self.visionService providerModelName]];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"开启自动分析"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"暂不启用" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        [[SAAutoAnalysisManager sharedManager] markAutoAnalysisPromptHandled];
        [self syncAutoAnalysisProgressUI];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"立即开启" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [[SAAutoAnalysisManager sharedManager] enableAutoAnalysisAndStart];
        [self syncAutoAnalysisProgressUI];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

/**
 * @brief 响应自动分析进度变化，刷新首页卡片和必要的数据展示。
 * @param notification 自动分析进度通知。
 */
- (void)handleAutoAnalysisProgressChanged:(NSNotification *)notification {
    NSDictionary<NSString *, id> *info = notification.userInfo ?: @{};
    [self updateAutoAnalysisProgressUIWithInfo:info];

    NSNumber *completedNumber = info[SAAutoAnalysisCompletedCountKey];
    if (self.searchKeyword.length > 0 && completedNumber.integerValue > 0) {
        [self applyFilter];
    }

    NSNumber *isRunningNumber = info[SAAutoAnalysisIsRunningKey];
    if (self.autoAnalysisWasRunning && !isRunningNumber.boolValue && self.allAlbums.count > 0) {
        [self loadAlbums];
    }
    self.autoAnalysisWasRunning = isRunningNumber.boolValue;
}

/**
 * @brief 点击首页导航栏模型按钮后展示可切换的模型列表。
 */
- (void)modelButtonTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择分析模型"
                                                                   message:@"你可以在阿里云百炼 Qwen 和 DeepSeek V4 之间切换，新的分析任务会使用当前所选模型。"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"阿里云百炼 Qwen" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [weakSelf switchVisionProvider:SAVisionProviderTypeQwen];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"DeepSeek V4" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [weakSelf switchVisionProvider:SAVisionProviderTypeDeepSeek];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (popover != nil) {
        popover.barButtonItem = self.navigationItem.leftBarButtonItem;
    }
    [self presentViewController:alert animated:YES completion:nil];
}

/**
 * @brief 切换当前视觉分析模型并刷新首页展示文案。
 * @param providerType 目标模型类型。
 */
- (void)switchVisionProvider:(SAVisionProviderType)providerType {
    [self.visionService switchProviderType:providerType];
    [self updateModelSelectionButton];
    [self configureAutoAnalysisManager];
    [self syncAutoAnalysisProgressUI];

    NSString *status = [NSString stringWithFormat:@"当前分析模型已切换为 %@（%@）。",
                        [self.visionService providerDisplayName],
                        [self.visionService providerModelName]];
    self.statusLabel.text = status;
    if (![self.visionService isConfigured]) {
        [self showAlertWithTitle:@"模型尚未配置" message:[self.visionService configurationMessage]];
        return;
    }
    if (![self.visionService supportsPhotoAnalysis]) {
        [self showAlertWithTitle:@"当前模型暂不可用" message:[self.visionService photoAnalysisAvailabilityMessage]];
    }
}

/**
 * @brief 刷新首页模型切换按钮标题。
 */
- (void)updateModelSelectionButton {
    self.navigationItem.leftBarButtonItem.title = [self.visionService providerShortTitle];
}

/**
 * @brief 根据管理器快照刷新首页自动分析卡片。
 */
- (void)syncAutoAnalysisProgressUI {
    NSDictionary<NSString *, id> *info = [[SAAutoAnalysisManager sharedManager] progressSnapshot];
    [self updateAutoAnalysisProgressUIWithInfo:info];
    self.autoAnalysisWasRunning = [info[SAAutoAnalysisIsRunningKey] boolValue];
}

/**
 * @brief 将自动分析状态映射到首页进度卡片。
 * @param info 自动分析状态字典。
 */
- (void)updateAutoAnalysisProgressUIWithInfo:(NSDictionary<NSString *, id> *)info {
    BOOL isEnabled = [info[SAAutoAnalysisEnabledKey] boolValue];
    BOOL isRunning = [info[SAAutoAnalysisIsRunningKey] boolValue];
    NSInteger totalCount = [info[SAAutoAnalysisTotalCountKey] integerValue];
    NSInteger completedCount = [info[SAAutoAnalysisCompletedCountKey] integerValue];
    NSInteger failedCount = [info[SAAutoAnalysisFailedCountKey] integerValue];
    NSInteger pendingCount = [info[SAAutoAnalysisPendingCountKey] integerValue];
    NSString *statusText = [info[SAAutoAnalysisStatusTextKey] isKindOfClass:[NSString class]] ? info[SAAutoAnalysisStatusTextKey] : @"";

    self.autoAnalysisCardView.hidden = !(isEnabled || isRunning);
    if (self.autoAnalysisCardView.hidden) {
        return;
    }

    self.autoAnalysisTitleLabel.text = isRunning ? @"后台自动分析中" : @"自动分析已开启";
    if (totalCount > 0) {
        self.autoAnalysisDetailLabel.text = [NSString stringWithFormat:@"%@\n进度：%ld / %ld，待处理 %ld，失败 %ld。",
                                             statusText.length > 0 ? statusText : @"后台自动分析正在进行。",
                                             (long)completedCount,
                                             (long)totalCount,
                                             (long)pendingCount,
                                             (long)failedCount];
        self.autoAnalysisProgressView.hidden = NO;
        self.autoAnalysisProgressView.progress = MIN(1.0, MAX(0.0, (float)completedCount / (float)MAX(totalCount, 1)));
    } else {
        self.autoAnalysisDetailLabel.text = statusText.length > 0 ? statusText : @"新增照片会在后台自动分析。";
        self.autoAnalysisProgressView.hidden = !isRunning;
        self.autoAnalysisProgressView.progress = 0.0f;
    }
}

#pragma mark - UITableViewDataSource

/**
 * @brief 返回首页相册列表数量。
 * @param tableView 列表视图。
 * @param section 分区索引。
 * @return 相册数量。
 */
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredAlbums.count;
}

/**
 * @brief 构建并配置相册列表单元格。
 * @param tableView 列表视图。
 * @param indexPath 位置索引。
 * @return 单元格对象。
 */
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SAAlbumListCell *cell = [tableView dequeueReusableCellWithIdentifier:SAAlbumListCellIdentifier forIndexPath:indexPath];
    SAAlbumItem *item = self.filteredAlbums[indexPath.row];

    NSString *subtitle = [NSString stringWithFormat:@"%lu 张照片 · 已分析 %lu 张",
                          (unsigned long)item.assetCount,
                          (unsigned long)item.analyzedCount];
    [cell configureWithImage:nil title:item.title subtitle:subtitle];
    cell.accessibilityIdentifier = item.collection.localIdentifier;

    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
    PHFetchResult<PHAsset *> *assetsResult = [PHAsset fetchAssetsInAssetCollection:item.collection options:options];
    PHAsset *coverAsset = assetsResult.firstObject;
    if (coverAsset != nil) {
        CGSize targetSize = CGSizeMake(136, 136);
        __weak typeof(self) weakSelf = self;
        [self.imageManager requestImageForAsset:coverAsset
                                     targetSize:targetSize
                                    contentMode:PHImageContentModeAspectFill
                                        options:nil
                                  resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }

            SAAlbumListCell *visibleCell = [strongSelf.tableView cellForRowAtIndexPath:indexPath];
            if ([visibleCell.accessibilityIdentifier isEqualToString:item.collection.localIdentifier]) {
                [visibleCell configureWithImage:result title:item.title subtitle:subtitle];
            }
        }];
    }

    return cell;
}

#pragma mark - UITableViewDelegate

/**
 * @brief 进入选中的相册照片页。
 * @param tableView 列表视图。
 * @param indexPath 位置索引。
 */
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    SAAlbumItem *item = self.filteredAlbums[indexPath.row];
    __weak typeof(self) weakSelf = self;
    SAAlbumPhotosViewController *photosViewController = [[SAAlbumPhotosViewController alloc] initWithAlbumCollection:item.collection
                                                                                                          imageManager:self.imageManager
                                                                                                              tagStore:self.tagStore
                                                                                                           visionService:self.visionService
                                                                                                            completion:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        [strongSelf loadAlbums];
    }];
    [self.navigationController pushViewController:photosViewController animated:YES];
}

#pragma mark - UICollectionViewDataSource

/**
 * @brief 返回首页搜索结果中的照片数量。
 * @param collectionView 宫格视图。
 * @param section 分区索引。
 * @return 照片数量。
 */
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.searchResultAssets.count;
}

/**
 * @brief 构建首页全局搜索结果的照片宫格单元格。
 * @param collectionView 宫格视图。
 * @param indexPath 位置索引。
 * @return 单元格对象。
 */
- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    SAPhotoGridCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:SAHomeSearchPhotoCellIdentifier forIndexPath:indexPath];
    PHAsset *asset = self.searchResultAssets[indexPath.item];
    SAPhotoClassification *classification = [self.tagStore classificationForIdentifier:asset.localIdentifier];

    NSString *title = classification.tags.count > 0 ? [classification.tags componentsJoinedByString:@" · "] : @"未分析";
    NSString *subtitle = classification.summary.length > 0 ? classification.summary : [self fallbackSubtitleForAsset:asset];
    [cell configureWithImage:nil title:title subtitle:subtitle];
    [cell setShowsAnalyzingState:NO];
    cell.selected = NO;
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
            [visibleCell setShowsAnalyzingState:NO];
        }
    }];
    return cell;
}

#pragma mark - UICollectionViewDelegate

/**
 * @brief 点击首页搜索结果中的照片后进入照片详情页。
 * @param collectionView 宫格视图。
 * @param indexPath 位置索引。
 */
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:NO];

    PHAsset *asset = self.searchResultAssets[indexPath.item];
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
        strongSelf.allPhotoAssets = [strongSelf loadAllPhotoAssets];
        [strongSelf applyFilter];
    }];
    [self.navigationController pushViewController:detailViewController animated:YES];
}

#pragma mark - UICollectionViewDelegateFlowLayout

/**
 * @brief 计算首页搜索结果宫格单元格尺寸。
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
 * @brief 响应搜索框变化并刷新首页搜索结果。
 * @param searchController 搜索控制器。
 */
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchKeyword = searchController.searchBar.text ?: @"";
    [self applyFilter];
}

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

        NSString *trimmedText = [recognizedText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmedText.length == 0) {
            return;
        }

        strongSelf.searchController.active = YES;
        strongSelf.searchController.searchBar.text = trimmedText;
        strongSelf.searchKeyword = trimmedText;
        [strongSelf applyFilter];
    } stateHandler:^(BOOL isRecognizing) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        strongSelf.searchController.active = YES;
        [strongSelf updateSpeechSearchButtonAppearance];
        if (isRecognizing) {
            [strongSelf updateSpeechRecognitionPrompt:@"正在识别中..."];
            strongSelf.statusLabel.text = @"正在语音识别，请直接说出搜索内容。";
        } else if (strongSelf.searchController.isActive) {
            [strongSelf updateSpeechRecognitionPrompt:nil];
            strongSelf.statusLabel.text = @"已停止语音识别，可继续编辑搜索内容。";
        }
    } errorHandler:^(NSString *message) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        [strongSelf updateSpeechRecognitionPrompt:nil];
        [strongSelf updateSpeechSearchButtonAppearance];
        [strongSelf showAlertWithTitle:@"语音搜索不可用" message:message];
    }];
}

/**
 * @brief 点击搜索框关闭按钮时结束语音识别并恢复首页相册列表。
 * @param searchBar 当前搜索栏。
 */
- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    [self.speechService stopRecognition];
    [self updateSpeechRecognitionPrompt:nil];
    [self updateSpeechSearchButtonAppearance];
    self.searchKeyword = @"";
    searchBar.text = @"";
    [self applyFilter];
}

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
 * @brief 更新搜索框顶部的语音识别提示文案。
 * @param prompt 提示文案，传空则清除。
 */
- (void)updateSpeechRecognitionPrompt:(NSString * _Nullable)prompt {
    self.searchController.searchBar.prompt = prompt;
}

/**
 * @brief 展示通用提示弹窗。
 * @param title 标题文案。
 * @param message 内容文案。
 */
- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

/**
 * @brief 生成首页搜索结果宫格缩略图目标尺寸。
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
