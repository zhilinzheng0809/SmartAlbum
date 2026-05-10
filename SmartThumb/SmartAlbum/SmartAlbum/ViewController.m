//
//  ViewController.m
//  SmartAlbum
//
//  Created by zheng zhilin on 2026/5/10.
//

#import "ViewController.h"
#import "SAAlbumItem.h"
#import "SAAlbumListCell.h"
#import "SAAlbumPhotosViewController.h"
#import "SAPhotoClassification.h"
#import "SAPhotoDetailViewController.h"
#import "SAPhotoGridCell.h"
#import "SAQwenVLService.h"
#import "SATagStore.h"
#import <Photos/Photos.h>

static NSString * const SAAlbumListCellIdentifier = @"SAAlbumListCellIdentifier";
static NSString * const SAHomeSearchPhotoCellIdentifier = @"SAHomeSearchPhotoCellIdentifier";

@interface ViewController () <UITableViewDataSource, UITableViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UISearchResultsUpdating>

@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) PHCachingImageManager *imageManager;
@property (nonatomic, strong) SATagStore *tagStore;
@property (nonatomic, strong) SAQwenVLService *qwenService;
@property (nonatomic, strong) NSArray<SAAlbumItem *> *allAlbums;
@property (nonatomic, strong) NSArray<SAAlbumItem *> *filteredAlbums;
@property (nonatomic, strong) NSArray<PHAsset *> *allPhotoAssets;
@property (nonatomic, strong) NSArray<PHAsset *> *searchResultAssets;
@property (nonatomic, copy) NSString *searchKeyword;

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
    self.qwenService = [[SAQwenVLService alloc] init];
    self.allAlbums = @[];
    self.filteredAlbums = @[];
    self.allPhotoAssets = @[];
    self.searchResultAssets = @[];
    self.searchKeyword = @"";

    [self setupNavigationBar];
    [self setupViews];
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
 * @brief 配置导航栏搜索能力。
 */
- (void)setupNavigationBar {
    self.title = @"智能相册";

    UISearchController *searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    searchController.obscuresBackgroundDuringPresentation = NO;
    searchController.searchResultsUpdater = self;
    searchController.searchBar.placeholder = @"搜索所有照片的标签或摘要";
    self.navigationItem.searchController = searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
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
    [self.view addSubview:self.tableView];
    [self.view addSubview:self.collectionView];

    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [self.tableView.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:8],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.collectionView.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:8],
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
    NSMutableArray<SAAlbumItem *> *albums = [NSMutableArray array];
    [albums addObjectsFromArray:[self albumItemsFromFetchResult:[PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeAny options:nil]]];
    [albums addObjectsFromArray:[self albumItemsFromFetchResult:[PHCollectionList fetchTopLevelUserCollectionsWithOptions:nil]]];

    self.allAlbums = albums.copy;
    self.allPhotoAssets = [self loadAllPhotoAssets];
    [self applyFilter];
    self.statusLabel.text = [NSString stringWithFormat:@"已加载 %lu 个相册。进入相册后可对其中照片进行 AI 分析。", (unsigned long)self.allAlbums.count];
}

/**
 * @brief 读取系统图库中的全部照片，供首页全局搜索使用。
 * @return 全部照片数组。
 */
- (NSArray<PHAsset *> *)loadAllPhotoAssets {
    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
    PHFetchResult<PHAsset *> *result = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:options];
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
                                                                                                           qwenService:self.qwenService
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
                                                                                                qwenService:self.qwenService
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
