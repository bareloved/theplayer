#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EssentiaSection : NSObject
@property (nonatomic, copy) NSString *label;
@property (nonatomic) float startTime;
@property (nonatomic) float endTime;
@property (nonatomic) NSInteger startBeat;
@property (nonatomic) NSInteger endBeat;
@property (nonatomic) NSInteger colorIndex;
@end

@interface EssentiaResult : NSObject
@property (nonatomic) float bpm;
@property (nonatomic) NSInteger downbeatOffset;
@property (nonatomic, strong) NSArray<NSNumber *> *beats;
@property (nonatomic, strong) NSArray<EssentiaSection *> *sections;
@end

@interface EssentiaAnalyzerObjC : NSObject
- (nullable EssentiaResult *)analyzeFileAtPath:(NSString *)path
                                         error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
