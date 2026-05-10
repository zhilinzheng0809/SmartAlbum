#import "SAAlbumListCell.h"

@interface SAAlbumListCell ()

@property (nonatomic, strong) UIImageView *coverImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIImageView *chevronImageView;

@end

@implementation SAAlbumListCell

/**
 * @brief 初始化相册列表单元格。
 * @param style 单元格样式。
 * @param reuseIdentifier 复用标识。
 * @return 单元格对象。
 */
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
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
    self.coverImageView.image = nil;
    self.titleLabel.text = @"";
    self.subtitleLabel.text = @"";
}

/**
 * @brief 配置相册列表单元格。
 * @param image 相册封面图。
 * @param title 相册标题。
 * @param subtitle 相册副标题。
 */
- (void)configureWithImage:(UIImage *)image
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle {
    self.coverImageView.image = image;
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
}

/**
 * @brief 构建单元格界面。
 */
- (void)setupViews {
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.accessoryType = UITableViewCellAccessoryNone;

    self.coverImageView = [[UIImageView alloc] init];
    self.coverImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.coverImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.coverImageView.clipsToBounds = YES;
    self.coverImageView.layer.cornerRadius = 10.0;
    self.coverImageView.backgroundColor = [UIColor tertiarySystemFillColor];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    self.titleLabel.textColor = [UIColor labelColor];

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.font = [UIFont systemFontOfSize:13];
    self.subtitleLabel.textColor = [UIColor secondaryLabelColor];
    self.subtitleLabel.numberOfLines = 2;

    self.chevronImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    self.chevronImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chevronImageView.tintColor = [UIColor tertiaryLabelColor];

    [self.contentView addSubview:self.coverImageView];
    [self.contentView addSubview:self.titleLabel];
    [self.contentView addSubview:self.subtitleLabel];
    [self.contentView addSubview:self.chevronImageView];

    [NSLayoutConstraint activateConstraints:@[
        [self.coverImageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.coverImageView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.coverImageView.widthAnchor constraintEqualToConstant:68],
        [self.coverImageView.heightAnchor constraintEqualToConstant:68],

        [self.chevronImageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.chevronImageView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [self.chevronImageView.widthAnchor constraintEqualToConstant:10],

        [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:18],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.coverImageView.trailingAnchor constant:14],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.chevronImageView.leadingAnchor constant:-12],

        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:6],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
        [self.subtitleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-18]
    ]];
}

@end
