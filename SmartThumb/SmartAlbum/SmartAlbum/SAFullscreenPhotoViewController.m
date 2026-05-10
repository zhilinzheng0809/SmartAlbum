#import "SAFullscreenPhotoViewController.h"
#import <Photos/Photos.h>

@interface SAFullscreenPhotoViewController () <UIScrollViewDelegate>

@property (nonatomic, strong) PHAsset *asset;
@property (nonatomic, strong) PHCachingImageManager *imageManager;
@property (nonatomic, strong, nullable) UIImage *placeholderImage;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIImageView *imageView;

@end

@implementation SAFullscreenPhotoViewController

/**
 * @brief 使用照片资源和图片管理器初始化全屏浏览控制器。
 * @param asset 当前展示的相册资源。
 * @param imageManager 图片读取管理器。
 * @param placeholderImage 进入全屏前的占位图片。
 * @return 全屏浏览控制器实例。
 */
- (instancetype)initWithAsset:(PHAsset *)asset
                 imageManager:(PHCachingImageManager *)imageManager
             placeholderImage:(UIImage *)placeholderImage {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _asset = asset;
        _imageManager = imageManager;
        _placeholderImage = placeholderImage;
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}

/**
 * @brief 页面加载后初始化全屏浏览界面。
 */
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    [self setupViews];
    [self loadFullScreenImage];
}

/**
 * @brief 页面布局更新后按当前图片比例刷新显示区域。
 */
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateImageLayoutForCurrentImage];
}

/**
 * @brief 隐藏状态栏，提升沉浸式浏览体验。
 * @return 是否隐藏状态栏。
 */
- (BOOL)prefersStatusBarHidden {
    return YES;
}

/**
 * @brief 构建全屏图片浏览视图和手势。
 */
- (void)setupViews {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.delegate = self;
    self.scrollView.minimumZoomScale = 1.0;
    self.scrollView.maximumZoomScale = 4.0;
    self.scrollView.bouncesZoom = YES;
    self.scrollView.showsHorizontalScrollIndicator = NO;
    self.scrollView.showsVerticalScrollIndicator = NO;

    self.imageView = [[UIImageView alloc] initWithImage:self.placeholderImage];
    self.imageView.frame = CGRectZero;
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.userInteractionEnabled = YES;

    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap)];
    singleTap.numberOfTapsRequired = 1;
    [self.view addGestureRecognizer:singleTap];

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    [self.scrollView addGestureRecognizer:doubleTap];
    [singleTap requireGestureRecognizerToFail:doubleTap];

    [self.view addSubview:self.scrollView];
    [self.scrollView addSubview:self.imageView];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    [self updateImageLayoutForCurrentImage];
}

/**
 * @brief 加载更适合全屏预览的图片资源。
 */
- (void)loadFullScreenImage {
    PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
    options.networkAccessAllowed = YES;
    options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    options.resizeMode = PHImageRequestOptionsResizeModeFast;

    UIScreen *screen = self.view.window.windowScene.screen;
    CGSize screenSize = screen != nil ? screen.bounds.size : self.view.bounds.size;
    CGFloat scale = screen != nil ? screen.scale : self.view.traitCollection.displayScale;
    if (scale <= 0) {
        scale = self.view.traitCollection.displayScale;
    }
    CGSize targetSize = CGSizeMake(screenSize.width * scale, screenSize.height * scale);

    [self.imageManager requestImageForAsset:self.asset
                                 targetSize:targetSize
                                contentMode:PHImageContentModeAspectFit
                                    options:options
                              resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        if (result == nil) {
            return;
        }

        self.imageView.image = result;
        [self updateImageLayoutForCurrentImage];
    }];
}

/**
 * @brief 单击关闭全屏浏览。
 */
- (void)handleSingleTap {
    [self dismissViewControllerAnimated:YES completion:nil];
}

/**
 * @brief 双击在原始大小和放大状态之间切换。
 * @param gesture 双击手势。
 */
- (void)handleDoubleTap:(UITapGestureRecognizer *)gesture {
    if (self.scrollView.zoomScale > self.scrollView.minimumZoomScale + 0.01) {
        [self.scrollView setZoomScale:self.scrollView.minimumZoomScale animated:YES];
        return;
    }

    CGPoint point = [gesture locationInView:self.imageView];
    CGFloat zoomScale = MIN(self.scrollView.maximumZoomScale, 2.5);
    CGFloat width = self.scrollView.bounds.size.width / zoomScale;
    CGFloat height = self.scrollView.bounds.size.height / zoomScale;
    CGRect zoomRect = CGRectMake(point.x - width / 2.0, point.y - height / 2.0, width, height);
    [self.scrollView zoomToRect:zoomRect animated:YES];
}

/**
 * @brief 指定需要参与缩放的视图。
 * @param scrollView 当前滚动视图。
 * @return 参与缩放的图片视图。
 */
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.imageView;
}

/**
 * @brief 缩放过程中持续保持图片在可视区域内居中。
 * @param scrollView 当前滚动视图。
 */
- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    [self centerImageIfNeeded];
}

/**
 * @brief 根据当前图片尺寸按比例布局 imageView，避免被错误拉伸或截断。
 */
- (void)updateImageLayoutForCurrentImage {
    UIImage *image = self.imageView.image;
    CGSize boundsSize = self.scrollView.bounds.size;
    if (image == nil || boundsSize.width <= 0 || boundsSize.height <= 0) {
        return;
    }

    CGFloat widthScale = boundsSize.width / image.size.width;
    CGFloat heightScale = boundsSize.height / image.size.height;
    CGFloat fitScale = MIN(widthScale, heightScale);
    CGSize imageSize = CGSizeMake(image.size.width * fitScale, image.size.height * fitScale);

    self.scrollView.zoomScale = 1.0;
    self.imageView.frame = CGRectMake(0, 0, imageSize.width, imageSize.height);
    self.scrollView.contentSize = imageSize;
    [self centerImageIfNeeded];
}

/**
 * @brief 当图片小于滚动区域时将其居中显示，避免出现一侧明显黑边。
 */
- (void)centerImageIfNeeded {
    CGSize boundsSize = self.scrollView.bounds.size;
    CGRect frame = self.imageView.frame;
    frame.origin.x = frame.size.width < boundsSize.width ? (boundsSize.width - frame.size.width) / 2.0 : 0.0;
    frame.origin.y = frame.size.height < boundsSize.height ? (boundsSize.height - frame.size.height) / 2.0 : 0.0;
    self.imageView.frame = frame;
}

@end
