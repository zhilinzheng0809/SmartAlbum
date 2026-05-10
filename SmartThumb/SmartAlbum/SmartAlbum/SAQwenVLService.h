#import <Foundation/Foundation.h>

@class SAPhotoClassification;

NS_ASSUME_NONNULL_BEGIN

typedef void(^SAQwenAnalyzeCompletion)(SAPhotoClassification * _Nullable classification, NSError * _Nullable error);
typedef void(^SAQwenBatchAnalyzeCompletion)(NSDictionary<NSString *, SAPhotoClassification *> *classifications, NSArray<NSString *> *failedIdentifiers, NSError * _Nullable error);

@interface SAQwenAnalyzeItem : NSObject

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

@interface SAQwenVLService : NSObject

/**
 * @brief 判断当前服务是否已完成本地密钥配置。
 * @return 是否可调用远程模型。
 */
- (BOOL)isConfigured;

/**
 * @brief 返回当前配置状态说明。
 * @return 配置说明文案。
 */
- (NSString *)configurationMessage;

/**
 * @brief 调用 qwen-vl-max 对图片进行分析并返回标签结果。
 * @param imageData JPEG 图片数据。
 * @param localIdentifier 相册资源唯一标识。
 * @param completion 分析完成回调。
 */
- (void)analyzeImageData:(NSData *)imageData
         localIdentifier:(NSString *)localIdentifier
              completion:(SAQwenAnalyzeCompletion)completion;

/**
 * @brief 使用 qwen-vl-max 对多张图片进行批量分析，并按资源标识返回逐张结果。
 * @param items 批量分析请求项数组。
 * @param completion 分析完成回调。
 */
- (void)analyzeBatchItems:(NSArray<SAQwenAnalyzeItem *> *)items
               completion:(SAQwenBatchAnalyzeCompletion)completion;

@end

NS_ASSUME_NONNULL_END
