# The Player

A Mac app for practicing music with recordings.

Drop in a song. The Player figures out the tempo, the beats, and where the verses and choruses are. Then you can slow it down without changing the pitch, change the key without changing the speed, and loop tricky bars over and over until your fingers learn them.

It's the kind of tool you'd want if you've ever tried to learn a guitar solo, transcribe a piano part, work out a vocal line, or just play along with a song that's a half-step too high for your voice.

## What it does

- **Slow it down (or speed it up).** Half speed, quarter speed, whatever you need — the pitch stays the same.
- **Change the key.** Move the song up or down without making it sound like a chipmunk or a slowed-down monster.
- **Loop a section.** Drag a bracket over the bit you want to drill. The Player snaps the loop to musical bars so it actually sounds right when it repeats.
- **See the song.** A waveform across the top shows you the whole track, with the verses, choruses, and bridges marked automatically. You can zoom in tight on a single bar or zoom out to see the whole shape.
- **Edit the map.** If the auto-analysis got something wrong — the wrong tempo, a chorus that's actually a bridge, a downbeat that's off — you can drag things around and fix it. Your edits are saved per song.
- **Click track.** Built-in metronome that locks to the song's beat grid.
- **Setlists.** Group songs you're working on into lists.

## Requirements

- macOS 14 or later
- Apple Silicon recommended

## Building from source

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen), and the audio analysis is powered by [Essentia](https://essentia.upf.edu/) (a C++ library), so there's a bit of setup.

```bash
# 1. Install the build tools and audio libraries
brew install xcodegen fftw ffmpeg libsamplerate taglib libyaml chromaprint

# 2. Generate the Xcode project
xcodegen generate

# 3. Open in Xcode and build
open ThePlayer.xcodeproj
```

Essentia itself ships pre-built under `Vendor/essentia/`.

### Running tests

```bash
xcodebuild -project ThePlayer.xcodeproj -scheme ThePlayer \
  -destination 'platform=macOS' test
```

## How it's put together

Three pieces, wired together in `ThePlayerApp.swift`:

1. **Audio engine** (`ThePlayer/Audio/`) — plays the file, handles speed and pitch, draws the waveform.
2. **Analysis engine** (`ThePlayer/Analysis/`) — runs the song through Essentia to find tempo, beats, and section boundaries. Caches the result so it only happens once per song.
3. **UI** (`ThePlayer/Views/`) — the SwiftUI surface, with the zoomable waveform, section editor, and loop bracket as the centerpieces.

Design docs and implementation plans for individual features live in `docs/superpowers/`.

## Status

Personal project, work in progress. Expect rough edges.
