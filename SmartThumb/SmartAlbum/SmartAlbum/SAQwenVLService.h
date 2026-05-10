#import <Foundation/Foundation.h>

@class SAPhotoClassification;

NS_ASSUME_NONNULL_BEGIN

typedef void(^SAQwenAnalyzeCompletion)(SAPhotoClassification * _Nullable classification, NSError * _Nullable error);

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

@end

NS_ASSUME_NONNULL_END
