#import "SAQwenVLService.h"
#import "SAPhotoClassification.h"
#import <UIKit/UIKit.h>

static NSInteger const SAQwenHTTPMaximumConnectionsPerHost = 10;

@implementation SAQwenAnalyzeItem

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

@interface SAQwenVLService ()

@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *modelName;
@property (nonatomic, strong) NSURL *endpointURL;
@property (nonatomic, strong) NSURLSession *session;

@end

@implementation SAQwenVLService

/**
 * @brief 初始化服务并从本地配置文件加载模型参数。
 * @return 服务实例。
 */
- (instancetype)init {
    self = [super init];
    if (self) {
        [self loadConfiguration];
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        configuration.HTTPMaximumConnectionsPerHost = SAQwenHTTPMaximumConnectionsPerHost;
        configuration.timeoutIntervalForRequest = 120;
        configuration.timeoutIntervalForResource = 180;
        _session = [NSURLSession sessionWithConfiguration:configuration];
    }
    return self;
}

/**
 * @brief 判断当前服务是否已完成本地密钥配置。
 * @return 是否可调用远程模型。
 */
- (BOOL)isConfigured {
    return self.apiKey.length > 0 && self.endpointURL != nil && self.modelName.length > 0;
}

/**
 * @brief 返回当前配置状态说明。
 * @return 配置说明文案。
 */
- (NSString *)configurationMessage {
    if ([self isConfigured]) {
        return @"Qwen 配置已完成。";
    }
    return @"未找到 SASecrets.plist 或缺少 Qwen 配置，请先填写本地 API Key。";
}

/**
 * @brief 调用 qwen-vl-max 对图片进行分析并返回标签结果。
 * @param imageData JPEG 图片数据。
 * @param localIdentifier 相册资源唯一标识。
 * @param completion 分析完成回调。
 */
- (void)analyzeImageData:(NSData *)imageData
         localIdentifier:(NSString *)localIdentifier
              completion:(SAQwenAnalyzeCompletion)completion {
    SAQwenAnalyzeItem *item = [[SAQwenAnalyzeItem alloc] initWithImageData:imageData localIdentifier:localIdentifier];
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

        NSError *fallbackError = [NSError errorWithDomain:@"SAQwenVLService"
                                                     code:1008
                                                 userInfo:@{NSLocalizedDescriptionKey: @"模型未返回该照片的分析结果。"}];
        completion(nil, fallbackError);
    }];
}

/**
 * @brief 使用 qwen-vl-max 对多张图片进行批量分析，并按资源标识返回逐张结果。
 * @param items 批量分析请求项数组。
 * @param completion 分析完成回调。
 */
- (void)analyzeBatchItems:(NSArray<SAQwenAnalyzeItem *> *)items
               completion:(SAQwenBatchAnalyzeCompletion)completion {
    if (![self isConfigured]) {
        NSError *error = [NSError errorWithDomain:@"SAQwenVLService"
                                             code:1001
                                         userInfo:@{NSLocalizedDescriptionKey: [self configurationMessage]}];
        completion(@{}, @[], error);
        return;
    }

    NSArray<SAQwenAnalyzeItem *> *validItems = [self normalizedAnalyzeItems:items];
    if (validItems.count == 0) {
        NSError *error = [NSError errorWithDomain:@"SAQwenVLService"
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

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.endpointURL];
    request.HTTPMethod = @"POST";
    request.HTTPBody = bodyData;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", self.apiKey] forHTTPHeaderField:@"Authorization"];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (error != nil) {
            NSMutableArray<NSString *> *allIdentifiers = [NSMutableArray array];
            for (SAQwenAnalyzeItem *item in validItems) {
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
- (NSDictionary<NSString *, id> *)requestPayloadWithAnalyzeItems:(NSArray<SAQwenAnalyzeItem *> *)items {
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

    for (SAQwenAnalyzeItem *item in items) {
        [userContent addObject:@{
            @"type": @"image_url",
            @"image_url": @{
                @"url": [self dataURLStringForImageData:item.imageData]
            }
        }];
    }

    return @{
        @"model": self.modelName,
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
                                                                        items:(NSArray<SAQwenAnalyzeItem *> *)items
                                                                        error:(NSError * __autoreleasing *)error {
    if (data.length == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"SAQwenVLService"
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
            *error = [NSError errorWithDomain:@"SAQwenVLService"
                                         code:1003
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return @{};
    }

    NSArray *choices = root[@"choices"];
    if (![choices isKindOfClass:[NSArray class]] || choices.count == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"SAQwenVLService"
                                         code:1004
                                     userInfo:@{NSLocalizedDescriptionKey: @"模型未返回可用结果。"}];
        }
        return @{};
    }

    NSDictionary *message = [choices.firstObject objectForKey:@"message"];
    NSString *content = [message objectForKey:@"content"];
    if (![content isKindOfClass:[NSString class]] || content.length == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"SAQwenVLService"
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
            *error = [NSError errorWithDomain:@"SAQwenVLService"
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

        SAQwenAnalyzeItem *item = items[(NSUInteger)index];
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
- (NSArray<SAQwenAnalyzeItem *> *)normalizedAnalyzeItems:(NSArray<SAQwenAnalyzeItem *> *)items {
    NSMutableArray<SAQwenAnalyzeItem *> *validItems = [NSMutableArray array];
    for (SAQwenAnalyzeItem *item in items) {
        if (![item isKindOfClass:[SAQwenAnalyzeItem class]]) {
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
- (NSArray<NSString *> *)failedIdentifiersForItems:(NSArray<SAQwenAnalyzeItem *> *)items
                                   classifications:(NSDictionary<NSString *, SAPhotoClassification *> *)classifications {
    NSMutableArray<NSString *> *failedIdentifiers = [NSMutableArray array];
    for (SAQwenAnalyzeItem *item in items) {
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
 * @brief 从应用包中读取本地 Secrets 配置。
 */
- (void)loadConfiguration {
    NSURL *fileURL = [[NSBundle mainBundle] URLForResource:@"SASecrets" withExtension:@"plist"];
    NSDictionary *dictionary = [NSDictionary dictionaryWithContentsOfURL:fileURL];

    NSString *apiKey = [dictionary[@"QwenAPIKey"] isKindOfClass:[NSString class]] ? dictionary[@"QwenAPIKey"] : @"";
    NSString *modelName = [dictionary[@"QwenModel"] isKindOfClass:[NSString class]] ? dictionary[@"QwenModel"] : @"qwen-vl-max";
    NSString *endpoint = [dictionary[@"QwenEndpoint"] isKindOfClass:[NSString class]] ? dictionary[@"QwenEndpoint"] : @"https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions";

    if ([apiKey hasPrefix:@"YOUR_"]) {
        apiKey = @"";
    }

    _apiKey = [apiKey copy];
    _modelName = [modelName copy];
    _endpointURL = [NSURL URLWithString:endpoint];
}

@end
