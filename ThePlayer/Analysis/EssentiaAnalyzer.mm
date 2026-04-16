#import "EssentiaAnalyzer.h"
#include <essentia/algorithmfactory.h>
#include <essentia/essentiamath.h>
#include <essentia/utils/tnt/tnt2essentiautils.h>

using namespace essentia;
using namespace essentia::standard;

@implementation EssentiaSection
@end

@implementation EssentiaResult
@end

@implementation EssentiaAnalyzerObjC

- (nullable EssentiaResult *)analyzeFileAtPath:(NSString *)path
                                         error:(NSError **)error {
    @try {
        essentia::init();

        AlgorithmFactory& factory = AlgorithmFactory::instance();

        // Load audio as mono 44100Hz
        Algorithm* loader = factory.create("MonoLoader",
            "filename", std::string([path UTF8String]),
            "sampleRate", 44100);

        std::vector<Real> audio;
        loader->output("audio").set(audio);
        loader->compute();
        delete loader;

        if (audio.empty()) {
            essentia::shutdown();
            if (error) {
                *error = [NSError errorWithDomain:@"EssentiaAnalyzer"
                                             code:-2
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to load audio"}];
            }
            return nil;
        }

        // --- BPM and beat detection ---
        Algorithm* rhythm = factory.create("RhythmExtractor2013");
        Real bpm;
        std::vector<Real> ticks;
        Real confidence;
        std::vector<Real> estimates;
        std::vector<Real> bpmIntervals;

        rhythm->input("signal").set(audio);
        rhythm->output("bpm").set(bpm);
        rhythm->output("ticks").set(ticks);
        rhythm->output("confidence").set(confidence);
        rhythm->output("estimates").set(estimates);
        rhythm->output("bpmIntervals").set(bpmIntervals);
        rhythm->compute();
        delete rhythm;

        // --- Section segmentation via SBic ---
        // First compute MFCCs for the segmenter
        Algorithm* frameCutter = factory.create("FrameCutter",
            "frameSize", 2048,
            "hopSize", 1024);
        Algorithm* windowing = factory.create("Windowing", "type", std::string("hann"));
        Algorithm* spectrum = factory.create("Spectrum");
        Algorithm* mfcc = factory.create("MFCC");

        std::vector<std::vector<Real>> allMfccs;
        std::vector<Real> frame, windowedFrame, spectrumVec, mfccBands, mfccCoeffs;

        frameCutter->input("signal").set(audio);
        frameCutter->output("frame").set(frame);

        windowing->input("frame").set(frame);
        windowing->output("frame").set(windowedFrame);

        spectrum->input("frame").set(windowedFrame);
        spectrum->output("spectrum").set(spectrumVec);

        mfcc->input("spectrum").set(spectrumVec);
        mfcc->output("bands").set(mfccBands);
        mfcc->output("mfcc").set(mfccCoeffs);

        while (true) {
            frameCutter->compute();
            if (frame.empty()) break;
            windowing->compute();
            spectrum->compute();
            mfcc->compute();
            allMfccs.push_back(mfccCoeffs);
        }

        delete frameCutter;
        delete windowing;
        delete spectrum;
        delete mfcc;

        // Run SBic segmentation
        std::vector<Real> segmentation;

        if (allMfccs.size() > 10) {
            // Convert vector<vector<Real>> to TNT::Array2D<Real> for SBic
            int rows = (int)allMfccs.size();
            int cols = (int)allMfccs[0].size();
            TNT::Array2D<Real> features(rows, cols);
            for (int r = 0; r < rows; r++) {
                for (int c = 0; c < cols; c++) {
                    features[r][c] = allMfccs[r][c];
                }
            }

            Algorithm* sbic = factory.create("SBic",
                "minLength", 10,
                "size1", 300,
                "size2", 200,
                "inc1", 60,
                "inc2", 20,
                "cpw", 1.5);

            sbic->input("features").set(features);
            sbic->output("segmentation").set(segmentation);
            sbic->compute();
            delete sbic;
        }

        // --- Build result ---
        EssentiaResult *result = [[EssentiaResult alloc] init];
        result.bpm = bpm;

        // Beats
        NSMutableArray<NSNumber *> *beatArray = [NSMutableArray arrayWithCapacity:ticks.size()];
        for (Real tick : ticks) {
            [beatArray addObject:@(tick)];
        }
        result.beats = beatArray;

        // Sections from segmentation boundaries
        float audioDuration = (float)audio.size() / 44100.0f;
        NSMutableArray<EssentiaSection *> *sectionArray = [NSMutableArray new];

        std::vector<float> boundaries;
        boundaries.push_back(0);
        // SBic returns boundaries in frame indices — convert to seconds
        float hopSizeSeconds = 1024.0f / 44100.0f;
        for (Real seg : segmentation) {
            float timeInSeconds = (float)seg * hopSizeSeconds;
            if (timeInSeconds > 0 && timeInSeconds < audioDuration) {
                boundaries.push_back(timeInSeconds);
            }
        }
        boundaries.push_back(audioDuration);

        // Label assignment — use simple pattern based on section count
        NSArray *labelPatterns = @[@"Intro", @"Verse", @"Chorus", @"Verse", @"Chorus",
                                   @"Bridge", @"Chorus", @"Outro"];

        for (size_t i = 0; i < boundaries.size() - 1; i++) {
            EssentiaSection *section = [[EssentiaSection alloc] init];
            section.startTime = boundaries[i];
            section.endTime = boundaries[i + 1];

            // Find nearest beats for start/end
            int startBeat = 0, endBeat = 0;
            for (size_t b = 0; b < ticks.size(); b++) {
                if (ticks[b] <= boundaries[i] + 0.05f) startBeat = (int)b;
                if (ticks[b] <= boundaries[i + 1] + 0.05f) endBeat = (int)b;
            }
            section.startBeat = startBeat;
            section.endBeat = endBeat;

            // Assign color index based on label pattern (similar sections share colors)
            NSString *label;
            if (i < labelPatterns.count) {
                label = labelPatterns[i];
            } else {
                label = [NSString stringWithFormat:@"Section %zu", i + 1];
            }
            section.label = label;

            // Color by label name for consistency
            NSDictionary *colorMap = @{@"Intro": @0, @"Verse": @1, @"Chorus": @2,
                                       @"Bridge": @3, @"Outro": @0};
            NSNumber *colorIdx = colorMap[label];
            section.colorIndex = colorIdx ? colorIdx.integerValue : (NSInteger)(i % 8);

            [sectionArray addObject:section];
        }
        result.sections = sectionArray;

        essentia::shutdown();
        return result;

    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"EssentiaAnalyzer"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                        [NSString stringWithFormat:@"Analysis failed: %@", exception.reason]}];
        }
        return nil;
    }
}

@end
