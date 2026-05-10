#import <Foundation/Foundation.h>

@class SAPhotoClassification;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SAVisionProviderType) {
    SAVisionProviderTypeQwen = 0,
    SAVisionProviderTypeDeepSeek = 1
};

typedef void(^SAVisionAnalyzeCompletion)(SAPhotoClassification * _Nullable classification, NSError * _Nullable error);
typedef void(^SAVisionBatchAnalyzeCompletion)(NSDictionary<NSString *, SAPhotoClassification *> *classifications, NSArray<NSString *> *failedIdentifiers, NSError * _Nullable error);

@interface SAVisionAnalyzeItem : NSObject

@property (nonatomic, copy, readonly) NSString *localIdentifier;
@property (nonatomic, copy, readonly) NSData *imageData;

/**
 * @brief 使用图片数据和资源标识初始化一条批量分析请求项。
 * @param imageData JPEG 图片数据。
 * @param localIdentifier 相册资源唯一标识。
 * @return 请求项对象。
 */
- (instancetype)initWithImageData:(NSData *)imageData
                  localIdentifier:(NSString *)localIdentifier;

@end

@interface SAVisionLLMService : NSObject

@property (nonatomic, assign, readonly) SAVisionProviderType currentProviderType;

/**
 * @brief 判断当前服务是否已完成当前模型的本地密钥配置。
 * @return 是否可调用远程模型。
 */
- (BOOL)isConfigured;

/**
 * @brief 返回当前模型配置状态说明。
 * @return 配置说明文案。
 */
- (NSString *)configurationMessage;

/**
 * @brief 判断当前模型是否支持照片分析所需的图片输入能力。
 * @return 是否支持图片分析。
 */
- (BOOL)supportsPhotoAnalysis;

/**
 * @brief 返回当前模型照片分析可用性说明。
 * @return 可用性说明文案。
 */
- (NSString *)photoAnalysisAvailabilityMessage;

/**
 * @brief 返回当前模型的展示名称。
 * @return 展示名称。
 */
- (NSString *)providerDisplayName;

/**
 * @brief 返回当前模型的短标题，适合用于按钮展示。
 * @return 短标题。
 */
- (NSString *)providerShortTitle;

/**
 * @brief 返回当前模型标识。
 * @return 模型标识字符串。
 */
- (NSString *)providerModelName;

/**
 * @brief 切换当前使用的视觉分析模型。
 * @param providerType 目标模型类型。
 */
- (void)switchProviderType:(SAVisionProviderType)providerType;

/**
 * @brief 调用当前模型对图片进行分析并返回标签结果。
 * @param imageData JPEG 图片数据。
 * @param localIdentifier 相册资源唯一标识。
 * @param completion 分析完成回调。
 */
- (void)analyzeImageData:(NSData *)imageData
         localIdentifier:(NSString *)localIdentifier
              completion:(SAVisionAnalyzeCompletion)completion;

/**
 * @brief 使用当前模型对多张图片进行批量分析，并按资源标识返回逐张结果。
 * @param items 批量分析请求项数组。
 * @param completion 分析完成回调。
 */
- (void)analyzeBatchItems:(NSArray<SAVisionAnalyzeItem *> *)items
               completion:(SAVisionBatchAnalyzeCompletion)completion;

@end

NS_ASSUME_NONNULL_END
