# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Talking to the user

No coding jargon. Explain things in plain, simple words — like you're talking to a friend, not writing a tech doc. If a technical term is unavoidable, say what it means in everyday language.

## Project

**The Player** — native macOS (14+) music practice app that slows down, speeds up, pitch-shifts, and intelligently loops sections of audio files using automatic song analysis. SwiftUI + AVAudioEngine + Essentia (C++).

## Commands

The Xcode project is generated from `project.yml` via XcodeGen — never edit the `.xcodeproj` directly; edit `project.yml` and regenerate.

```bash
# Regenerate the Xcode project after changing project.yml or adding source files
xcodegen generate

# Build
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -configuration Debug build

# Run all tests
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' test

# Run a single test class or method
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer -destination 'platform=macOS' \
  test -only-testing:ThePlayerTests/LoopRegionTests
xcodebuild ... test -only-testing:ThePlayerTests/LoopRegionTests/testSnapToBeat
```

Adding a new Swift file: drop it under `ThePlayer/` in the appropriate subdirectory, then run `xcodegen generate` — sources are picked up by directory globbing in `project.yml`.

## Architecture

Three subsystems wired together in `ThePlayerApp.swift` / `ContentView.swift`:

1. **Audio Engine** (`ThePlayer/Audio/`) — `AudioEngine` is an `@Observable` class wrapping `AVAudioEngine` + `AVAudioUnitTimePitch` for load/play/seek/speed/pitch. `WaveformExtractor` produces downsampled peaks for rendering. `ClickTrackPlayer` drives the metronome.
2. **Analysis Engine** (`ThePlayer/Analysis/`) — `TrackAnalyzerProtocol` has two implementations: `EssentiaAnalyzer` (ObjC++ `.mm` bridging Essentia C++ for BPM/beats/sections) and `MockAnalyzer`. `AnalysisService` is the Swift async wrapper. `AnalysisCache` persists results per file hash to App Support. `UserEditsStore` persists user overrides on top of analysis (e.g. manual section edits) — merging logic lives in `AnalysisService` (see `AnalysisServiceMergeTests`).
3. **UI Layer** (`ThePlayer/Views/`) — SwiftUI `NavigationSplitView`. `WaveformView` is the central canvas (peaks, sections, playhead, loop region). `SectionEditor/` contains the manual section editing surface (`SectionsViewModel`, boundary handles, label badges). `TiledCanvas`/`TiledHostingView` and `HorizontalNSScrollView` underpin the zoomable, scrollable waveform — zoom math lives in `WaveformZoomMath` (pure, unit-tested).

**C++ bridging:** `ThePlayer/ThePlayer-Bridging-Header.h` exposes `EssentiaAnalyzer.h` to Swift. Essentia and its dependencies (fftw, ffmpeg, libsamplerate, taglib, libyaml, chromaprint) are linked from `Vendor/essentia/lib` and Homebrew (`/opt/homebrew`) — see `OTHER_LDFLAGS` and `LIBRARY_SEARCH_PATHS` in `project.yml`. Building requires those Homebrew packages installed at the versions encoded in `project.yml`.

**Models** (`ThePlayer/Models/`) are `Codable` value types — `TrackAnalysis`, `AudioSection`, `LoopRegion`, `UserEdits`, `SongEntry`, `Setlist`, etc. The cache schema is the on-disk format; changes need migration consideration.

## Planning Docs

`docs/superpowers/specs/` and `docs/superpowers/plans/` contain dated design specs and implementation plans for features (loops, sections, zoom, BPM/bars, downbeat alignment, library/setlists). When working on a feature, check for a matching dated spec/plan before designing from scratch.
