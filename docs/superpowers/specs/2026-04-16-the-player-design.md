# The Player — Design Spec

A macOS native music practice app that lets musicians slow down, speed up, pitch-shift, and loop sections of audio files. Differentiator: automatic song analysis that detects BPM, beats, and sections (verse/chorus/bridge) to suggest intelligent loop regions.

## Platform & Stack

- **macOS native** (SwiftUI, minimum macOS 14 Sonoma)
- **Audio engine:** AVAudioEngine with AVAudioUnitTimePitch
- **Analysis:** Essentia (C++ library bridged via Objective-C++ wrapper)
- **Architecture:** Monolithic SwiftUI app — single target, no separate packages
- **Future:** Web version planned but not in scope for v1

## Audio Format Support

Whatever AVFoundation supports natively — no custom codecs. This includes:
- MP3, AAC/M4A, WAV, AIFF, ALAC, and other formats Apple supports out of the box

## File Loading

- Drag-and-drop onto the app window
- File > Open dialog (⌘O)
- macOS standard Recent Files menu
- No playlists, library, or streaming integration in v1

## Architecture

Three subsystems in one app:

### UI Layer (SwiftUI)
- Waveform view with colored section regions
- Transport controls (play/pause, skip)
- Speed and pitch sliders
- Section list sidebar
- Loop controls and markers

### Audio Engine (AVAudioEngine)
- `AVAudioFile` → `AVAudioPlayerNode` → `AVAudioUnitTimePitch` → output
- Independent speed (25%–200%) and pitch (±12 semitones) control
- Loop scheduling with sample-accurate start/end points
- Waveform peak data extraction for rendering
- Publishes state via Swift `@Observable` for UI binding

### Analysis Engine (Essentia)
- BPM detection via `RhythmExtractor2013`
- Beat grid extraction (array of beat timestamps)
- Section segmentation via `SBic` algorithm
- Section labeling by segment similarity (similar-sounding segments get the same label: Verse, Chorus, etc.)
- Runs on background thread with progress reporting
- Results cached per file

### Data Flow
1. User opens audio file → Audio Engine loads it, extracts waveform peaks
2. Audio buffer sent to Analysis Engine → BPM, beats, sections detected
3. UI observes both engines via `@Observable` → renders waveform with colored sections, populates sidebar
4. User interacts → UI calls Audio Engine methods
5. Audio Engine handles real-time playback with time-stretch/pitch-shift

## UI Layout

Standard macOS `NavigationSplitView`:

### Sidebar (220pt wide)
- **Sections list:** Each detected section shows label (Intro, Verse 1, Chorus, etc.), time range, and bar count. Click to jump and loop.
- **Track info:** BPM, duration, sample rate at the bottom.

### Main Content Area
- **Track title and artist** at top (from file metadata)
- **Waveform view** — the centerpiece:
  - Color-coded background bands for each section
  - Waveform rendered from extracted peaks
  - White playhead with dot handle
  - Loop region overlay with labeled boundaries
  - Current time (bottom-left) and total time (bottom-right)
- **Transport bar** below the waveform:
  - Left: Speed slider (25%–200%) with value display
  - Center: Skip back, play/pause, skip forward, A-B loop toggle
  - Right: Pitch slider (−12 to +12 semitones) with value display

## Core Features

### Playback & Speed/Pitch
- Analysis runs automatically on file load with a progress indicator
- Speed: 25% to 200%, continuous slider, default 100%
- Pitch: −12 to +12 semitones, snaps to semitone steps, default 0
- Speed and pitch are fully independent

### Looping
- **Section loop:** Click a section in the sidebar to loop it
- **Manual A-B loop:** Click the A-B button, then click two points on the waveform
- **Drag to adjust:** Loop boundaries are draggable on the waveform
- **Smart snap:** Loop points snap to nearest beat by default (toggleable)
- **Escape** exits the current loop and resumes normal playback

### Waveform Interaction
- Click to seek
- Scroll to zoom horizontally
- Trackpad pinch to zoom
- Hover shows time position tooltip

### Keyboard Shortcuts
| Key | Action |
|-----|--------|
| Space | Play/pause |
| ←/→ | Skip back/forward 5 seconds (or to beat boundaries when snap is on) |
| ↑/↓ | Adjust speed ±5% |
| `[` / `]` | Adjust pitch ±1 semitone |
| `L` | Toggle loop on/off |
| `1`–`9` | Jump to section by number |
| `⌘O` | Open file |

## Analysis Caching

- File identity: hash of first 1MB + file size (fast, avoids full-file hashing)
- Cache location: `~/Library/Application Support/The Player/cache/`
- Cache format: JSON per file hash
- Cached data per track:
  - `bpm` (Float)
  - `beats` (array of timestamps in seconds)
  - `sections` (array of `{label: String, startTime: Float, endTime: Float, startBeat: Int, endBeat: Int}`)
  - `waveformPeaks` (downsampled peak array for rendering)

## Essentia Integration

- **Wrapper:** `EssentiaAnalyzer` — Objective-C++ class bridging Essentia to Swift
- Takes an audio file path, runs analysis algorithms, returns a Swift-friendly `TrackAnalysis` struct
- Runs on a background thread via Swift concurrency
- Publishes progress for the UI loading indicator

## Error Handling

- **Unsupported format:** Alert listing supported formats
- **Analysis failure:** Graceful degradation — playback works, sections/beats unavailable. Shows a "Could not analyze" notice on the waveform area
- **Corrupt file:** AVFoundation error surfaced as user-friendly alert
- **Cache corruption:** Re-run analysis, overwrite cache

## Out of Scope for v1

- Playlists or library management
- Streaming service integration (Apple Music, Spotify)
- CD ripping
- Multiple file tabs or windows
- Audio recording or export
- Custom section labeling (manual override of detected sections)
- iOS or web version
- Gradual speed-up during loop practice (v2 candidate)
- Multiple saved loop points per track (v2 candidate)
