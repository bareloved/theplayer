# Library Picker & Import — Design

**Date:** 2026-04-30
**Status:** Draft
**Wave:** 1 of 3 in the library improvement track (foundation: finding & adding)

## Background

The library today is a sidebar list: Recent songs, Setlists, Playlists. To open a song, you either drag a file in or pick from the small Recent list. There is no way to:

- See *all* songs at once
- Search across the whole library
- Sort the library
- Add many songs at once (file-by-file drag is the only path)

Per-song stats (`practiceCount`, `totalPracticeTime`, `lastOpenedAt`) are recorded but not used in any browse surface beyond `recentSongs()`.

## Goals

For Wave 1, make the library *findable* and *fillable*:

1. Open any song from the library in under 2 seconds without leaving the player.
2. Add a folder of audio files in one drop, no per-file work.
3. Survive bad metadata (a song's embedded title not matching reality) when searching.

Non-goals for Wave 1: tags, nesting, smart groups, practice insights, artwork, BPM/key/last-practiced columns. Those land in Waves 2 and 3.

## User-facing behavior

### The Library Picker (⌘L)

A modal-style overlay that appears centered over the player. It does not move the underlying UI; pressing ⎋ dismisses it and the player surface is exactly as it was.

**Invocation:**
- ⌘L (primary)
- File menu → "Open from Library…"

**Layout (top to bottom):**
1. Search field, autofocused.
2. Sort dropdown (top-right of the picker): "Recent" (default), "Alphabetical", "Recently added".
3. Scrolling list of song titles. Title-only rows. Currently-loaded song shows a subtle highlight.
4. Footer hint: `↵ open · ⎋ close · ⌫ delete`.

**Search:**
- Case-insensitive substring match against `SongEntry.title` and the filename portion of `SongEntry.filePath` (`URL(fileURLWithPath:).deletingPathExtension().lastPathComponent`).
- A row is shown if either field contains the query.
- Empty query → show all songs in the active sort order.
- Search and sort are computed in pure functions on `[SongEntry]`, unit-testable, no view dependency.

**Sort:**
- "Recent" — sorts by `lastOpenedAt` desc; songs with `nil` `lastOpenedAt` fall to the bottom in `addedAt` desc order.
- "Alphabetical" — `title` asc, case-insensitive, with locale-aware comparison.
- "Recently added" — `addedAt` desc.
- When a search query is non-empty, sort is preserved but rows that don't match are filtered out. We do not re-rank by match quality in Wave 1 (substring presence is binary).

**Keyboard:**
- Search field is focused on open; typing filters live.
- ↑ / ↓ move the highlighted row.
- ↵ on highlighted row → load song into the player and dismiss the picker (same effect as clicking a song in the sidebar today).
- ⌫ on highlighted row → confirm sheet ("Remove "<title>" from library? File on disk is not deleted."); on confirm, calls `LibraryService.deleteSong`.
- ⎋ dismisses without action.

**Row actions (right-click context menu):**
- Add to Setlist… → submenu listing existing setlists; selecting one calls `addSongToSetlist`.
- Rename… → inline `TextField` overlay for that row; ↵ commits via `renameSong`, ⎋ cancels.
- Delete from Library — same as ⌫ keyboard path.

**Empty states:**
- Empty library: "No songs yet. Drop a folder anywhere on the window, or use File → Add Songs…"
- No search matches: "No songs match `\(query)\`."

### Importing songs

**File → Add Songs…** opens an `NSOpenPanel`:
- `allowsMultipleSelection = true`
- `canChooseFiles = true`, `canChooseDirectories = true`
- File type filter: the same audio UTTypes already accepted by drag-drop today (`.audio` family). Folders are also selectable; selecting a folder is treated identically to dropping it.

**Folder drop:** Dragging a folder onto the main window OR onto an open Library Picker triggers a recursive scan:

1. Walk the folder tree with `FileManager.enumerator(at:includingPropertiesForKeys:options:)`, skipping hidden files and packages.
2. For each file whose UTType conforms to `UTType.audio`, attempt to add via `LibraryService.addSong(filePath:title:artist:bpm:duration:)`.
3. The existing `addSong` no-op-on-duplicate behavior (`songByPath`) handles re-imports cleanly.
4. Title and artist for each imported song are read using the just-fixed `AudioEngine.loadEmbeddedMetadata(url:)` — i.e. the same async metadata read used in the single-file path. We do **not** load the audio itself; we just need the metadata.

**Progress UI:** A small toast/banner at the top of the window: "Importing… 14 / 87" with a Cancel button. Cancel stops the walk; songs already added stay added. On completion: "Imported 87 songs. 3 skipped (already in library)." Errors per-file (unreadable, format-rejected) are silently skipped and counted; if any are skipped due to error a "View log" link reveals them.

**Concurrency:** Sequential per-file metadata reads in a detached `Task`. We do not parallelize — Wave 1 is correctness-first, and a folder of 200 songs imports in a few seconds even sequentially. `LibraryService.save()` is called once at the end of the import, not per-file.

## Architecture

### New files

- `ThePlayer/Views/LibraryPicker.swift` — the overlay view. Owns search text, highlighted index, sort selection. Reads `[SongEntry]` from `LibraryService`.
- `ThePlayer/Library/LibraryFiltering.swift` — pure functions: `filter(_ songs:, query:) -> [SongEntry]`, `sort(_ songs:, by:) -> [SongEntry]`. Unit-tested.
- `ThePlayer/Library/FolderImporter.swift` — `actor FolderImporter` that walks a directory and yields candidate URLs. Cancellation-aware.
- `ThePlayerTests/LibraryFilteringTests.swift` — coverage for filter/sort edge cases (case, locale, nil dates, exact ties).
- `ThePlayerTests/FolderImporterTests.swift` — uses a temp directory tree to verify recursion, hidden-file skipping, UTType filtering, cancellation.

### Changed files

- `ThePlayer/Views/ContentView.swift` — adds `@State private var isPickerOpen = false`; presents `LibraryPicker` as `.sheet` (modal) or `.overlay` (Spotlight-style — see Open Question below). Wires ⌘L via `.keyboardShortcut("l", modifiers: .command)`. Adds folder-drop handling alongside today's file-drop handling. Adds File menu → "Open from Library…" via `Commands` builder in `ThePlayerApp.swift`.
- `ThePlayer/ThePlayerApp.swift` — adds `CommandMenu` / `CommandGroup` entries: "Open from Library…" (⌘L), "Add Songs…" (⇧⌘O).
- `ThePlayer/Services/LibraryService.swift` — adds `func addSongs(urls: [URL]) async -> ImportResult` for batch import; reuses the existing `addSong` for the per-file work but defers `save()` until the batch finishes. `ImportResult` reports `added`, `skippedDuplicate`, `failed` counts plus a `[URL: Error]` for the log link.

### Data model

No changes. `SongEntry`, `PlayerLibrary`, `Setlist`, `Playlist` stay as-is. The new behavior is read-mostly over the existing model.

### Module boundaries

- `LibraryFiltering` is pure. It has no SwiftUI, no `LibraryService`, no IO. Given `[SongEntry]` and a query/sort, it returns `[SongEntry]`. This makes search/sort trivially testable and lets us swap algorithms (fuzzy in Wave 2?) without touching the view.
- `FolderImporter` does IO but knows nothing about `LibraryService`. It produces a stream of candidate `URL`s; the caller (`LibraryService.addSongs`) decides what to do with them.
- `LibraryPicker` is presentation only. Search-text state lives in the view; sort selection persists in `UserDefaults` so the user's choice sticks across launches.

## Error handling

- **Bad audio file in a folder import** — caught at `AVAudioFile(forReading:)` time *only when we try to play it*. During import we only read metadata via `AVURLAsset`; if metadata load fails we still add the entry using the filename as the title (consistent with the rest of the app). The file is not validated as playable at import time — that would require opening every file. Wave 2 can add an opt-in "verify on import" pass.
- **Permission errors during folder walk** — surfaced once at the top of the import log; we do not bail out the whole import.
- **Duplicate paths** — `LibraryService.addSong` already short-circuits on `songByPath`. Counted as `skippedDuplicate`.
- **User cancels mid-import** — the walk task is cancelled; any songs already added stay (no rollback). The save runs once with whatever was added.

## Testing

- `LibraryFilteringTests` — query case insensitivity, filename match when title differs (the Get-Lucky-is-Peaches scenario), empty query, multiple sort orders, nil `lastOpenedAt` placement, locale-aware alphabetical (e.g. "Élise" sorts with "E").
- `FolderImporterTests` — temp directory with nested subfolders, hidden files (`.DS_Store`), non-audio files, symlinks, empty directories. Verifies cancellation by enumerating against a large fake tree and cancelling mid-walk.
- `LibraryServiceImportTests` — `addSongs(urls:)` with mixed valid/invalid/duplicate URLs; verifies single `save()` call (via a tiny `FileManager` test double or by counting `library.json` mtime bumps).
- Manual: import a real folder of ~50 mp3s; verify titles, no duplicates, picker shows them sorted by addedAt desc when toggled.

## Open question

**Sheet vs. overlay presentation.** SwiftUI's `.sheet` is modal and centered, but on macOS it animates in from the top of the parent window — visually fine, behaviorally always blocks. A `.overlay` with custom `Material.thinMaterial` background gives the true Spotlight feel (centered, floating, doesn't shift the window) but we have to handle dismissal/keyboard ourselves. Recommend starting with `.sheet` for Wave 1 to ship faster; revisit in Wave 2 if it feels wrong. Flagging here so the implementation plan picks one explicitly rather than punting.

## What we're explicitly *not* doing

- Tags / labels — Wave 2.
- Nested setlists — Wave 2.
- Watched folders — Wave 2 if we still want it.
- iTunes / Apple Music import — Wave 2.
- Streaks, "what to practice next", practice charts — Wave 3.
- Artwork, BPM / key / duration columns — out of scope by user direction. Title-only.
- Fuzzy matching — substring is enough for current library size; revisit in Wave 2.
- Per-file playability validation at import — too slow; defer.

## Migration

None. The library JSON schema is unchanged. Existing users get the new picker on next launch with their library intact.
