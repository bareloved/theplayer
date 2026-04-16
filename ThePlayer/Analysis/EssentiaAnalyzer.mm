#import "EssentiaAnalyzer.h"

// Stub implementation — replace with real Essentia calls when the library is built and linked.
// Build Essentia for macOS, copy libessentia.a + headers into Vendor/essentia/,
// add HEADER_SEARCH_PATHS and LIBRARY_SEARCH_PATHS to project.yml, then replace this file.

@implementation EssentiaSection
@end

@implementation EssentiaResult
@end

@implementation EssentiaAnalyzerObjC

- (nullable EssentiaResult *)analyzeFileAtPath:(NSString *)path
                                         error:(NSError **)error {
    if (error) {
        *error = [NSError errorWithDomain:@"EssentiaAnalyzer"
                                     code:-1
                                 userInfo:@{NSLocalizedDescriptionKey:
                                    @"Essentia is not yet integrated. Using mock analyzer."}];
    }
    return nil;
}

@end
