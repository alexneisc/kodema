# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kodema is a macOS backup tool written in Swift that backs up iCloud Drive and local files to Backblaze B2 cloud storage. It supports two modes: incremental backup with versioning (Time Machine-style) and simple mirroring.

## Build & Development Commands

### Building
```bash
# Debug build
swift build

# Release build (optimized)
swift build -c release
# OR
make release

# Run without installing
swift run kodema help
.build/release/kodema help
```

### Installation
```bash
# Install to /usr/local/bin
make install
# OR
sudo cp .build/release/kodema /usr/local/bin/

# Uninstall
make uninstall
```

### Testing
```bash
# Create test config first
mkdir -p ~/.config/kodema
cp kodema/config.example.yml ~/.config/kodema/config.yml
# Edit config with your B2 credentials

# Test with discovery
kodema list

# Test backup with small folder
mkdir -p ~/Documents/kodema-test
echo "test" > ~/Documents/kodema-test/test.txt
kodema backup
```

## Architecture

### Core Components (kodema/core.swift)

**Configuration System (lines 6-61)**
- YAML-based config loading via Yams library
- Nested config structs: `B2Config`, `TimeoutsConfig`, `IncludeConfig`, `FiltersConfig`, `RetentionConfig`, `BackupConfig`, `MirrorConfig`
- Default config location: `~/.config/kodema/config.yml`
- `BackupConfig.manifestUpdateInterval`: Frequency of incremental manifest updates (default: 50 files)

**File Discovery & Scanning (lines 388-449)**
- `buildFoldersToScan()`: Determines folders to backup (custom list or all iCloud Drive folders)
- `scanFolder()`: Recursively scans directories using `FileManager.enumerator`
- `checkFileStatus()`: Detects if file is local or in iCloud (not yet downloaded)

**iCloud Integration (lines 295-364)**
- `getAvailableDiskSpace()`: Checks available disk space using `volumeAvailableCapacityForImportantUsageKey`
- Disk space validation: Before downloading iCloud files, verifies 120% of file size is available (20% buffer)
- `startDownloadIfNeeded()`: Triggers iCloud file download if space check passes
- `waitForICloudDownload()`: Polls until file is locally available (with timeout)
- `evictIfUbiquitous()`: Removes local copy after upload to save disk space
- Uses `URLResourceKey`: `.isUbiquitousItemKey`, `.ubiquitousItemDownloadingStatusKey`
- Files skipped if insufficient disk space (marked as failed with warning)

**B2 API Client (lines 686-1131)**
- `B2Client` class handles all Backblaze API operations
- Auth flow: `ensureAuthorized()` → caches `B2AuthorizeResponse`
- Bucket resolution: `ensureBucketId()` resolves bucket name to ID
- **Upload strategies:**
  - Small files (≤5GB): `uploadSmallFile()` uses `httpBodyStream` to avoid loading entire file in RAM
  - Large files (>5GB): `uploadLargeFile()` splits into parts, uploads with retry logic
  - Part upload uses concurrent uploads (configurable via `uploadConcurrency`)
- **Download strategies:**
  - `downloadFile()`: Loads entire file into RAM (use for small files like manifests ~500KB)
  - `downloadFileStreaming()`: Streams directly to disk (efficient for large files, constant RAM usage)
- Retry logic: Handles expired upload URLs, temporary errors (5xx), exponential backoff

**Versioning & Snapshots (lines 70-86, 1066-1193)**
- `SnapshotManifest`: JSON metadata for each backup run (timestamp, file list, total size)
- `FileVersionInfo`: Per-file metadata (path, size, mtime, version timestamp)
- **IMPORTANT**: Each snapshot manifest contains ALL files existing at that point in time, not just changed files
  - New snapshots inherit files from previous snapshot
  - Changed files get updated version timestamps
  - Deleted files are removed from manifest
- `fetchLatestManifest()`: Downloads and parses the latest snapshot manifest from B2
- `uploadManifest()`: Helper function to create and upload manifest to B2
- `uploadSuccessMarker()`: Uploads completion marker after successful backup
- **Incremental Manifest Updates**: Prevents orphaned files on backup interruption
  - Initial manifest uploaded at backup start (empty or with previous files)
  - Manifest re-uploaded every N files (configurable via `manifestUpdateInterval`)
  - Final manifest uploaded at backup end (with deleted files filtered)
  - Success marker uploaded after successful backup completion
  - Ensures every uploaded file is tracked in manifest, even if backup is interrupted
- Storage structure:
  - `backup/snapshots/{timestamp}/manifest.json` - snapshot metadata (complete file list)
  - `backup/files/{relative_path}/{timestamp}` - versioned file content
  - `backup/.success-markers/{timestamp}` - completion markers for successful backups
- `fileNeedsBackup()`: Determines if file changed by comparing size + mtime against previous snapshot manifest

**Retention & Cleanup (lines 1625-1820)**
- Time Machine-style retention policy: hourly → daily → weekly → monthly
- `classifySnapshot()`: Categorizes snapshots by age
- `selectSnapshotsToKeep()`: Groups by time period, keeps latest in each bucket
- **Hybrid Orphan Detection**: Uses success markers for efficient cleanup
  - Fetches success markers to identify completed vs incomplete backups
  - For completed backups: all files with that timestamp are valid (no manifest download needed)
  - For incomplete backups: downloads manifest to verify which files are actually referenced
  - Deletes success markers for removed snapshots
  - Significantly faster than downloading all manifests (only incomplete backups need manifest check)
- Cleanup deletes: snapshot manifests, success markers, and orphaned file versions

**Progress Tracking (lines 96-239)**
- `ProgressTracker` actor: Thread-safe progress state
- ANSI terminal UI: progress bar, speed, ETA, current file
- Cursor management: hides cursor during progress, restores on exit/error
- **Graceful Shutdown** (lines 1266-1298): Signal handlers for SIGINT/SIGTERM
  - Sets global flag instead of immediate exit
  - Allows current file upload to complete
  - Saves partial manifest with progress
  - Shows cursor and exits cleanly with appropriate exit code
  - Preserves all uploaded files for resume on next backup

### Command Flow

**`kodema help` (lines 1201-1222)**
- Displays usage information, available commands, and examples
- Aliases: `help`, `-h`, `--help`

**`kodema version` (lines 1197-1199)**
- Displays the current version of Kodema
- Aliases: `version`, `-v`, `--version`
- Version string is defined in `kodema/Version.swift`

**`kodema list` (lines 1240-1402)**
1. Enumerate iCloud containers in `~/Library/Mobile Documents/`
2. Skip Apple system containers (com~apple~*)
3. Show third-party app folders with file counts and sizes
4. Helpful for discovering what to backup

**`kodema test-config [--config <path>]`**
1. Load and validate YAML configuration file
2. Test B2 authentication and bucket access
3. Scan configured folders and check accessibility
4. Count files and calculate total size
5. Detect iCloud files not yet downloaded locally
6. Check available disk space and warn if insufficient for iCloud downloads
7. Display all configuration settings (filters, retention, performance, timeouts)
8. Show summary with total files and estimated size
- Supports custom config via `--config` or `-c` flag
- No modifications made to local files or remote B2 bucket
- Exits with error if configuration has issues (missing folders, auth failure, etc.)
- Shows warnings for potential issues (iCloud files not downloaded, low disk space)
- Useful for validating config before first backup or after making changes
- Disk space check: requires 20% buffer above file size for safety

**`kodema backup [--config <path>] [--dry-run]` (lines 1914-2124)**
1. Scan local files and apply filters
2. Fetch latest snapshot manifest from B2 (`fetchLatestManifest()`)
3. Determine which files changed by comparing with previous snapshot (`fileNeedsBackup()`)
4. **If --dry-run**: Show preview (file count, total size) and exit early
5. Sort files (local first, then iCloud)
6. Upload initial manifest to B2 (establishes snapshot immediately)
7. Upload changed files with progress tracking
   - For iCloud files: checks available disk space before downloading (requires 20% buffer)
   - Skips files if insufficient disk space with warning message
   - Checks for shutdown request before each file (graceful shutdown support)
8. Incrementally update manifest every N files (prevents orphaned files on interruption)
9. Upload final manifest with deleted files filtered
10. Upload success marker to indicate backup completed successfully (skipped if shutdown requested)
11. Evict iCloud files to free disk space
- Supports custom config via `--config` or `-c` flag
- Supports dry-run mode via `--dry-run` or `-n` flag
- Manifest update frequency controlled by `backup.manifestUpdateInterval` (default: 50 files)
- **Graceful shutdown**: On SIGINT/SIGTERM, finishes current file, saves partial manifest, exits cleanly
- **Dry-run**: Shows files to upload and total size without making any changes

**`kodema mirror [--config <path>]` (lines 1836-1939)**
1. Scan all files
2. Sort files (local first)
3. Upload all files (no change detection)
4. Simple flat structure in B2
- Supports custom config via `--config` or `-c` flag

**`kodema cleanup [--config <path>] [--dry-run]` (lines 1670-1910)**
1. Fetch all snapshot manifests from B2
2. Apply retention policy to select snapshots to keep
3. **If --dry-run**: Show preview of what would be deleted and exit
4. Confirm deletion (skipped in dry-run mode)
5. Delete old snapshot manifests
6. Fetch success markers and delete markers for removed snapshots
7. Use hybrid orphan detection to find orphaned file versions:
   - For completed backups: all files with that timestamp are valid
   - For incomplete backups: download manifest to verify referenced files
8. Delete orphaned file versions
- Supports custom config via `--config` or `-c` flag
- Supports dry-run mode via `--dry-run` or `-n` flag
- Performance: only downloads manifests for incomplete backups (typically 0-5% of total)
- **Dry-run**: Shows snapshots to delete, orphaned files to remove, without making changes

**`kodema restore [options]` (lines 2613-2686)**
1. Parse restore options (snapshot, paths, output, force, list-snapshots, dry-run)
2. If `--list-snapshots`: display all available snapshots and exit
3. Get target snapshot (interactive selection or via `--snapshot` flag)
4. Filter files to restore (all or specific paths via `--path`)
5. Determine output directory (original location or `--output`)
6. Check for file conflicts with existing files
7. **If --dry-run**: Show preview (files, size, conflicts) and exit
8. If conflicts and no `--force`: prompt user for confirmation (skipped in dry-run)
9. Download files from B2 with progress tracking
10. Write files and restore modification timestamps
11. Report completion with success/failure counts

**Flags:**
- `--snapshot <timestamp>` - Restore specific snapshot
- `--path <path>` - Restore specific file/folder (repeatable)
- `--output <path>` - Custom restore location (default: original)
- `--force` - Skip overwrite confirmation
- `--list-snapshots` - List available snapshots
- `--dry-run`, `-n` - Preview restore without downloading files

**Key functions:**
- `parseRestoreOptions()` - Parse command-line flags
- `fetchAllSnapshots()` - List snapshots from B2
- `selectSnapshotInteractively()` - Interactive snapshot selection with metadata
- `getTargetSnapshot()` - Get snapshot manifest (interactive or direct)
- `filterFilesToRestore()` - Filter files by path patterns (supports exact match, prefix, directory components)
- `checkForConflicts()` - Detect existing files at destination
- `handleConflicts()` - Interactive conflict resolution
- `downloadAndRestoreFiles()` - Download loop with progress tracking
- `runRestore()` - Main restore entry point
- `listSnapshotsCommand()` - Display available snapshots (with optional path filtering)

**Path filtering logic:**
- Supports flexible path matching: exact, prefix, directory components
- Works with or without trailing slash
- Can filter snapshots by path: `--path folder1 --list-snapshots` shows only snapshots containing folder1 files

### Key Design Decisions

**Streaming for Large Files**
- Uses `InputStream` for uploads and chunked reading for SHA1 to avoid RAM limits
- SHA1 computed in 8MB chunks (`sha1HexStream()`)

**Async/Await Concurrency**
- Main logic uses Swift async/await (requires macOS 13+, Swift 6.0)
- `ProgressTracker` is an actor for thread-safe state management
- Timeout wrappers (`withTimeoutVoid`, `withTimeoutDataResponse`) - currently no-ops but structured for future timeout enforcement

**Error Handling Strategy**
- B2 errors mapped to `B2Error` enum: `.unauthorized`, `.expiredUploadUrl`, `.temporary`, `.client`
- Upload URL expiration handled transparently with retry
- 5xx errors trigger exponential backoff
- File-level failures tracked but don't abort entire backup

**Glob Pattern Filtering (lines 451-527)**
- Custom glob implementation using `fnmatch()` from Darwin
- Special handling for directory patterns: `/**` and trailing `/`
- Supports tilde expansion: `~/.Trash/**`

## Important Implementation Notes

### When Adding Features

**Config Changes**: Update both `config.example.yml` and the Decodable structs in core.swift (lines 6-59)

**New B2 Operations**: Follow the pattern in `B2Client`:
- Add response struct conforming to `Decodable`
- Implement retry logic with `mapHTTPErrorToB2()`
- Use `session.data(for:timeout:)` extension (line 546)

**Progress Updates**: Call `await progress.printProgress()` before and after long operations

**iCloud File Handling**: Always check `checkFileStatus()` before accessing files, use `startDownloadIfNeeded()` + `waitForICloudDownload()` for cloud files

### Testing Considerations

**No Tests Yet**: Test infrastructure not implemented (Makefile line 38)

**Manual Testing Approach**:
1. Use `kodema list` to verify iCloud access
2. Test with small folder first
3. Verify uploads in B2 web interface
4. Test retention with `kodema cleanup --dry-run` (not implemented, would need to add)

### Glob Pattern Examples
```yaml
excludeGlobs:
  - "*.tmp"              # Match extension
  - "**/.DS_Store"       # Match anywhere
  - "**/node_modules/**" # Exclude directory contents
  - "~/Downloads/**"     # Absolute path with tilde
  - "/Volumes/Backup/"   # Directory prefix (trailing slash)
```

## Dependencies

- **Yams** (6.2.0+): YAML parsing for config
- **CommonCrypto**: SHA1 hashing (macOS system framework)
- **Foundation**: File system, networking, iCloud APIs

Package definition: `Package.swift` (in repository root)

## Code Organization

**Single File Architecture**: All code in `kodema/core.swift` (~1950 lines)
- MARK comments divide sections: Models, Helpers, B2 API, Commands
- Entry point: `@main struct Runner` (line 1979)
- Version: `kodema/Version.swift` exports `KODEMA_VERSION` constant and is used by `printVersion()` and `printHelp()`

## Code Style Guidelines

**CRITICAL FORMATTING RULES** - Always follow these when editing code:

1. **Empty Lines**: All empty lines in code must be completely empty (no spaces or tabs)
   - Bad: `    ` (line with spaces/tabs)
   - Good: `` (completely empty line)
   - This keeps code clean and avoids whitespace-only lines in git diffs

2. **Language**: All code, comments, documentation, and user-facing text must be in English
   - Comments: `// Fetch latest snapshot` (not Ukrainian)
   - Variable names: `latestManifest` (not transliterated or mixed)
   - User output: `"No previous snapshots found"` (not localized)
   - Exception: Only config examples in `config.example.yml` may contain non-English comments for user convenience

## Common Pitfalls

1. **iCloud Timeouts**: Default 30min may be insufficient for large files on slow connections - increase `icloudDownloadSeconds`

2. **Part Size**: Must be ≥ B2 minimum (5MB), configured in MB not bytes

3. **File Size Threshold**: Currently 5GB (lines 1872, 1883) - could make configurable

4. **Retention Cleanup**: Irreversible! Users should test policy before running cleanup

5. **Concurrent Uploads**: `uploadConcurrency > 1` is beta, may cause issues with B2 rate limits

6. **Signal Handling**: setupSignalHandlers() must be called early (line 2116). Implements graceful shutdown - finishes current file and saves progress before exiting. Don't use SIGKILL (kill -9) as it bypasses graceful shutdown.

7. **Restore Memory Usage**: Now uses streaming downloads (constant ~8-16MB RAM usage regardless of file size). Manifests still load into RAM but are small (~500KB).

8. **Restore Conflicts**: Without `--force`, user must manually confirm overwrites - be careful when restoring to original location

9. **Sequential Downloads**: Restore downloads files one at a time - no parallelization (avoids B2 rate limits but slower for many small files)

10. **Manifest Update Frequency**: Low `manifestUpdateInterval` values (e.g., <10) increase B2 API calls and may slow down backup. High values (e.g., >100) mean more orphaned files if backup is interrupted. Default of 50 is a good balance.
