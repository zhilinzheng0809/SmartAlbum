#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

NS_ASSUME_NONNULL_BEGIN

@class PHCachingImageManager;
@class SATagStore;
@class SAQwenVLService;

extern NSString * const SAAutoAnalysisProgressDidChangeNotification;
extern NSString * const SAAutoAnalysisIsRunningKey;
extern NSString * const SAAutoAnalysisEnabledKey;
extern NSString * const SAAutoAnalysisTotalCountKey;
extern NSString * const SAAutoAnalysisCompletedCountKey;
extern NSString * const SAAutoAnalysisFailedCountKey;
extern NSString * const SAAutoAnalysisPendingCountKey;
extern NSString * const SAAutoAnalysisCurrentIdentifierKey;
extern NSString * const SAAutoAnalysisStatusTextKey;

@interface SAAutoAnalysisManager : NSObject

@property (nonatomic, assign, readonly) BOOL autoAnalysisEnabled;
@property (nonatomic, assign, readonly) BOOL isAnalyzing;

/**
 * @brief 返回自动分析管理器单例。
 * @return 管理器实例。
 */
+ (instancetype)sharedManager;

/**
 * @brief 注入自动分析所需依赖，并准备监听图库变化。
 * @param imageManager 图片读取管理器。
 * @param tagStore 标签存储对象。
 * @param qwenService 大模型分析服务。
 */
- (void)configureWithImageManager:(PHCachingImageManager *)imageManager
                         tagStore:(SATagStore *)tagStore
                      qwenService:(SAQwenVLService *)qwenService;

/**
 * @brief 判断当前是否应该展示首次自动分析提醒。
 * @return 是否需要提醒用户。
 */
- (BOOL)shouldPresentAutoAnalysisPrompt;

/**
 * @brief 标记首次提醒已处理，避免重复弹出。
 */
- (void)markAutoAnalysisPromptHandled;

/**
 * @brief 开启自动分析，并立即将未分析照片加入后台任务。
 */
- (void)enableAutoAnalysisAndStart;

/**
 * @brief 返回当前自动分析进度快照。
 * @return 进度信息字典。
 */
- (NSDictionary<NSString *, id> *)progressSnapshot;

@end

NS_ASSUME_NONNULL_END
