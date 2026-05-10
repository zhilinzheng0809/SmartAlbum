#import "SAVisionLLMService.h"
#import "SAPhotoClassification.h"

static NSInteger const SAVisionHTTPMaximumConnectionsPerHost = 10;
static NSString * const SAVisionSelectedProviderDefaultsKey = @"SAVisionSelectedProviderDefaultsKey";

@interface SAVisionProviderConfiguration : NSObject

@property (nonatomic, assign) SAVisionProviderType providerType;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *shortTitle;
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *modelName;
@property (nonatomic, strong) NSURL *endpointURL;
@property (nonatomic, assign) BOOL supportsImageInput;

@end

@implementation SAVisionProviderConfiguration
@end

@implementation SAVisionAnalyzeItem

/**
 * @brief 使用图片数据和资源标识初始化一条批量分析请求项。
 * @param imageData JPEG 图片数据。
 * @param localIdentifier 相册资源唯一标识。
 * @return 请求项对象。
 */
- (instancetype)initWithImageData:(NSData *)imageData
                  localIdentifier:(NSString *)localIdentifier {
    self = [super init];
    if (self) {
        _imageData = [imageData copy];
        _localIdentifier = [localIdentifier copy];
    }
    return self;
}

@end

@interface SAVisionLLMService ()

@property (nonatomic, assign, readwrite) SAVisionProviderType currentProviderType;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSDictionary<NSNumber *, SAVisionProviderConfiguration *> *providerConfigurations;

@end

@implementation SAVisionLLMService

/**
 * @brief 初始化服务并从本地配置文件加载模型参数。
 * @return 服务实例。
 */
- (instancetype)init {
    self = [super init];
    if (self) {
        [self loadConfiguration];
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        configuration.HTTPMaximumConnectionsPerHost = SAVisionHTTPMaximumConnectionsPerHost;
        configuration.timeoutIntervalForRequest = 120;
        configuration.timeoutIntervalForResource = 180;
        _session = [NSURLSession sessionWithConfiguration:configuration];
    }
    return self;
}

/**
 * @brief 判断当前服务是否已完成当前模型的本地密钥配置。
 * @return 是否可调用远程模型。
 */
- (BOOL)isConfigured {
    SAVisionProviderConfiguration *configuration = [self currentProviderConfiguration];
    return configuration.apiKey.length > 0 && configuration.endpointURL != nil && configuration.modelName.length > 0;
}

/**
 * @brief 返回当前模型配置状态说明。
 * @return 配置说明文案。
 */
- (NSString *)configurationMessage {
    if ([self isConfigured]) {
        return [NSString stringWithFormat:@"%@ 配置已完成。", self.providerDisplayName];
    }
    return [NSString stringWithFormat:@"未找到 SASecrets.plist 或缺少 %@ 配置，请先填写对应 API Key。", self.providerDisplayName];
}

/**
 * @brief 判断当前模型是否支持照片分析所需的图片输入能力。
 * @return 是否支持图片分析。
 */
- (BOOL)supportsPhotoAnalysis {
    return [self currentProviderConfiguration].supportsImageInput;
}

/**
 * @brief 返回当前模型照片分析可用性说明。
 * @return 可用性说明文案。
 */
- (NSString *)photoAnalysisAvailabilityMessage {
    if (![self isConfigured]) {
        return [self configurationMessage];
    }

    if ([self supportsPhotoAnalysis]) {
        return [NSString stringWithFormat:@"%@ 当前可用于照片分析。", self.providerDisplayName];
    }

    return [NSString stringWithFormat:@"%@（%@）当前官方 API 不支持 `image_url` 图片输入，因此暂时不能用于照片分析。请切换到阿里云百炼 Qwen，或等待 DeepSeek 官方开放多模态图片接口后再启用。",
            [self providerDisplayName],
            [self providerModelName]];
}

/**
 * @brief 返回当前模型的展示名称。
 * @return 展示名称。
 */
- (NSString *)providerDisplayName {
    return [self currentProviderConfiguration].displayName ?: @"视觉模型";
}

/**
 * @brief 返回当前模型的短标题，适合用于按钮展示。
 * @return 短标题。
 */
- (NSString *)providerShortTitle {
    return [self currentProviderConfiguration].shortTitle ?: @"模型";
}

/**
 * @brief 返回当前模型标识。
 * @return 模型标识字符串。
 */
- (NSString *)providerModelName {
    return [self currentProviderConfiguration].modelName ?: @"";
}

/**
 * @brief 切换当前使用的视觉分析模型。
 * @param providerType 目标模型类型。
 */
- (void)switchProviderType:(SAVisionProviderType)providerType {
    if (self.providerConfigurations[@(providerType)] == nil) {
        return;
    }
    self.currentProviderType = providerType;
    [[NSUserDefaults standardUserDefaults] setInteger:providerType forKey:SAVisionSelectedProviderDefaultsKey];
}

/**
 * @brief 调用当前模型对图片进行分析并返回标签结果。
 * @param imageData JPEG 图片数据。
 * @param localIdentifier 相册资源唯一标识。
 * @param completion 分析完成回调。
 */
- (void)analyzeImageData:(NSData *)imageData
         localIdentifier:(NSString *)localIdentifier
              completion:(SAVisionAnalyzeCompletion)completion {
    SAVisionAnalyzeItem *item = [[SAVisionAnalyzeItem alloc] initWithImageData:imageData localIdentifier:localIdentifier];
    [self analyzeBatchItems:@[item] completion:^(NSDictionary<NSString *,SAPhotoClassification *> * _Nonnull classifications, NSArray<NSString *> * _Nonnull failedIdentifiers, NSError * _Nullable error) {
        SAPhotoClassification *classification = classifications[localIdentifier];
        if (classification != nil) {
            completion(classification, nil);
            return;
        }

        if (error != nil) {
            completion(nil, error);
            return;
        }

        NSError *fallbackError = [NSError errorWithDomain:@"SAVisionLLMService"
                                                     code:1008
                                                 userInfo:@{NSLocalizedDescriptionKey: @"模型未返回该照片的分析结果。"}];
        completion(nil, fallbackError);
    }];
}

/**
 * @brief 使用当前模型对多张图片进行批量分析，并按资源标识返回逐张结果。
 * @param items 批量分析请求项数组。
 * @param completion 分析完成回调。
 */
- (void)analyzeBatchItems:(NSArray<SAVisionAnalyzeItem *> *)items
               completion:(SAVisionBatchAnalyzeCompletion)completion {
    if (![self isConfigured]) {
        NSError *error = [NSError errorWithDomain:@"SAVisionLLMService"
                                             code:1001
                                         userInfo:@{NSLocalizedDescriptionKey: [self configurationMessage]}];
        completion(@{}, @[], error);
        return;
    }

    if (![self supportsPhotoAnalysis]) {
        NSError *error = [NSError errorWithDomain:@"SAVisionLLMService"
                                             code:1009
                                         userInfo:@{NSLocalizedDescriptionKey: [self photoAnalysisAvailabilityMessage]}];
        NSMutableArray<NSString *> *allIdentifiers = [NSMutableArray array];
        for (SAVisionAnalyzeItem *item in items) {
            if (item.localIdentifier.length > 0) {
                [allIdentifiers addObject:item.localIdentifier];
            }
        }
        completion(@{}, allIdentifiers.copy, error);
        return;
    }

    NSArray<SAVisionAnalyzeItem *> *validItems = [self normalizedAnalyzeItems:items];
    if (validItems.count == 0) {
        NSError *error = [NSError errorWithDomain:@"SAVisionLLMService"
                                             code:1006
                                         userInfo:@{NSLocalizedDescriptionKey: @"没有可提交给模型的照片。"}];
        completion(@{}, @[], error);
        return;
    }

    NSDictionary *payload = [self requestPayloadWithAnalyzeItems:validItems];
    NSError *serializationError = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&serializationError];
    if (bodyData == nil || serializationError != nil) {
        completion(@{}, @[], serializationError);
        return;
    }

    SAVisionProviderConfiguration *providerConfiguration = [self currentProviderConfiguration];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:providerConfiguration.endpointURL];
    request.HTTPMethod = @"POST";
    request.HTTPBody = bodyData;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", providerConfiguration.apiKey] forHTTPHeaderField:@"Authorization"];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (error != nil) {
            NSMutableArray<NSString *> *allIdentifiers = [NSMutableArray array];
            for (SAVisionAnalyzeItem *item in validItems) {
                if (item.localIdentifier.length > 0) {
                    [allIdentifiers addObject:item.localIdentifier];
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(@{}, allIdentifiers.copy, error);
            });
            return;
        }

        NSError *parseError = nil;
        NSDictionary<NSString *, SAPhotoClassification *> *classifications = [strongSelf parseBatchResponseData:data
                                                                                                           items:validItems
                                                                                                           error:&parseError];
        NSArray<NSString *> *failedIdentifiers = [strongSelf failedIdentifiersForItems:validItems
                                                                      classifications:classifications];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(classifications, failedIdentifiers, parseError);
        });
    }];
    [task resume];
}

/**
 * @brief 生成符合 OpenAI 兼容接口的多图批量请求体。
 * @param items 批量请求项数组。
 * @return 请求体字典。
 */
- (NSDictionary<NSString *, id> *)requestPayloadWithAnalyzeItems:(NSArray<SAVisionAnalyzeItem *> *)items {
    NSString *instruction = [NSString stringWithFormat:
                             @"请按输入顺序分析以下 %lu 张照片，并严格输出 JSON 对象，不要输出 Markdown。"
                             @"JSON 格式为：{\"results\":[{\"index\":0,\"summary\":\"一句中文摘要\",\"tags\":[\"标签1\",\"标签2\"]}]}"
                             @"要求：1. 每张照片都返回一项结果，index 必须与图片顺序一致；2. tags 使用简短中文标签；3. 不要包含人名猜测、品牌臆测或隐私信息；4. tags 数量控制在 3 到 8 个；5. 如果某张图片信息不足，也要返回简短 summary 和尽量稳妥的标签。",
                             (unsigned long)items.count];
    NSMutableArray<NSDictionary<NSString *, id> *> *userContent = [NSMutableArray array];
    [userContent addObject:@{
        @"type": @"text",
        @"text": instruction
    }];

    for (SAVisionAnalyzeItem *item in items) {
        [userContent addObject:@{
            @"type": @"image_url",
            @"image_url": @{
                @"url": [self dataURLStringForImageData:item.imageData]
            }
        }];
    }

    SAVisionProviderConfiguration *providerConfiguration = [self currentProviderConfiguration];
    return @{
        @"model": providerConfiguration.modelName,
        @"messages": @[
            @{
                @"role": @"system",
                @"content": @"你是一个智能相册图像标注助手，擅长生成稳定、简洁、适合搜索的中文标签。"
            },
            @{
                @"role": @"user",
                @"content": userContent.copy
            }
        ],
        @"temperature": @0.2,
        @"max_tokens": @(MAX(600, items.count * 220)),
        @"response_format": @{
            @"type": @"json_object"
        }
    };
}

/**
 * @brief 将批量接口返回解析为多张照片标签结果。
 * @param data 响应数据。
 * @param items 批量请求项数组。
 * @param error 输出错误对象。
 * @return 资源标识到照片标签结果的映射。
 */
- (NSDictionary<NSString *, SAPhotoClassification *> *)parseBatchResponseData:(NSData *)data
                                                                        items:(NSArray<SAVisionAnalyzeItem *> *)items
                                                                        error:(NSError * __autoreleasing *)error {
    if (data.length == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"SAVisionLLMService"
                                         code:1002
                                     userInfo:@{NSLocalizedDescriptionKey: @"模型返回为空。"}];
        }
        return @{};
    }

    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![root isKindOfClass:[NSDictionary class]]) {
        return @{};
    }

    NSDictionary *apiError = root[@"error"];
    if ([apiError isKindOfClass:[NSDictionary class]]) {
        NSString *message = apiError[@"message"] ?: @"模型调用失败。";
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"SAVisionLLMService"
                                         code:1003
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return @{};
    }

    NSArray *choices = root[@"choices"];
    if (![choices isKindOfClass:[NSArray class]] || choices.count == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"SAVisionLLMService"
                                         code:1004
                                     userInfo:@{NSLocalizedDescriptionKey: @"模型未返回可用结果。"}];
        }
        return @{};
    }

    NSDictionary *message = [choices.firstObject objectForKey:@"message"];
    NSString *content = [message objectForKey:@"content"];
    if (![content isKindOfClass:[NSString class]] || content.length == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"SAVisionLLMService"
                                         code:1005
                                     userInfo:@{NSLocalizedDescriptionKey: @"模型返回内容格式异常。"}];
        }
        return @{};
    }

    NSData *jsonData = [content dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:error];
    if (![payload isKindOfClass:[NSDictionary class]]) {
        return @{};
    }

    NSArray *results = payload[@"results"];
    if (![results isKindOfClass:[NSArray class]]) {
        if (items.count == 1) {
            SAPhotoClassification *classification = [self classificationFromDictionary:payload localIdentifier:items.firstObject.localIdentifier];
            return classification != nil ? @{items.firstObject.localIdentifier: classification} : @{};
        }

        if (error != NULL) {
            *error = [NSError errorWithDomain:@"SAVisionLLMService"
                                         code:1007
                                     userInfo:@{NSLocalizedDescriptionKey: @"模型返回缺少 results 数组。"}];
        }
        return @{};
    }

    NSMutableDictionary<NSString *, SAPhotoClassification *> *classifications = [NSMutableDictionary dictionary];
    for (NSDictionary *result in results) {
        if (![result isKindOfClass:[NSDictionary class]]) {
            continue;
        }

        NSNumber *indexNumber = result[@"index"];
        if (![indexNumber isKindOfClass:[NSNumber class]]) {
            continue;
        }

        NSInteger index = indexNumber.integerValue;
        if (index < 0 || index >= (NSInteger)items.count) {
            continue;
        }

        SAVisionAnalyzeItem *item = items[(NSUInteger)index];
        SAPhotoClassification *classification = [self classificationFromDictionary:result localIdentifier:item.localIdentifier];
        if (classification != nil) {
            classifications[item.localIdentifier] = classification;
        }
    }
    return classifications.copy;
}

/**
 * @brief 将图片二进制转换为可直接传给多模态接口的 Data URL。
 * @param imageData 图片二进制。
 * @return Data URL 字符串。
 */
- (NSString *)dataURLStringForImageData:(NSData *)imageData {
    NSString *base64 = [imageData base64EncodedStringWithOptions:0];
    return [NSString stringWithFormat:@"data:image/jpeg;base64,%@", base64];
}

/**
 * @brief 过滤出可提交给模型的有效请求项，避免空数据进入请求体。
 * @param items 原始请求项数组。
 * @return 清洗后的请求项数组。
 */
- (NSArray<SAVisionAnalyzeItem *> *)normalizedAnalyzeItems:(NSArray<SAVisionAnalyzeItem *> *)items {
    NSMutableArray<SAVisionAnalyzeItem *> *validItems = [NSMutableArray array];
    for (SAVisionAnalyzeItem *item in items) {
        if (![item isKindOfClass:[SAVisionAnalyzeItem class]]) {
            continue;
        }

        if (item.localIdentifier.length == 0 || item.imageData.length == 0) {
            continue;
        }
        [validItems addObject:item];
    }
    return validItems.copy;
}

/**
 * @brief 根据批量解析结果计算失败的资源标识列表。
 * @param items 原始请求项数组。
 * @param classifications 成功解析的结果映射。
 * @return 未成功生成结果的资源标识数组。
 */
- (NSArray<NSString *> *)failedIdentifiersForItems:(NSArray<SAVisionAnalyzeItem *> *)items
                                   classifications:(NSDictionary<NSString *, SAPhotoClassification *> *)classifications {
    NSMutableArray<NSString *> *failedIdentifiers = [NSMutableArray array];
    for (SAVisionAnalyzeItem *item in items) {
        if (classifications[item.localIdentifier] == nil) {
            [failedIdentifiers addObject:item.localIdentifier];
        }
    }
    return failedIdentifiers.copy;
}

/**
 * @brief 将模型输出字典转换为单张照片标签结果。
 * @param dictionary 模型返回字典。
 * @param localIdentifier 相册资源唯一标识。
 * @return 照片标签结果对象。
 */
- (SAPhotoClassification * _Nullable)classificationFromDictionary:(NSDictionary<NSString *, id> *)dictionary
                                                  localIdentifier:(NSString *)localIdentifier {
    NSString *summary = [dictionary[@"summary"] isKindOfClass:[NSString class]] ? dictionary[@"summary"] : @"";
    NSArray<NSString *> *tags = [dictionary[@"tags"] isKindOfClass:[NSArray class]] ? dictionary[@"tags"] : @[];
    if (summary.length == 0 && tags.count == 0) {
        return nil;
    }

    return [[SAPhotoClassification alloc] initWithLocalIdentifier:localIdentifier
                                                          summary:summary
                                                             tags:tags
                                                       analyzedAt:[NSDate date]];
}

/**
 * @brief 返回当前选中的模型配置。
 * @return 模型配置对象。
 */
- (SAVisionProviderConfiguration *)currentProviderConfiguration {
    SAVisionProviderConfiguration *configuration = self.providerConfigurations[@(self.currentProviderType)];
    if (configuration != nil) {
        return configuration;
    }
    return self.providerConfigurations[@(SAVisionProviderTypeQwen)];
}

/**
 * @brief 从应用包中读取本地 Secrets 配置并初始化各模型参数。
 */
- (void)loadConfiguration {
    NSURL *fileURL = [[NSBundle mainBundle] URLForResource:@"SASecrets" withExtension:@"plist"];
    NSDictionary *dictionary = [NSDictionary dictionaryWithContentsOfURL:fileURL];

    SAVisionProviderConfiguration *qwenConfiguration = [[SAVisionProviderConfiguration alloc] init];
    qwenConfiguration.providerType = SAVisionProviderTypeQwen;
    qwenConfiguration.displayName = @"阿里云百炼 Qwen";
    qwenConfiguration.shortTitle = @"Qwen";
    qwenConfiguration.apiKey = [self normalizedAPIKeyFromDictionary:dictionary key:@"QwenAPIKey"];
    qwenConfiguration.modelName = [self normalizedStringFromDictionary:dictionary key:@"QwenModel" fallback:@"qwen-vl-max"];
    qwenConfiguration.supportsImageInput = YES;
    qwenConfiguration.endpointURL = [NSURL URLWithString:[self normalizedStringFromDictionary:dictionary
                                                                                           key:@"QwenEndpoint"
                                                                                      fallback:@"https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"]];

    SAVisionProviderConfiguration *deepSeekConfiguration = [[SAVisionProviderConfiguration alloc] init];
    deepSeekConfiguration.providerType = SAVisionProviderTypeDeepSeek;
    deepSeekConfiguration.displayName = @"DeepSeek V4";
    deepSeekConfiguration.shortTitle = @"DeepSeek";
    deepSeekConfiguration.apiKey = [self normalizedAPIKeyFromDictionary:dictionary key:@"DeepSeekAPIKey"];
    deepSeekConfiguration.modelName = [self normalizedStringFromDictionary:dictionary key:@"DeepSeekModel" fallback:@"deepseek-v4-pro"];
    deepSeekConfiguration.supportsImageInput = NO;
    deepSeekConfiguration.endpointURL = [NSURL URLWithString:[self normalizedStringFromDictionary:dictionary
                                                                                               key:@"DeepSeekEndpoint"
                                                                                          fallback:@"https://api.deepseek.com/chat/completions"]];

    self.providerConfigurations = @{
        @(SAVisionProviderTypeQwen): qwenConfiguration,
        @(SAVisionProviderTypeDeepSeek): deepSeekConfiguration
    };

    NSString *defaultProvider = [self normalizedStringFromDictionary:dictionary key:@"DefaultVisionProvider" fallback:@"qwen"];
    SAVisionProviderType configuredProviderType = [defaultProvider.lowercaseString containsString:@"deepseek"] ? SAVisionProviderTypeDeepSeek : SAVisionProviderTypeQwen;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:SAVisionSelectedProviderDefaultsKey] != nil) {
        self.currentProviderType = (SAVisionProviderType)[defaults integerForKey:SAVisionSelectedProviderDefaultsKey];
    } else {
        self.currentProviderType = configuredProviderType;
    }
}

/**
 * @brief 读取字符串配置并提供兜底值。
 * @param dictionary 配置字典。
 * @param key 配置键名。
 * @param fallback 兜底值。
 * @return 标准化后的字符串。
 */
- (NSString *)normalizedStringFromDictionary:(NSDictionary *)dictionary key:(NSString *)key fallback:(NSString *)fallback {
    NSString *value = [dictionary[key] isKindOfClass:[NSString class]] ? dictionary[key] : @"";
    return value.length > 0 ? value : fallback;
}

/**
 * @brief 读取 API Key 配置并清理占位值。
 * @param dictionary 配置字典。
 * @param key 配置键名。
 * @return 标准化后的 API Key。
 */
- (NSString *)normalizedAPIKeyFromDictionary:(NSDictionary *)dictionary key:(NSString *)key {
    NSString *value = [dictionary[key] isKindOfClass:[NSString class]] ? dictionary[key] : @"";
    if ([value hasPrefix:@"YOUR_"]) {
        return @"";
    }
    return value;
}

@end
