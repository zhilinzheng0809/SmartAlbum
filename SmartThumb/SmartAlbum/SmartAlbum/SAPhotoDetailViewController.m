#import "SAPhotoDetailViewController.h"
#import "SAFullscreenPhotoViewController.h"
#import "SAPhotoClassification.h"
#import "SAVisionLLMService.h"
#import "SATagStore.h"
#import <Photos/Photos.h>

@interface SAPhotoDetailViewController ()

@property (nonatomic, strong) PHAsset *asset;
@property (nonatomic, strong) PHCachingImageManager *imageManager;
@property (nonatomic, strong) SATagStore *tagStore;
@property (nonatomic, strong) SAVisionLLMService *visionService;
@property (nonatomic, copy, nullable) void (^completionHandler)(void);
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *summaryTitleLabel;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UILabel *tagsTitleLabel;
@property (nonatomic, strong) UILabel *tagsLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *analyzeButton;
@property (nonatomic, assign) BOOL isAnalyzing;

@end

@implementation SAPhotoDetailViewController

/**
 * @brief 使用详情页依赖初始化控制器。
 * @param asset 当前展示的相册资源。
 * @param imageManager 缩略图与原图读取管理器。
 * @param tagStore 标签存储对象。
 * @param visionService 大模型分析服务。
 * @param completion 分析完成后的回调。
 * @return 详情页控制器。
 */
- (instancetype)initWithAsset:(PHAsset *)asset
                 imageManager:(PHCachingImageManager *)imageManager
                     tagStore:(SATagStore *)tagStore
                visionService:(SAVisionLLMService *)visionService
                   completion:(void (^)(void))completion {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _asset = asset;
        _imageManager = imageManager;
        _tagStore = tagStore;
        _visionService = visionService;
        _completionHandler = [completion copy];
    }
    return self;
}

/**
 * @brief 页面加载后初始化详情界面。
 */
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"照片详情";
    [self setupViews];
    [self loadImage];
    [self refreshContent];
}

/**
 * @brief 构建详情页视图层级。
 */
- (void)setupViews {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;

    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = 16.0;

    self.imageView = [[UIImageView alloc] init];
    self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.imageView.layer.cornerRadius = 16.0;
    self.imageView.layer.masksToBounds = YES;
    self.imageView.userInteractionEnabled = YES;
    [self.imageView.heightAnchor constraintEqualToConstant:360].active = YES;
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(photoTapped)];
    [self.imageView addGestureRecognizer:tapGesture];

    self.timeLabel = [self infoLabelWithFont:[UIFont systemFontOfSize:14 weight:UIFontWeightMedium]];
    self.summaryTitleLabel = [self titleLabelWithText:@"照片摘要"];
    self.summaryLabel = [self infoLabelWithFont:[UIFont systemFontOfSize:15]];
    self.tagsTitleLabel = [self titleLabelWithText:@"照片标签"];
    self.tagsLabel = [self infoLabelWithFont:[UIFont systemFontOfSize:15]];
    self.statusLabel = [self infoLabelWithFont:[UIFont systemFontOfSize:13]];
    self.statusLabel.textColor = [UIColor secondaryLabelColor];

    self.analyzeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.analyzeButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.analyzeButton.backgroundColor = [UIColor systemBlueColor];
    [self.analyzeButton setTitle:@"开始分析这张照片" forState:UIControlStateNormal];
    [self.analyzeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.analyzeButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.analyzeButton.layer.cornerRadius = 12.0;
    [self.analyzeButton.heightAnchor constraintEqualToConstant:48].active = YES;
    [self.analyzeButton addTarget:self action:@selector(analyzeButtonTapped) forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:self.scrollView];
    [self.scrollView addSubview:self.contentStack];

    [self.contentStack addArrangedSubview:self.imageView];
    [self.contentStack addArrangedSubview:self.timeLabel];
    [self.contentStack addArrangedSubview:self.summaryTitleLabel];
    [self.contentStack addArrangedSubview:self.summaryLabel];
    [self.contentStack addArrangedSubview:self.tagsTitleLabel];
    [self.contentStack addArrangedSubview:self.tagsLabel];
    [self.contentStack addArrangedSubview:self.statusLabel];
    [self.contentStack addArrangedSubview:self.analyzeButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:16],
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.leadingAnchor constant:16],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.trailingAnchor constant:-16],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-24],
        [self.contentStack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor constant:-32]
    ]];
}

/**
 * @brief 点击详情页照片时进入沉浸式大图浏览模式。
 */
- (void)photoTapped {
    SAFullscreenPhotoViewController *viewController = [[SAFullscreenPhotoViewController alloc] initWithAsset:self.asset
                                                                                                imageManager:self.imageManager
                                                                                            placeholderImage:self.imageView.image];
    [self presentViewController:viewController animated:YES completion:nil];
}

/**
 * @brief 创建标题标签。
 * @param text 标题文本。
 * @return 标签对象。
 */
- (UILabel *)titleLabelWithText:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont boldSystemFontOfSize:18];
    label.textColor = [UIColor labelColor];
    label.text = text;
    return label;
}

/**
 * @brief 创建信息展示标签。
 * @param font 字体对象。
 * @return 标签对象。
 */
- (UILabel *)infoLabelWithFont:(UIFont *)font {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.numberOfLines = 0;
    label.font = font;
    label.textColor = [UIColor labelColor];
    return label;
}

/**
 * @brief 加载当前照片的大图展示。
 */
- (void)loadImage {
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
                                    options:nil
                              resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
        self.imageView.image = result;
    }];
}

/**
 * @brief 根据当前缓存刷新详情页标签与摘要。
 */
- (void)refreshContent {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm";
    self.timeLabel.text = [NSString stringWithFormat:@"拍摄时间：%@", [formatter stringFromDate:self.asset.creationDate ?: [NSDate date]]];

    SAPhotoClassification *classification = [self.tagStore classificationForIdentifier:self.asset.localIdentifier];
    if (classification != nil) {
        self.summaryLabel.text = classification.summary.length > 0 ? classification.summary : @"暂无摘要";
        self.tagsLabel.text = classification.tags.count > 0 ? [classification.tags componentsJoinedByString:@" · "] : @"暂无标签";
        self.statusLabel.text = [NSString stringWithFormat:@"最近分析时间：%@", [formatter stringFromDate:classification.analyzedAt]];
        [self.analyzeButton setTitle:@"重新分析这张照片" forState:UIControlStateNormal];
    } else {
        self.summaryLabel.text = @"尚未分析这张照片。";
        self.tagsLabel.text = @"暂无标签";
        self.statusLabel.text = [NSString stringWithFormat:@"点击下方按钮后将调用 %@（%@）生成摘要和标签。",
                                 [self.visionService providerDisplayName],
                                 [self.visionService providerModelName]];
        [self.analyzeButton setTitle:@"开始分析这张照片" forState:UIControlStateNormal];
    }
}

/**
 * @brief 点击分析按钮后调用大模型分析当前照片。
 */
- (void)analyzeButtonTapped {
    if (self.isAnalyzing) {
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

    NSString *message = [NSString stringWithFormat:@"将调用 %@（%@）分析当前照片并生成摘要与标签，可能产生接口费用。是否继续？",
                         [self.visionService providerDisplayName],
                         [self.visionService providerModelName]];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"开始分析" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"继续" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self startAnalysis];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

/**
 * @brief 执行当前照片分析流程。
 */
- (void)startAnalysis {
    self.isAnalyzing = YES;
    self.analyzeButton.enabled = NO;
    self.analyzeButton.alpha = 0.5;
    self.statusLabel.text = @"正在分析当前照片...";

    __weak typeof(self) weakSelf = self;
    [self requestOptimizedImageDataWithCompletion:^(NSData * _Nullable imageData) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        if (imageData.length == 0) {
            [strongSelf finishAnalysisWithClassification:nil errorMessage:@"当前照片读取失败，无法发起分析。"];
            return;
        }

        [strongSelf.visionService analyzeImageData:imageData localIdentifier:strongSelf.asset.localIdentifier completion:^(SAPhotoClassification * _Nullable classification, NSError * _Nullable error) {
            if (classification != nil) {
                [strongSelf.tagStore saveClassification:classification];
                [strongSelf finishAnalysisWithClassification:classification errorMessage:nil];
            } else {
                [strongSelf finishAnalysisWithClassification:nil errorMessage:error.localizedDescription ?: @"分析失败"];
            }
        }];
    }];
}

/**
 * @brief 完成分析后刷新状态与页面展示。
 * @param classification 分析结果。
 * @param errorMessage 错误文案。
 */
- (void)finishAnalysisWithClassification:(SAPhotoClassification * _Nullable)classification
                            errorMessage:(NSString * _Nullable)errorMessage {
    self.isAnalyzing = NO;
    self.analyzeButton.enabled = YES;
    self.analyzeButton.alpha = 1.0;

    if (classification != nil) {
        [self refreshContent];
        if (self.completionHandler != nil) {
            self.completionHandler();
        }
    } else {
        self.statusLabel.text = errorMessage ?: @"分析失败";
    }
}

/**
 * @brief 读取并压缩当前照片，生成适合发送给模型的 JPEG。
 * @param completion 图片数据回调。
 */
- (void)requestOptimizedImageDataWithCompletion:(void (^)(NSData * _Nullable imageData))completion {
    PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
    options.networkAccessAllowed = YES;
    options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    options.version = PHImageRequestOptionsVersionCurrent;

    [self.imageManager requestImageDataAndOrientationForAsset:self.asset
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
 * @brief 展示简单提示弹窗。
 * @param title 标题。
 * @param message 文案。
 */
- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
