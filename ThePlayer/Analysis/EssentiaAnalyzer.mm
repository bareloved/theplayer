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

        // --- Onset detection + sample-accurate refinement ---
        // Hop size 512 @ 44.1 kHz → ~11.6 ms detection-function resolution.
        // We then refine each reported onset to the local short-term RMS peak
        // in a ±10 ms window of raw samples.
        std::vector<Real> refinedOnsets;
        {
            const int onsetFrameSize = 1024;
            const int onsetHopSize = 512;
            Algorithm* odFrameCutter = factory.create("FrameCutter",
                "frameSize", onsetFrameSize,
                "hopSize", onsetHopSize);
            Algorithm* odWindowing = factory.create("Windowing",
                "type", std::string("hann"));
            Algorithm* odSpectrum = factory.create("Spectrum");
            Algorithm* onsetDetection = factory.create("OnsetDetection",
                "method", std::string("hfc"),
                "sampleRate", 44100.0);

            std::vector<Real> odFrame, odWindowed, odSpec;
            Real odValue;

            odFrameCutter->input("signal").set(audio);
            odFrameCutter->output("frame").set(odFrame);

            odWindowing->input("frame").set(odFrame);
            odWindowing->output("frame").set(odWindowed);

            odSpectrum->input("frame").set(odWindowed);
            odSpectrum->output("spectrum").set(odSpec);

            onsetDetection->input("spectrum").set(odSpec);
            onsetDetection->output("onsetDetection").set(odValue);

            std::vector<Real> detectionFunction;
            while (true) {
                odFrameCutter->compute();
                if (odFrame.empty()) break;
                odWindowing->compute();
                odSpectrum->compute();
                onsetDetection->compute();
                detectionFunction.push_back(odValue);
            }

            delete odFrameCutter;
            delete odWindowing;
            delete odSpectrum;
            delete onsetDetection;

            // Peak-pick the detection function into onset times.
            std::vector<Real> rawOnsets;
            if (!detectionFunction.empty()) {
                Algorithm* onsets = factory.create("Onsets",
                    "frameRate", 44100.0 / (Real)onsetHopSize);
                // Onsets expects a TNT::Array2D<Real> with rows = detectors, cols = frames.
                TNT::Array2D<Real> detectionMatrix(1, (int)detectionFunction.size());
                for (int i = 0; i < (int)detectionFunction.size(); i++) {
                    detectionMatrix[0][i] = detectionFunction[i];
                }
                std::vector<Real> weights; weights.push_back(1.0);
                onsets->input("detections").set(detectionMatrix);
                onsets->input("weights").set(weights);
                onsets->output("onsets").set(rawOnsets);
                onsets->compute();
                delete onsets;
            }

            // Refine each onset to the local short-term RMS peak within ±10ms.
            const Real sr = 44100.0;
            const int refineRadius = (int)(0.010 * sr); // ±10 ms window
            const int rmsWindow = (int)(0.002 * sr);    // 2 ms RMS window
            for (Real t : rawOnsets) {
                int center = (int)(t * sr);
                int lo = std::max(0, center - refineRadius);
                int hi = std::min((int)audio.size() - 1, center + refineRadius);
                if (hi - lo < rmsWindow) { refinedOnsets.push_back(t); continue; }

                // Slide a 2ms RMS window across [lo, hi] and pick the peak center.
                // Use running sum of squares for O(n) refinement.
                double sumSq = 0.0;
                for (int i = lo; i < lo + rmsWindow && i < (int)audio.size(); i++) {
                    sumSq += (double)audio[i] * (double)audio[i];
                }
                double bestRms = sumSq;
                int bestStart = lo;
                for (int i = lo + 1; i + rmsWindow <= hi; i++) {
                    sumSq -= (double)audio[i - 1] * (double)audio[i - 1];
                    sumSq += (double)audio[i + rmsWindow - 1] * (double)audio[i + rmsWindow - 1];
                    if (sumSq > bestRms) { bestRms = sumSq; bestStart = i; }
                }
                Real refined = (Real)(bestStart + rmsWindow / 2) / sr;
                refinedOnsets.push_back(refined);
            }
        }

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
        std::vector<Real> frameLowEnergy;

        while (true) {
            frameCutter->compute();
            if (frame.empty()) break;
            windowing->compute();
            spectrum->compute();
            // Sum magnitude in the 20-200 Hz band (captures kick-drum downbeats).
            {
                int lowStartBin = (int)std::floor(20.0 * 2048.0 / 44100.0);
                int lowEndBin = (int)std::ceil(200.0 * 2048.0 / 44100.0);
                if (lowEndBin > (int)spectrumVec.size()) lowEndBin = (int)spectrumVec.size();
                Real lowE = 0;
                for (int bn = lowStartBin; bn < lowEndBin; bn++) lowE += spectrumVec[bn];
                frameLowEnergy.push_back(lowE);
            }
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

        // Per-beat low-frequency energy for downbeat heuristic
        auto frameToTimeDB = [](size_t i) -> float {
            return (float)(i * 1024) / 44100.0f;
        };

        std::vector<Real> beatLowEnergy;
        if (!ticks.empty() && !frameLowEnergy.empty()) {
            size_t fi = 0;
            for (size_t b = 0; b + 1 < ticks.size(); b++) {
                float t0 = (float)ticks[b];
                float t1 = (float)ticks[b + 1];
                Real sum = 0;
                int count = 0;
                while (fi < frameLowEnergy.size() && frameToTimeDB(fi) < t1) {
                    if (frameToTimeDB(fi) >= t0) {
                        sum += frameLowEnergy[fi];
                        count++;
                    }
                    fi++;
                }
                beatLowEnergy.push_back(count > 0 ? sum / (Real)count : 0);
            }
        }

        // Downbeat heuristic: for each offset 0..3, sum low-freq energy at beats matching that offset.
        // Pick offset with highest total score.
        int chosenDownbeatOffset = 0;
        if (beatLowEnergy.size() >= 4) {
            Real bestScore = -1;
            for (int offset = 0; offset < 4; offset++) {
                Real score = 0;
                for (size_t b = offset; b < beatLowEnergy.size(); b += 4) {
                    score += beatLowEnergy[b];
                }
                if (score > bestScore) {
                    bestScore = score;
                    chosenDownbeatOffset = offset;
                }
            }
        }

        // Build beat-synchronous features: one combined (for novelty) and one chroma-only (for clustering)
        auto frameToTime = [&](size_t i) -> float {
            return (float)(i * 1024) / 44100.0f;
        };

        std::vector<std::vector<Real>> beatFeaturesCombined;
        std::vector<std::vector<Real>> beatFeaturesChroma;

        if (!ticks.empty() && allMfccs.size() == allHpcps.size() && allMfccs.size() > 0) {
            size_t mfccDim = allMfccs[0].size();   // typically 13
            size_t hpcpDim = allHpcps[0].size();   // 12

            size_t frameIdx = 0;
            for (size_t b = 0; b + 1 < ticks.size(); b++) {
                float t0 = (float)ticks[b];
                float t1 = (float)ticks[b + 1];
                std::vector<Real> sumMfcc(mfccDim, 0.0);
                std::vector<Real> sumHpcp(hpcpDim, 0.0);
                int count = 0;
                while (frameIdx < allMfccs.size() && frameToTime(frameIdx) < t1) {
                    if (frameToTime(frameIdx) >= t0) {
                        for (size_t k = 0; k < mfccDim; k++) sumMfcc[k] += allMfccs[frameIdx][k];
                        for (size_t k = 0; k < hpcpDim; k++) sumHpcp[k] += allHpcps[frameIdx][k];
                        count++;
                    }
                    frameIdx++;
                }

                std::vector<Real> mfccBeat(mfccDim, 0.0), hpcpBeat(hpcpDim, 0.0);
                if (count > 0) {
                    for (size_t k = 0; k < mfccDim; k++) mfccBeat[k] = sumMfcc[k] / count;
                    for (size_t k = 0; k < hpcpDim; k++) hpcpBeat[k] = sumHpcp[k] / count;
                }

                // Combined: drop MFCC[0] (loudness), then concatenate MFCC[1..] + HPCP
                std::vector<Real> combined;
                combined.reserve((mfccDim - 1) + hpcpDim);
                for (size_t k = 1; k < mfccDim; k++) combined.push_back(mfccBeat[k]);
                for (auto v : hpcpBeat) combined.push_back(v);

                beatFeaturesCombined.push_back(combined);
                beatFeaturesChroma.push_back(hpcpBeat);
            }
        }

        // Z-normalize beatFeaturesCombined across beats: per-dimension (column-wise) zero-mean, unit-std
        if (!beatFeaturesCombined.empty()) {
            size_t D = beatFeaturesCombined[0].size();
            size_t M = beatFeaturesCombined.size();
            std::vector<Real> mean(D, 0.0), stdv(D, 0.0);
            for (size_t b = 0; b < M; b++) {
                for (size_t k = 0; k < D; k++) mean[k] += beatFeaturesCombined[b][k];
            }
            for (size_t k = 0; k < D; k++) mean[k] /= (Real)M;
            for (size_t b = 0; b < M; b++) {
                for (size_t k = 0; k < D; k++) {
                    Real d = beatFeaturesCombined[b][k] - mean[k];
                    stdv[k] += d * d;
                }
            }
            for (size_t k = 0; k < D; k++) {
                stdv[k] = std::sqrt(stdv[k] / (Real)M);
                if (stdv[k] < 1e-6) stdv[k] = 1.0;  // avoid div by zero on flat dims
            }
            for (size_t b = 0; b < M; b++) {
                for (size_t k = 0; k < D; k++) {
                    beatFeaturesCombined[b][k] = (beatFeaturesCombined[b][k] - mean[k]) / stdv[k];
                }
            }
        }

        // Also L2-normalize beatFeaturesChroma per-beat so cosine similarity is well-behaved on HPCP
        for (auto& v : beatFeaturesChroma) {
            Real n = 0;
            for (auto x : v) n += x * x;
            n = std::sqrt(n);
            if (n > 1e-6) {
                for (auto& x : v) x /= n;
            }
        }

        // Build a clustering feature: HPCP (weight 1.0) + z-normalized MFCC[1:] (weight 0.3)
        // beatFeaturesCombined is already z-normalized and is [MFCC[1:], HPCP] concatenated.
        // We extract the MFCC[1:] portion from beatFeaturesCombined and downweight it, then
        // concatenate with the L2-normalized HPCP from beatFeaturesChroma.
        std::vector<std::vector<Real>> beatFeaturesClustering;
        if (!beatFeaturesCombined.empty() && !beatFeaturesChroma.empty()
            && beatFeaturesCombined.size() == beatFeaturesChroma.size()) {
            size_t mfccPart = beatFeaturesCombined[0].size() - beatFeaturesChroma[0].size();
            const Real mfccWeight = 0.3;
            const Real chromaWeight = 1.0;
            beatFeaturesClustering.reserve(beatFeaturesCombined.size());
            for (size_t b = 0; b < beatFeaturesCombined.size(); b++) {
                std::vector<Real> v;
                v.reserve(beatFeaturesCombined[b].size());
                for (size_t k = 0; k < mfccPart; k++) {
                    v.push_back(mfccWeight * beatFeaturesCombined[b][k]);
                }
                for (size_t k = 0; k < beatFeaturesChroma[b].size(); k++) {
                    v.push_back(chromaWeight * beatFeaturesChroma[b][k]);
                }
                beatFeaturesClustering.push_back(v);
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

        size_t N = beatFeaturesCombined.size();
        std::vector<std::vector<float>> SSM(N, std::vector<float>(N, 0.0f));
        for (size_t i = 0; i < N; i++) {
            for (size_t j = i; j < N; j++) {
                float s = cosineSim(beatFeaturesCombined[i], beatFeaturesCombined[j]);
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
        result.downbeatOffset = chosenDownbeatOffset;

        // Beats
        NSMutableArray<NSNumber *> *beatArray = [NSMutableArray arrayWithCapacity:ticks.size()];
        for (Real tick : ticks) {
            [beatArray addObject:@(tick)];
        }
        result.beats = beatArray;

        // Onsets (sample-accurate refined times)
        NSMutableArray<NSNumber *> *onsetArray = [NSMutableArray arrayWithCapacity:refinedOnsets.size()];
        for (Real t : refinedOnsets) {
            [onsetArray addObject:@(t)];
        }
        result.onsets = onsetArray;

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
        if (!beatFeaturesClustering.empty()) {
            for (size_t s = 0; s < segCount; s++) {
                float t0 = boundaries[s];
                float t1 = boundaries[s + 1];
                std::vector<Real> sum(beatFeaturesClustering[0].size(), 0.0);
                int count = 0;
                for (size_t b = 0; b + 1 < ticks.size() && b < beatFeaturesClustering.size(); b++) {
                    float bt = (float)ticks[b];
                    if (bt >= t0 && bt < t1) {
                        for (size_t k = 0; k < sum.size(); k++) sum[k] += beatFeaturesClustering[b][k];
                        count++;
                    }
                }
                if (count > 0) {
                    for (auto& v : sum) v /= count;
                }
                // L2-normalize segMeans[s] for clean cosine
                Real nrm = 0;
                for (auto v : sum) nrm += v * v;
                nrm = std::sqrt(nrm);
                if (nrm > 1e-6) for (auto& v : sum) v /= nrm;
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
                if (cosineSim(segMeans[i], segMeans[j]) >= 0.92f) {
                    cluster[j] = nextCluster;
                }
            }
            nextCluster++;
        }

        // --- Heuristic mapping cluster → human label ---
        std::map<int, int> clusterCounts;
        for (int c : cluster) clusterCounts[c]++;

        // Per-segment RMS energy from raw audio
        std::vector<float> segmentEnergy(segCount, 0.0f);
        float totalEnergy = 0.0f;
        int totalEnergyCount = 0;
        for (size_t s = 0; s < segCount; s++) {
            size_t startSample = (size_t)(boundaries[s] * 44100.0f);
            size_t endSample = (size_t)(boundaries[s + 1] * 44100.0f);
            if (endSample > audio.size()) endSample = audio.size();
            if (startSample >= endSample) continue;

            double sumSq = 0.0;
            for (size_t i = startSample; i < endSample; i++) {
                sumSq += (double)audio[i] * (double)audio[i];
            }
            float rms = (float)std::sqrt(sumSq / (double)(endSample - startSample));
            segmentEnergy[s] = rms;
            totalEnergy += rms;
            totalEnergyCount++;
        }
        float meanEnergy = totalEnergyCount > 0 ? totalEnergy / (float)totalEnergyCount : 0.0f;

        // Degenerate-cluster detection: clustering failed to separate segments meaningfully.
        // Fall back to neutral "Section N" labels so the user knows to edit manually.
        bool degenerate = false;
        if (clusterCounts.size() <= 1) {
            degenerate = true;
        } else if (segCount > 0) {
            int maxC = 0;
            for (auto& kv : clusterCounts) if (kv.second > maxC) maxC = kv.second;
            if ((float)maxC / (float)segCount > 0.6f) {
                degenerate = true;
            }
        }

        NSMutableArray<NSString*>* heuristicLabels = [NSMutableArray arrayWithCapacity:segCount];

        if (degenerate) {
            for (size_t i = 0; i < segCount; i++) {
                [heuristicLabels addObject:[NSString stringWithFormat:@"Section %zu", i + 1]];
            }
        } else {
            // --- Energy-weighted chorus/verse pick among repeated clusters ---
            std::vector<int> repeatedClusters;
            for (auto& kv : clusterCounts) {
                if (kv.second >= 2) repeatedClusters.push_back(kv.first);
            }

            // Compute mean energy per cluster
            std::map<int, float> clusterMeanEnergy;
            for (int c : repeatedClusters) {
                float sum = 0.0f; int n = 0;
                for (size_t s = 0; s < segCount; s++) {
                    if (cluster[s] == c) { sum += segmentEnergy[s]; n++; }
                }
                clusterMeanEnergy[c] = n > 0 ? sum / (float)n : 0.0f;
            }

            int chorusCluster = -1;
            int verseCluster = -1;
            if (!repeatedClusters.empty()) {
                // Chorus = highest-energy repeated cluster
                chorusCluster = repeatedClusters[0];
                for (int c : repeatedClusters) {
                    if (clusterMeanEnergy[c] > clusterMeanEnergy[chorusCluster]) chorusCluster = c;
                }
                // Verse = most-repeated non-chorus cluster (tiebreak: lower energy)
                int bestCount = 0;
                for (int c : repeatedClusters) {
                    if (c == chorusCluster) continue;
                    int cnt = clusterCounts[c];
                    if (cnt > bestCount ||
                        (cnt == bestCount && verseCluster >= 0 && clusterMeanEnergy[c] < clusterMeanEnergy[verseCluster])) {
                        bestCount = cnt;
                        verseCluster = c;
                    }
                }
            }

            // --- Initial pass: Chorus / Verse from clusters; leave others as nil ---
            std::vector<NSString*> initial(segCount, nil);
            for (size_t s = 0; s < segCount; s++) {
                int c = cluster[s];
                if (c == chorusCluster) initial[s] = @"Chorus";
                else if (c == verseCluster) initial[s] = @"Verse";
            }

            // --- Positional priors: Intro / Outro ---
            auto sectionBarCount = [&](size_t s) -> int {
                // Approximate bar count from duration and BPM (4-beat bars)
                float dur = boundaries[s + 1] - boundaries[s];
                if (bpm <= 0) return 0;
                float beatsPerSec = bpm / 60.0f;
                return (int)std::round(dur * beatsPerSec / 4.0f);
            };

            if (segCount > 0) {
                // First segment → Intro if unassigned OR (short AND low-energy)
                int firstBars = sectionBarCount(0);
                bool firstIsShort = firstBars > 0 && firstBars < 16;
                bool firstIsLowEnergy = meanEnergy > 0 && segmentEnergy[0] < meanEnergy * 0.85f;
                if (initial[0] == nil || (firstIsShort && firstIsLowEnergy)) {
                    initial[0] = @"Intro";
                }
            }

            if (segCount > 1) {
                // Last segment → Outro if unassigned OR low-energy
                size_t last = segCount - 1;
                bool lastLowEnergy = meanEnergy > 0 && segmentEnergy[last] < meanEnergy * 0.8f;
                if (initial[last] == nil || lastLowEnergy) {
                    initial[last] = @"Outro";
                }
            }

            // --- Bridge: at most one, the longest unassigned mid-song segment ---
            int bridgeIdx = -1;
            int bridgeBars = -1;
            for (size_t s = 1; s + 1 < segCount; s++) {
                if (initial[s] != nil) continue;
                int bars = sectionBarCount(s);
                if (bars > bridgeBars) { bridgeBars = bars; bridgeIdx = (int)s; }
            }
            if (bridgeIdx >= 0) initial[bridgeIdx] = @"Bridge";

            // --- Anything still unassigned → "Section N" ---
            for (size_t s = 0; s < segCount; s++) {
                if (initial[s] == nil) {
                    [heuristicLabels addObject:[NSString stringWithFormat:@"Section %zu", s + 1]];
                } else {
                    [heuristicLabels addObject:initial[s]];
                }
            }
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
