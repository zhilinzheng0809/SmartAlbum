#import "SAPhotoGridCell.h"

@interface SAPhotoGridCell ()

@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIView *overlayView;
@property (nonatomic, strong) UIView *analyzingOverlayView;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicatorView;
@property (nonatomic, strong) UILabel *analyzingLabel;
@property (nonatomic, strong) UIView *selectionBadgeView;
@property (nonatomic, strong) UIImageView *selectionCheckmarkView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;

@end

@implementation SAPhotoGridCell

/**
 * @brief 初始化照片宫格单元格。
 * @param frame 单元格布局范围。
 * @return 单元格实例。
 */
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupViews];
    }
    return self;
}

/**
 * @brief 重用前重置界面内容。
 */
- (void)prepareForReuse {
    [super prepareForReuse];
    self.imageView.image = nil;
    self.titleLabel.text = @"";
    self.subtitleLabel.text = @"";
    [self setShowsAnalyzingState:NO];
    self.selected = NO;
}

/**
 * @brief 配置单元格展示内容。
 * @param image 缩略图。
 * @param title 主标题文案。
 * @param subtitle 副标题文案。
 */
- (void)configureWithImage:(UIImage *)image
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle {
    self.imageView.image = image;
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
}

/**
 * @brief 控制单元格是否展示“分析中”遮罩。
 * @param shows 是否展示分析状态。
 */
- (void)setShowsAnalyzingState:(BOOL)shows {
    self.analyzingOverlayView.hidden = !shows;
    if (shows) {
        [self.activityIndicatorView startAnimating];
    } else {
        [self.activityIndicatorView stopAnimating];
    }
}

/**
 * @brief 根据选中状态更新多选管理时的视觉反馈。
 * @param selected 当前是否选中。
 */
- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    self.contentView.layer.borderWidth = selected ? 3.0 : 0.0;
    self.contentView.layer.borderColor = selected ? [UIColor systemBlueColor].CGColor : UIColor.clearColor.CGColor;
    self.selectionBadgeView.hidden = !selected;
}

/**
 * @brief 构建单元格视图层级与样式。
 */
- (void)setupViews {
    self.contentView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.contentView.layer.cornerRadius = 12.0;
    self.contentView.layer.masksToBounds = YES;

    self.imageView = [[UIImageView alloc] init];
    self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.imageView.contentMode = UIViewContentModeScaleAspectFill;
    self.imageView.clipsToBounds = YES;

    self.overlayView = [[UIView alloc] init];
    self.overlayView.translatesAutoresizingMaskIntoConstraints = NO;
    self.overlayView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];

    self.analyzingOverlayView = [[UIView alloc] init];
    self.analyzingOverlayView.translatesAutoresizingMaskIntoConstraints = NO;
    self.analyzingOverlayView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
    self.analyzingOverlayView.hidden = YES;

    self.activityIndicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.activityIndicatorView.translatesAutoresizingMaskIntoConstraints = NO;
    self.activityIndicatorView.color = [UIColor whiteColor];

    self.analyzingLabel = [[UILabel alloc] init];
    self.analyzingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.analyzingLabel.text = @"分析中";
    self.analyzingLabel.textColor = [UIColor whiteColor];
    self.analyzingLabel.font = [UIFont boldSystemFontOfSize:14];

    self.selectionBadgeView = [[UIView alloc] init];
    self.selectionBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
    self.selectionBadgeView.backgroundColor = [UIColor systemBlueColor];
    self.selectionBadgeView.layer.cornerRadius = 14.0;
    self.selectionBadgeView.hidden = YES;

    self.selectionCheckmarkView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark"]];
    self.selectionCheckmarkView.translatesAutoresizingMaskIntoConstraints = NO;
    self.selectionCheckmarkView.tintColor = [UIColor whiteColor];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    self.titleLabel.numberOfLines = 2;

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.85];
    self.subtitleLabel.font = [UIFont systemFontOfSize:10];
    self.subtitleLabel.numberOfLines = 2;

    [self.contentView addSubview:self.imageView];
    [self.contentView addSubview:self.overlayView];
    [self.contentView addSubview:self.analyzingOverlayView];
    [self.contentView addSubview:self.selectionBadgeView];
    [self.overlayView addSubview:self.titleLabel];
    [self.overlayView addSubview:self.subtitleLabel];
    [self.analyzingOverlayView addSubview:self.activityIndicatorView];
    [self.analyzingOverlayView addSubview:self.analyzingLabel];
    [self.selectionBadgeView addSubview:self.selectionCheckmarkView];

    [NSLayoutConstraint activateConstraints:@[
        [self.imageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [self.imageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.imageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.imageView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

        [self.overlayView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.overlayView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.overlayView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

        [self.analyzingOverlayView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [self.analyzingOverlayView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.analyzingOverlayView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.analyzingOverlayView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

        [self.selectionBadgeView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
        [self.selectionBadgeView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
        [self.selectionBadgeView.widthAnchor constraintEqualToConstant:28],
        [self.selectionBadgeView.heightAnchor constraintEqualToConstant:28],
        [self.selectionCheckmarkView.centerXAnchor constraintEqualToAnchor:self.selectionBadgeView.centerXAnchor],
        [self.selectionCheckmarkView.centerYAnchor constraintEqualToAnchor:self.selectionBadgeView.centerYAnchor],

        [self.activityIndicatorView.centerXAnchor constraintEqualToAnchor:self.analyzingOverlayView.centerXAnchor],
        [self.activityIndicatorView.centerYAnchor constraintEqualToAnchor:self.analyzingOverlayView.centerYAnchor constant:-10],
        [self.analyzingLabel.topAnchor constraintEqualToAnchor:self.activityIndicatorView.bottomAnchor constant:8],
        [self.analyzingLabel.centerXAnchor constraintEqualToAnchor:self.analyzingOverlayView.centerXAnchor],

        [self.titleLabel.topAnchor constraintEqualToAnchor:self.overlayView.topAnchor constant:8],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.overlayView.leadingAnchor constant:8],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.overlayView.trailingAnchor constant:-8],

        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.overlayView.leadingAnchor constant:8],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.overlayView.trailingAnchor constant:-8],
        [self.subtitleLabel.bottomAnchor constraintEqualToAnchor:self.overlayView.bottomAnchor constant:-8]
    ]];
}

@end
