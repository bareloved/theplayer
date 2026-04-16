# Library, Setlists & Playlists — Design Spec

Add a song library with practice history, setlists for gigs, playlists for practice collections, and smart playlists generated from usage data.

## Data Storage

Single `library.json` in `~/Library/Application Support/The Player/`. All songs, setlists, and playlists in one file.

### Song Entry
- `id` (UUID)
- `filePath` (String — absolute path to audio file)
- `title`, `artist` (String — from metadata or filename)
- `bpm` (Float), `duration` (Float)
- `analysisCacheKey` (String — links to analysis cache)
- `lastSpeed` (Float), `lastPitch` (Float) — saved practice state
- `lastPosition` (Float) — where playback was when song was unloaded
- `lastLoopStart`, `lastLoopEnd` (Float? — nil if no loop was active)
- `lastOpenedAt` (Date), `addedAt` (Date)
- `practiceCount` (Int), `totalPracticeTime` (Double, seconds)

### Setlist
- `id` (UUID)
- `name` (String)
- `songIds` ([UUID] — ordered, order matters for sequential playback)
- `createdAt`, `updatedAt` (Date)

### Playlist
- `id` (UUID)
- `name` (String)
- `songIds` ([UUID] — unordered collection)
- `createdAt`, `updatedAt` (Date)

### Smart Playlists (computed at runtime, not stored)
- **Recent** — last 20 songs by `lastOpenedAt`
- **Most Practiced** — top 10 by `practiceCount`
- **Needs Work** — songs with `practiceCount` < 3

## UI Layout

Three-column layout replacing the current two-column `NavigationSplitView`:

- **Left sidebar** (collapsible) — Library browser: Recent, Setlists, Playlists, Smart Playlists
- **Center** — Waveform + transport (unchanged)
- **Right sidebar** (collapsible) — Song sections, track info (current left sidebar content moves here)

### Left Sidebar Structure

```
▼ Recent
  Song A — 2 min ago
  Song B — yesterday
  Song C — 3 days ago

▼ Setlists
  ▶ Saturday Gig (3 songs)
  ▶ Jazz Standards (8 songs)
  [+ New Setlist]

▼ Playlists
  ▶ This Week (5 songs)
  ▶ Tricky Solos (3 songs)
  [+ New Playlist]

▼ Smart
  ▶ Most Practiced
  ▶ Needs Work
```

Clicking a setlist/playlist expands it inline to show its songs. Clicking a song loads it.

### Adding Songs
- Any file opened (via drag-drop, ⌘O, or setlist) is automatically added to the library
- Right-click a song in the left sidebar → "Add to Setlist..." / "Add to Playlist..." submenu
- "+" button on setlists/playlists opens a picker from the library
- Drag to reorder songs within a setlist

### Setlist Playback
- When inside a setlist, the transport bar shows a "Next →" button
- When a song finishes or user clicks "Next →", the next song in the setlist loads automatically
- The next song's saved practice state (speed, pitch, loop) restores on load
- Current position in setlist is highlighted in the sidebar

## Behavior

### Auto-save Practice State
When a song is unloaded (new song loaded, app quit, etc.), the current speed, pitch, playback position, and loop region are saved to the song's library entry. When that song is loaded again from any source (history, setlist, playlist), those settings restore automatically.

### Practice Tracking
- `practiceCount` increments each time a song is loaded
- `totalPracticeTime` accumulates while the song is playing (tracked by the audio engine timer)

### Both Sidebars Collapsible
Standard macOS sidebar toggle buttons in the toolbar. Both can be hidden independently to maximize waveform space.

## Error Handling

- **Missing file** — song shown grayed out with "Missing" badge. Right-click → "Relocate" to update the file path.
- **Empty setlist/playlist** — "No songs yet" placeholder with prompt to add songs
- **Corrupt library.json** — back up as `library.json.backup`, start fresh with empty library
- **Auto-save failure** — log silently, retry next save cycle

## Out of Scope
- Importing/exporting setlists as files (v2)
- Syncing library across devices
- Smart playlist customization (custom filters/rules)
- Album art display
