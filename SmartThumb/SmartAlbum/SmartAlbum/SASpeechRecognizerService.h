#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SASpeechRecognizerService : NSObject

@property (nonatomic, assign, readonly) BOOL isRecognizing;

/**
 * @brief 使用指定语言环境初始化语音识别服务。
 * @param localeIdentifier 语言环境标识，如 zh-CN。
 * @return 语音识别服务实例。
 */
- (instancetype)initWithLocaleIdentifier:(NSString *)localeIdentifier;

/**
 * @brief 切换语音识别状态，并通过回调返回结果与状态变化。
 * @param resultHandler 识别文本回调。
 * @param stateHandler 识别状态变化回调。
 * @param errorHandler 异常信息回调。
 */
- (void)toggleRecognitionWithResultHandler:(void (^)(NSString *recognizedText))resultHandler
                              stateHandler:(void (^)(BOOL isRecognizing))stateHandler
                              errorHandler:(void (^)(NSString *message))errorHandler;

/**
 * @brief 主动停止当前语音识别任务。
 */
- (void)stopRecognition;

@end

NS_ASSUME_NONNULL_END
