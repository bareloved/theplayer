#import "EssentiaAnalyzer.h"
#include <essentia/algorithmfactory.h>
#include <essentia/essentiamath.h>
#include <essentia/utils/tnt/tnt2essentiautils.h>
#include <cmath>
#include <map>
#include <algorithm>

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

        Algorithm* spectralPeaks = factory.create("SpectralPeaks",
            "minFrequency", 40.0,
            "maxFrequency", 5000.0,
            "magnitudeThreshold", 0.0);
        Algorithm* hpcp = factory.create("HPCP", "size", 12);

        std::vector<Real> peakFreqs, peakMags, hpcpVec;
        spectralPeaks->input("spectrum").set(spectrumVec);
        spectralPeaks->output("frequencies").set(peakFreqs);
        spectralPeaks->output("magnitudes").set(peakMags);

        hpcp->input("frequencies").set(peakFreqs);
        hpcp->input("magnitudes").set(peakMags);
        hpcp->output("hpcp").set(hpcpVec);

        std::vector<std::vector<Real>> allHpcps;

        while (true) {
            frameCutter->compute();
            if (frame.empty()) break;
            windowing->compute();
            spectrum->compute();
            mfcc->compute();
            allMfccs.push_back(mfccCoeffs);
            spectralPeaks->compute();
            hpcp->compute();
            allHpcps.push_back(hpcpVec);
        }

        delete frameCutter;
        delete windowing;
        delete spectrum;
        delete mfcc;
        delete spectralPeaks;
        delete hpcp;

        // Build beat-synchronous features: avg(MFCC + HPCP) between consecutive ticks
        auto frameToTime = [&](size_t i) -> float {
            return (float)(i * 1024) / 44100.0f;
        };

        std::vector<std::vector<Real>> beatFeatures;
        if (!ticks.empty() && allMfccs.size() == allHpcps.size() && allMfccs.size() > 0) {
            size_t frameIdx = 0;
            for (size_t b = 0; b + 1 < ticks.size(); b++) {
                float t0 = (float)ticks[b];
                float t1 = (float)ticks[b + 1];
                std::vector<Real> sumMfcc(allMfccs[0].size(), 0.0);
                std::vector<Real> sumHpcp(allHpcps[0].size(), 0.0);
                int count = 0;
                while (frameIdx < allMfccs.size() && frameToTime(frameIdx) < t1) {
                    if (frameToTime(frameIdx) >= t0) {
                        for (size_t k = 0; k < sumMfcc.size(); k++) sumMfcc[k] += allMfccs[frameIdx][k];
                        for (size_t k = 0; k < sumHpcp.size(); k++) sumHpcp[k] += allHpcps[frameIdx][k];
                        count++;
                    }
                    frameIdx++;
                }
                if (count > 0) {
                    std::vector<Real> combined;
                    combined.reserve(sumMfcc.size() + sumHpcp.size());
                    for (auto v : sumMfcc) combined.push_back(v / count);
                    for (auto v : sumHpcp) combined.push_back(v / count);
                    beatFeatures.push_back(combined);
                } else {
                    beatFeatures.push_back(std::vector<Real>(sumMfcc.size() + sumHpcp.size(), 0.0));
                }
            }
        }

        // --- Self-similarity matrix (cosine similarity between beat features) ---
        auto cosineSim = [](const std::vector<Real>& a, const std::vector<Real>& b) -> float {
            Real dot = 0, na = 0, nb = 0;
            for (size_t i = 0; i < a.size(); i++) {
                dot += a[i] * b[i];
                na += a[i] * a[i];
                nb += b[i] * b[i];
            }
            if (na == 0 || nb == 0) return 0;
            return (float)(dot / (std::sqrt(na) * std::sqrt(nb)));
        };

        size_t N = beatFeatures.size();
        std::vector<std::vector<float>> SSM(N, std::vector<float>(N, 0.0f));
        for (size_t i = 0; i < N; i++) {
            for (size_t j = i; j < N; j++) {
                float s = cosineSim(beatFeatures[i], beatFeatures[j]);
                SSM[i][j] = s;
                SSM[j][i] = s;
            }
        }

        // --- Foote novelty curve via checkerboard kernel along diagonal ---
        int K = std::min((int)16, (int)(N / 4));
        std::vector<float> novelty(N, 0.0f);
        if (K >= 2 && N > (size_t)(2 * K)) {
            for (size_t t = K; t + K < N; t++) {
                float pos = 0, neg = 0;
                for (int di = -K; di < 0; di++) {
                    for (int dj = -K; dj < 0; dj++) {
                        pos += SSM[t + di][t + dj];
                    }
                }
                for (int di = 0; di < K; di++) {
                    for (int dj = 0; dj < K; dj++) {
                        pos += SSM[t + di][t + dj];
                    }
                }
                for (int di = -K; di < 0; di++) {
                    for (int dj = 0; dj < K; dj++) {
                        neg += SSM[t + di][t + dj];
                    }
                }
                for (int di = 0; di < K; di++) {
                    for (int dj = -K; dj < 0; dj++) {
                        neg += SSM[t + di][t + dj];
                    }
                }
                novelty[t] = (pos - neg);
            }
        }

        // --- Pick peaks (adaptive threshold) and convert to time boundaries ---
        std::vector<float> noveltyBoundaries;
        if (!novelty.empty()) {
            Real meanN = 0, stdN = 0;
            int nz = 0;
            for (auto v : novelty) if (v != 0) { meanN += v; nz++; }
            if (nz > 0) meanN /= nz;
            for (auto v : novelty) if (v != 0) stdN += (v - meanN) * (v - meanN);
            if (nz > 1) stdN = std::sqrt(stdN / nz);
            Real threshold = meanN + 0.5 * stdN;

            int minDistance = std::max(K, 4);
            int lastPeak = -minDistance;
            for (int t = 1; t + 1 < (int)novelty.size(); t++) {
                if (novelty[t] > threshold &&
                    novelty[t] >= novelty[t - 1] &&
                    novelty[t] >= novelty[t + 1] &&
                    t - lastPeak >= minDistance) {
                    noveltyBoundaries.push_back((float)ticks[t]);
                    lastPeak = t;
                }
            }
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

        for (float t : noveltyBoundaries) {
            if (t > 0 && t < audioDuration) {
                boundaries.push_back(t);
            }
        }

        // Fallback: if SBic found fewer than 3 boundaries, create segments
        // based on bar structure (every 8 or 16 bars depending on song length)
        if (boundaries.size() < 3 && bpm > 0 && !ticks.empty()) {
            boundaries.clear();
            boundaries.push_back(0);

            float beatsPerBar = 4.0f;
            float barDuration = beatsPerBar * (60.0f / bpm);
            int totalBars = (int)(audioDuration / barDuration);

            // Choose segment size: 16 bars for long songs, 8 for short
            int barsPerSection = totalBars > 32 ? 16 : 8;

            for (int bar = barsPerSection; bar < totalBars; bar += barsPerSection) {
                float t = bar * barDuration;
                // Snap to nearest beat
                float bestTick = t;
                float bestDist = 999.0f;
                for (Real tick : ticks) {
                    float dist = fabsf((float)tick - t);
                    if (dist < bestDist) {
                        bestDist = dist;
                        bestTick = (float)tick;
                    }
                }
                if (bestTick > 0 && bestTick < audioDuration - barDuration) {
                    boundaries.push_back(bestTick);
                }
            }
        }

        boundaries.push_back(audioDuration);

        // --- Per-segment mean feature vectors ---
        size_t segCount = boundaries.size() - 1;
        std::vector<std::vector<Real>> segMeans(segCount);
        if (!beatFeatures.empty()) {
            for (size_t s = 0; s < segCount; s++) {
                float t0 = boundaries[s];
                float t1 = boundaries[s + 1];
                std::vector<Real> sum(beatFeatures[0].size(), 0.0);
                int count = 0;
                for (size_t b = 0; b + 1 < ticks.size() && b < beatFeatures.size(); b++) {
                    float bt = (float)ticks[b];
                    if (bt >= t0 && bt < t1) {
                        for (size_t k = 0; k < sum.size(); k++) sum[k] += beatFeatures[b][k];
                        count++;
                    }
                }
                if (count > 0) {
                    for (auto& v : sum) v /= count;
                }
                segMeans[s] = sum;
            }
        }

        // --- Agglomerative clustering by cosine similarity (threshold 0.85) ---
        std::vector<int> cluster(segCount, -1);
        int nextCluster = 0;
        for (size_t i = 0; i < segCount; i++) {
            if (cluster[i] >= 0) continue;
            cluster[i] = nextCluster;
            for (size_t j = i + 1; j < segCount; j++) {
                if (cluster[j] >= 0) continue;
                if (cosineSim(segMeans[i], segMeans[j]) >= 0.85f) {
                    cluster[j] = nextCluster;
                }
            }
            nextCluster++;
        }

        // --- Heuristic mapping cluster → human label ---
        std::map<int, int> clusterCounts;
        for (int c : cluster) clusterCounts[c]++;
        int chorusCluster = -1;
        int maxCount = 1;
        for (auto& kv : clusterCounts) {
            if (kv.second > maxCount) { maxCount = kv.second; chorusCluster = kv.first; }
        }

        int verseCluster = -1;
        int verseCount = 1;
        for (auto& kv : clusterCounts) {
            if (kv.first == chorusCluster) continue;
            if (kv.second > verseCount) { verseCount = kv.second; verseCluster = kv.first; }
        }

        NSMutableArray<NSString*>* heuristicLabels = [NSMutableArray arrayWithCapacity:segCount];
        for (size_t i = 0; i < segCount; i++) {
            NSString* label;
            int c = cluster[i];
            bool unique = (clusterCounts[c] == 1);
            if (c == chorusCluster && chorusCluster >= 0) {
                label = @"Chorus";
            } else if (c == verseCluster && verseCluster >= 0) {
                label = @"Verse";
            } else if (i == 0 && unique) {
                label = @"Intro";
            } else if (i == segCount - 1 && unique) {
                label = @"Outro";
            } else if (unique) {
                label = @"Bridge";
            } else {
                label = [NSString stringWithFormat:@"Section %zu", i + 1];
            }
            [heuristicLabels addObject:label];
        }

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
            NSString *label = i < heuristicLabels.count ? heuristicLabels[i] : [NSString stringWithFormat:@"Section %zu", i + 1];
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
