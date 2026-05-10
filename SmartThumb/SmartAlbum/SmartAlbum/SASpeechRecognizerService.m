#import "SASpeechRecognizerService.h"
#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>

@interface SASpeechRecognizerService ()

@property (nonatomic, strong) SFSpeechRecognizer *speechRecognizer;
@property (nonatomic, strong) AVAudioEngine *audioEngine;
@property (nonatomic, strong, nullable) SFSpeechAudioBufferRecognitionRequest *recognitionRequest;
@property (nonatomic, strong, nullable) SFSpeechRecognitionTask *recognitionTask;
@property (nonatomic, copy, nullable) void (^resultHandler)(NSString *recognizedText);
@property (nonatomic, copy, nullable) void (^stateHandler)(BOOL isRecognizing);
@property (nonatomic, copy, nullable) void (^errorHandler)(NSString *message);
@property (nonatomic, assign, readwrite) BOOL isRecognizing;
@property (nonatomic, assign) BOOL suppressRecognitionErrorCallback;

@end

@implementation SASpeechRecognizerService

/**
 * @brief 使用指定语言环境初始化语音识别服务。
 * @param localeIdentifier 语言环境标识，如 zh-CN。
 * @return 语音识别服务实例。
 */
- (instancetype)initWithLocaleIdentifier:(NSString *)localeIdentifier {
    self = [super init];
    if (self) {
        NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:localeIdentifier.length > 0 ? localeIdentifier : @"zh-CN"];
        _speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:locale];
        _audioEngine = [[AVAudioEngine alloc] init];
    }
    return self;
}

/**
 * @brief 对象释放前终止仍在运行的识别任务。
 */
- (void)dealloc {
    [self stopRecognition];
}

/**
 * @brief 切换语音识别状态，并通过回调返回结果与状态变化。
 * @param resultHandler 识别文本回调。
 * @param stateHandler 识别状态变化回调。
 * @param errorHandler 异常信息回调。
 */
- (void)toggleRecognitionWithResultHandler:(void (^)(NSString *recognizedText))resultHandler
                              stateHandler:(void (^)(BOOL isRecognizing))stateHandler
                              errorHandler:(void (^)(NSString *message))errorHandler {
    self.resultHandler = resultHandler;
    self.stateHandler = stateHandler;
    self.errorHandler = errorHandler;

    if (self.isRecognizing) {
        [self stopRecognition];
        return;
    }

    [self requestSpeechAuthorizationWithCompletion:^(BOOL granted, NSString * _Nullable message) {
        if (!granted) {
            [self notifyErrorWithMessage:message ?: @"语音识别权限未开启。"];
            return;
        }

        [self requestMicrophoneAuthorizationWithCompletion:^(BOOL microphoneGranted, NSString * _Nullable microphoneMessage) {
            if (!microphoneGranted) {
                [self notifyErrorWithMessage:microphoneMessage ?: @"麦克风权限未开启。"];
                return;
            }

            [self startRecognition];
        }];
    }];
}

/**
 * @brief 主动停止当前语音识别任务。
 */
- (void)stopRecognition {
    [self stopRecognitionSilently:YES];
}

/**
 * @brief 停止当前识别任务，并可控制是否吞掉停止过程中产生的系统错误回调。
 * @param silently 是否静默停止。
 */
- (void)stopRecognitionSilently:(BOOL)silently {
    self.suppressRecognitionErrorCallback = silently;

    if (self.audioEngine.isRunning) {
        [self.audioEngine stop];
    }

    AVAudioInputNode *inputNode = self.audioEngine.inputNode;
    if (inputNode != nil) {
        [inputNode removeTapOnBus:0];
    }

    [self.recognitionRequest endAudio];
    [self.recognitionTask cancel];
    self.recognitionRequest = nil;
    self.recognitionTask = nil;
    self.isRecognizing = NO;
    [self notifyStateChanged:NO];

    NSError *sessionError = nil;
    [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&sessionError];
}

/**
 * @brief 请求语音识别权限。
 * @param completion 权限结果回调。
 */
- (void)requestSpeechAuthorizationWithCompletion:(void (^)(BOOL granted, NSString * _Nullable message))completion {
    SFSpeechRecognizerAuthorizationStatus status = [SFSpeechRecognizer authorizationStatus];
    switch (status) {
        case SFSpeechRecognizerAuthorizationStatusAuthorized:
            completion(YES, nil);
            return;
        case SFSpeechRecognizerAuthorizationStatusDenied:
            completion(NO, @"请在系统设置中开启语音识别权限。");
            return;
        case SFSpeechRecognizerAuthorizationStatusRestricted:
            completion(NO, @"当前设备不支持语音识别权限。");
            return;
        case SFSpeechRecognizerAuthorizationStatusNotDetermined:
            [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus authStatus) {
                BOOL granted = (authStatus == SFSpeechRecognizerAuthorizationStatusAuthorized);
                NSString *message = granted ? nil : @"请在系统设置中开启语音识别权限。";
                [self dispatchToMain:^{
                    completion(granted, message);
                }];
            }];
            return;
    }
}

/**
 * @brief 请求麦克风权限。
 * @param completion 权限结果回调。
 */
- (void)requestMicrophoneAuthorizationWithCompletion:(void (^)(BOOL granted, NSString * _Nullable message))completion {
    [AVAudioApplication requestRecordPermissionWithCompletionHandler:^(BOOL granted) {
        NSString *message = granted ? nil : @"请在系统设置中开启麦克风权限。";
        [self dispatchToMain:^{
            completion(granted, message);
        }];
    }];
}

/**
 * @brief 启动语音识别并实时输出识别文本。
 */
- (void)startRecognition {
    if (self.speechRecognizer == nil || !self.speechRecognizer.isAvailable) {
        [self notifyErrorWithMessage:@"当前语音识别暂不可用，请稍后重试。"];
        return;
    }

    [self stopRecognitionSilently:YES];
    self.suppressRecognitionErrorCallback = NO;

    NSError *audioSessionError = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryRecord mode:AVAudioSessionModeMeasurement options:AVAudioSessionCategoryOptionDuckOthers error:&audioSessionError];
    [session setActive:YES withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&audioSessionError];
    if (audioSessionError != nil) {
        [self notifyErrorWithMessage:@"无法启动麦克风，请稍后重试。"];
        return;
    }

    self.recognitionRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    self.recognitionRequest.shouldReportPartialResults = YES;

    AVAudioInputNode *inputNode = self.audioEngine.inputNode;
    if (inputNode == nil) {
        [self notifyErrorWithMessage:@"当前设备无法读取麦克风输入。"];
        return;
    }

    __weak typeof(self) weakSelf = self;
    self.recognitionTask = [self.speechRecognizer recognitionTaskWithRequest:self.recognitionRequest resultHandler:^(SFSpeechRecognitionResult * _Nullable result, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        if (result != nil) {
            [strongSelf notifyRecognizedText:result.bestTranscription.formattedString ?: @""];
        }

        if (error != nil || result.isFinal) {
            BOOL shouldShowError = (error != nil && !strongSelf.suppressRecognitionErrorCallback);
            [strongSelf stopRecognitionSilently:YES];
            if (shouldShowError) {
                [strongSelf notifyErrorWithMessage:error.localizedDescription ?: @"语音识别失败，请稍后重试。"];
            }
        }
    }];

    AVAudioFormat *recordingFormat = [inputNode outputFormatForBus:0];
    [inputNode installTapOnBus:0 bufferSize:1024 format:recordingFormat block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
        [self.recognitionRequest appendAudioPCMBuffer:buffer];
    }];

    [self.audioEngine prepare];
    NSError *engineError = nil;
    [self.audioEngine startAndReturnError:&engineError];
    if (engineError != nil) {
        [self stopRecognition];
        [self notifyErrorWithMessage:@"无法开始语音识别，请稍后重试。"];
        return;
    }

    self.isRecognizing = YES;
    [self notifyStateChanged:YES];
}

/**
 * @brief 将识别文本回调到主线程。
 * @param recognizedText 识别出的文本。
 */
- (void)notifyRecognizedText:(NSString *)recognizedText {
    [self dispatchToMain:^{
        if (self.resultHandler != nil) {
            self.resultHandler(recognizedText);
        }
    }];
}

/**
 * @brief 将识别状态回调到主线程。
 * @param isRecognizing 当前是否正在识别。
 */
- (void)notifyStateChanged:(BOOL)isRecognizing {
    [self dispatchToMain:^{
        if (self.stateHandler != nil) {
            self.stateHandler(isRecognizing);
        }
    }];
}

/**
 * @brief 将错误信息回调到主线程。
 * @param message 错误提示。
 */
- (void)notifyErrorWithMessage:(NSString *)message {
    [self dispatchToMain:^{
        if (self.errorHandler != nil) {
            self.errorHandler(message);
        }
    }];
}

/**
 * @brief 确保 UI 相关回调在主线程执行。
 * @param block 待执行代码块。
 */
- (void)dispatchToMain:(dispatch_block_t)block {
    if (block == nil) {
        return;
    }

    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

@end
