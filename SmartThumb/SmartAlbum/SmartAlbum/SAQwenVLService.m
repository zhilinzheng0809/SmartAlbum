#import "SAQwenVLService.h"
#import "SAPhotoClassification.h"
#import <UIKit/UIKit.h>

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
    if (![self isConfigured]) {
        NSError *error = [NSError errorWithDomain:@"SAQwenVLService"
                                             code:1001
                                         userInfo:@{NSLocalizedDescriptionKey: [self configurationMessage]}];
        completion(nil, error);
        return;
    }

    NSString *dataURL = [self dataURLStringForImageData:imageData];
    NSDictionary *payload = [self requestPayloadWithDataURL:dataURL];
    NSError *serializationError = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&serializationError];
    if (bodyData == nil || serializationError != nil) {
        completion(nil, serializationError);
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
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, error);
            });
            return;
        }

        NSError *parseError = nil;
        SAPhotoClassification *classification = [strongSelf parseResponseData:data
                                                              localIdentifier:localIdentifier
                                                                        error:&parseError];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(classification, parseError);
        });
    }];
    [task resume];
}

/**
 * @brief 生成符合 OpenAI 兼容接口的多模态请求体。
 * @param dataURL 图片的 Base64 Data URL。
 * @return 请求体字典。
 */
- (NSDictionary<NSString *, id> *)requestPayloadWithDataURL:(NSString *)dataURL {
    NSString *instruction = @"请分析这张照片，并严格输出 JSON 对象，不要输出 Markdown。JSON 格式为："
    @"{\"summary\":\"一句中文摘要\",\"tags\":[\"标签1\",\"标签2\",\"标签3\"]}。"
    @"要求：1. tags 使用简短中文标签；2. 不要包含人名猜测、品牌臆测或隐私信息；3. tags 数量控制在 3 到 8 个。";

    return @{
        @"model": self.modelName,
        @"messages": @[
            @{
                @"role": @"system",
                @"content": @"你是一个智能相册图像标注助手，擅长生成稳定、简洁、适合搜索的中文标签。"
            },
            @{
                @"role": @"user",
                @"content": @[
                    @{
                        @"type": @"text",
                        @"text": instruction
                    },
                    @{
                        @"type": @"image_url",
                        @"image_url": @{
                            @"url": dataURL
                        }
                    }
                ]
            }
        ],
        @"temperature": @0.2,
        @"max_tokens": @500,
        @"response_format": @{
            @"type": @"json_object"
        }
    };
}

/**
 * @brief 将接口返回解析为照片标签结果。
 * @param data 响应数据。
 * @param localIdentifier 相册资源唯一标识。
 * @param error 输出错误对象。
 * @return 照片标签结果。
 */
- (SAPhotoClassification *)parseResponseData:(NSData *)data
                              localIdentifier:(NSString *)localIdentifier
                                        error:(NSError * __autoreleasing *)error {
    if (data.length == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"SAQwenVLService"
                                         code:1002
                                     userInfo:@{NSLocalizedDescriptionKey: @"模型返回为空。"}];
        }
        return nil;
    }

    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![root isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSDictionary *apiError = root[@"error"];
    if ([apiError isKindOfClass:[NSDictionary class]]) {
        NSString *message = apiError[@"message"] ?: @"模型调用失败。";
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"SAQwenVLService"
                                         code:1003
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return nil;
    }

    NSArray *choices = root[@"choices"];
    if (![choices isKindOfClass:[NSArray class]] || choices.count == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"SAQwenVLService"
                                         code:1004
                                     userInfo:@{NSLocalizedDescriptionKey: @"模型未返回可用结果。"}];
        }
        return nil;
    }

    NSDictionary *message = [choices.firstObject objectForKey:@"message"];
    NSString *content = [message objectForKey:@"content"];
    if (![content isKindOfClass:[NSString class]] || content.length == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"SAQwenVLService"
                                         code:1005
                                     userInfo:@{NSLocalizedDescriptionKey: @"模型返回内容格式异常。"}];
        }
        return nil;
    }

    NSData *jsonData = [content dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:error];
    if (![payload isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSString *summary = [payload[@"summary"] isKindOfClass:[NSString class]] ? payload[@"summary"] : @"";
    NSArray<NSString *> *tags = [payload[@"tags"] isKindOfClass:[NSArray class]] ? payload[@"tags"] : @[];
    SAPhotoClassification *classification = [[SAPhotoClassification alloc] initWithLocalIdentifier:localIdentifier
                                                                                            summary:summary
                                                                                               tags:tags
                                                                                         analyzedAt:[NSDate date]];
    return classification;
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
