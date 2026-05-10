#import "SAPhotoClassification.h"

@implementation SAPhotoClassification

/**
 * @brief 使用基础字段初始化照片标签结果。
 * @param localIdentifier 相册资源唯一标识。
 * @param summary 照片摘要描述。
 * @param tags 照片标签数组。
 * @param analyzedAt 分析完成时间。
 * @return 照片标签结果对象。
 */
- (instancetype)initWithLocalIdentifier:(NSString *)localIdentifier
                                summary:(NSString *)summary
                                   tags:(NSArray<NSString *> *)tags
                             analyzedAt:(NSDate *)analyzedAt {
    self = [super init];
    if (self) {
        _localIdentifier = [localIdentifier copy];
        _summary = [summary copy];
        _tags = [self normalizedTags:tags];
        _analyzedAt = analyzedAt;
    }
    return self;
}

/**
 * @brief 将对象转换为可持久化字典。
 * @return 字典结构。
 */
- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    return @{
        @"localIdentifier": self.localIdentifier ?: @"",
        @"summary": self.summary ?: @"",
        @"tags": self.tags ?: @[],
        @"analyzedAt": @([self.analyzedAt timeIntervalSince1970])
    };
}

/**
 * @brief 通过字典恢复照片标签结果。
 * @param dictionary 持久化字典。
 * @return 照片标签结果对象。
 */
+ (instancetype)classificationWithDictionary:(NSDictionary<NSString *, id> *)dictionary {
    NSString *localIdentifier = dictionary[@"localIdentifier"];
    NSString *summary = dictionary[@"summary"];
    NSArray<NSString *> *tags = dictionary[@"tags"];
    NSNumber *timestamp = dictionary[@"analyzedAt"];
    if (![localIdentifier isKindOfClass:[NSString class]] ||
        ![summary isKindOfClass:[NSString class]] ||
        ![tags isKindOfClass:[NSArray class]] ||
        ![timestamp isKindOfClass:[NSNumber class]]) {
        return nil;
    }

    NSDate *analyzedAt = [NSDate dateWithTimeIntervalSince1970:timestamp.doubleValue];
    return [[SAPhotoClassification alloc] initWithLocalIdentifier:localIdentifier
                                                          summary:summary
                                                             tags:tags
                                                       analyzedAt:analyzedAt];
}

/**
 * @brief 判断当前结果是否匹配搜索关键字。
 * @param keyword 用户输入的搜索词。
 * @return 是否匹配。
 */
- (BOOL)matchesKeyword:(NSString *)keyword {
    NSString *trimmed = [keyword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return YES;
    }

    if ([[self.summary lowercaseString] containsString:[trimmed lowercaseString]]) {
        return YES;
    }

    for (NSString *tag in self.tags) {
        if ([[tag lowercaseString] containsString:[trimmed lowercaseString]]) {
            return YES;
        }
    }
    return NO;
}

/**
 * @brief 对标签数组进行去重和空值过滤。
 * @param tags 原始标签。
 * @return 清洗后的标签数组。
 */
- (NSArray<NSString *> *)normalizedTags:(NSArray<NSString *> *)tags {
    NSMutableOrderedSet<NSString *> *set = [NSMutableOrderedSet orderedSet];
    for (id item in tags) {
        if (![item isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *tag = [(NSString *)item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (tag.length > 0) {
            [set addObject:tag];
        }
    }
    return set.array;
}

@end
