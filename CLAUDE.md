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

The codebase is organized into logical modules for maintainability and clarity:

```
kodema/
├── Models/              - Data structures and configuration
├── Core/                - Core utilities and progress tracking
├── Security/            - Encryption and hashing
├── FileSystem/          - File scanning and iCloud integration
├── Network/             - Backblaze B2 API client
├── Commands/            - Command implementations
├── Utilities/           - Helper functions
├── main.swift           - Entry point
└── Version.swift        - Version constant
```

### Models (kodema/Models/)

**Config.swift** - Configuration data structures
- YAML-based config loading via Yams library
- Nested config structs: `B2Config`, `TimeoutsConfig`, `IncludeConfig`, `FiltersConfig`, `RetentionConfig`, `BackupConfig`, `MirrorConfig`, `EncryptionConfig`
- Default config location: `~/.config/kodema/config.yml`
- `BackupConfig.manifestUpdateInterval`: Frequency of incremental manifest updates (default: 50 files)

**Snapshot.swift** - Versioning data structures
- `SnapshotManifest`: JSON metadata for each backup run (timestamp, file list, total size)
- `FileVersionInfo`: Per-file metadata (path, size, mtime, version timestamp)
- **IMPORTANT**: Each snapshot manifest contains ALL files existing at that point in time, not just changed files
  - New snapshots inherit files from previous snapshot
  - Changed files get updated version timestamps
  - Deleted files are removed from manifest

**FileItem.swift** - File metadata model for scanning

**RestoreModels.swift** - Restore-specific data structures

### FileSystem (kodema/FileSystem/)

**FileScanner.swift** - File discovery and scanning
- `buildFoldersToScan()`: Determines folders to backup (custom list or all iCloud Drive folders)
- `scanFolder()`: Recursively scans directories using `FileManager.enumerator`
- `scanFile()`: Scans individual files

**iCloudManager.swift** - iCloud integration
- `checkFileStatus()`: Detects if file is local or in iCloud (not yet downloaded)
- `getAvailableDiskSpace()`: Checks available disk space using `volumeAvailableCapacityForImportantUsageKey`
- Disk space validation: Before downloading iCloud files, verifies 120% of file size is available (20% buffer)
- `startDownloadIfNeeded()`: Triggers iCloud file download if space check passes
- `waitForICloudDownload()`: Polls until file is locally available (with timeout)
  - **On-demand download support**: If file has status `nil` or `.notDownloaded`, attempts to open file for reading
  - macOS automatically downloads iCloud files on-demand when accessed, much faster than waiting for status change
  - Handles three status cases: `.current` (already downloaded), `.notDownloaded` (triggers download), `nil` (triggers download)
  - This prevents hanging on files that are readable but have incorrect/cached status metadata
- `evictIfUbiquitous()`: Removes local copy after upload to save disk space
- Uses `URLResourceKey`: `.isUbiquitousItemKey`, `.ubiquitousItemDownloadingStatusKey`
- Files skipped if insufficient disk space (marked as failed with warning)

**GlobMatcher.swift** - Pattern matching and filtering
- Custom glob implementation using `fnmatch()` from Darwin
- Special handling for directory patterns: `/**` and trailing `/`
- Supports tilde expansion: `~/.Trash/**`
- `applyFilters()`: Applies size and glob filters to file lists

### Network (kodema/Network/)

**B2Client.swift** - Backblaze B2 API client
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

**B2Error.swift** - Error handling and retry logic
- **Retry logic with intelligent error handling:**
  - Expired upload URLs (401): Retry immediately with new URL
  - Rate limits (429): Exponential backoff (1s, 2s, 4s) with visible warning
  - Temporary errors (5xx): Exponential backoff
  - Client errors (4xx except 401/429): Fail immediately
  - Max retries: 3 (configurable via `b2.maxRetries`)
- `RestoreError` enum for restore-specific errors

**B2Models.swift** - API response models
- Decodable structs for all B2 API responses

**URLSessionExtensions.swift** - HTTP utilities

### Security (kodema/Security/)

**EncryptionManager.swift** - Encryption functionality
- Supports three key sources: keychain, file, passphrase
- File encryption/decryption with streaming (8MB chunks)
- Filename encryption/decryption (URL-safe Base64)
- Manifest data encryption/decryption
- Uses RNCryptor for encryption (AES-256)

**SHA1.swift** - Streaming SHA1 computation
- Computes SHA1 in 8MB chunks to avoid RAM limits

### Core (kodema/Core/)

**ProgressTracker.swift** - Progress tracking
- `ProgressTracker` actor: Thread-safe progress state
- Tracks completed, failed, and skipped files
- ANSI terminal UI: progress bar, speed, ETA, current file
- Displays skipped files (e.g., path too long) in progress and final summary
- Cursor management: hides cursor during progress, restores on exit/error

**Constants.swift** - Global constants
- ANSI color codes for terminal output
- `maxB2PathLength` constant: 950 bytes (safety margin below B2's 1000-byte limit)

**Helpers.swift** - Core utilities
- Config loading and parsing
- URL path expansion
- Error types: `TimeoutError`, `ConfigError`, `EncryptionError`
- Timeout wrapper functions

### Commands (kodema/Commands/)

**SnapshotHelpers.swift** - Shared snapshot utilities
- `fetchLatestManifest()`: Downloads and parses the latest snapshot manifest from B2
  - Automatically decrypts manifest if encryption is enabled
  - Backward compatible with plaintext manifests (pre-encryption)
- `uploadManifest()`: Helper function to create and upload manifest to B2
  - Automatically encrypts manifest if encryption is enabled
  - Uses `EncryptionManager.encryptData()` for manifest encryption
  - Content-Type changes to `application/octet-stream` for encrypted manifests
- `uploadSuccessMarker()`: Uploads completion marker after successful backup
- `buildRelativePath()`: Builds relative path from home directory to preserve full structure
  - For folders inside home: uses complete path from `~/` (e.g., `Library/Mobile Documents/iCloud~md~obsidian/notes/work.md`)
  - For folders outside home: uses folder name + relative path
  - Ensures proper restore to original locations and prevents path collisions between different backup folders
- `fileNeedsBackup()`: Determines if file changed by comparing size + mtime against previous snapshot manifest
- Storage structure:
  - `backup/snapshots/{timestamp}/manifest.json` - snapshot metadata (complete file list)
  - `backup/files/{full-path-from-home}/{timestamp}` - versioned file content with complete directory structure
  - `backup/.success-markers/{timestamp}` - completion markers for successful backups
  - Example: `backup/files/Library/Mobile Documents/iCloud~md~obsidian/notes/work.md/2025-12-12_143022`

**BackupCommand.swift** - Incremental backup logic
- **Incremental Manifest Updates**: Prevents orphaned files on backup interruption
  - Initial manifest uploaded at backup start (empty or with previous files)
  - Manifest re-uploaded every N files (configurable via `manifestUpdateInterval`)
  - Final manifest uploaded at backup end (with deleted files filtered)
  - Success marker uploaded after successful backup completion
  - Ensures every uploaded file is tracked in manifest, even if backup is interrupted
- **Path Length Validation**: Skips files with paths >950 bytes (B2 limit)
- **Graceful Shutdown**: Signal handlers for SIGINT/SIGTERM
  - Sets global flag instead of immediate exit
  - Allows current file upload to complete
  - Saves partial manifest with progress
  - Shows cursor and exits cleanly with appropriate exit code
  - Preserves all uploaded files for resume on next backup

**CleanupCommand.swift** - Retention and cleanup
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

**MirrorCommand.swift** - Simple mirroring (uploads all files)

**RestoreCommand.swift** - Restore functionality
- Interactive snapshot selection
- Path filtering and conflict detection
- Streaming download with encryption support
- Dry-run mode for previewing restores

**TestConfigCommand.swift** - Configuration validation
- Tests B2 authentication and bucket access
- Scans configured folders
- Checks disk space and path lengths
- Validates all settings before backup

**ListCommand.swift** - iCloud discovery
- Enumerates iCloud containers
- Shows third-party app folders with file counts

**HelpCommand.swift** - Help and version display

### Utilities (kodema/Utilities/)

**SignalHandler.swift** - Graceful shutdown
- SIGINT/SIGTERM handlers for clean exit

**RemotePath.swift** - Path building utilities

**ContentType.swift** - MIME type detection

### Command Flow

Commands are implemented in `kodema/Commands/` with entry point in `kodema/main.swift`.

**`kodema help`** (HelpCommand.swift)
- Displays usage information, available commands, and examples
- Aliases: `help`, `-h`, `--help`

**`kodema version`** (HelpCommand.swift)
- Displays the current version of Kodema
- Aliases: `version`, `-v`, `--version`
- Version string is defined in `kodema/Version.swift`

**`kodema list`** (ListCommand.swift)
1. Enumerate iCloud containers in `~/Library/Mobile Documents/`
2. Skip Apple system containers (com~apple~*)
3. Show third-party app folders with file counts and sizes
4. Helpful for discovering what to backup

**`kodema test-config [--config <path>]`** (TestConfigCommand.swift)
1. Load and validate YAML configuration file
2. Test B2 authentication and bucket access
3. Scan configured folders and check accessibility
4. Count files and calculate total size
5. Detect iCloud files not yet downloaded locally
6. Check available disk space and warn if insufficient for iCloud downloads
7. **Check path lengths** - detects files with paths exceeding B2 limit (950 bytes)
8. Display all configuration settings (filters, retention, performance, timeouts)
9. Show summary with total files and estimated size
- Supports custom config via `--config` or `-c` flag
- No modifications made to local files or remote B2 bucket
- Exits with error if configuration has issues (missing folders, auth failure, etc.)
- Shows warnings for potential issues (iCloud files not downloaded, low disk space, long paths)
- Useful for validating config before first backup or after making changes
- Disk space check: requires 20% buffer above file size for safety
- Path length check: simulates full B2 path to detect potential skips before backup

**`kodema backup [--config <path>] [--dry-run]`** (BackupCommand.swift)
1. Scan local files and apply filters
2. Fetch latest snapshot manifest from B2 (`fetchLatestManifest()`)
3. Determine which files changed by comparing with previous snapshot (`fileNeedsBackup()`)
4. **If --dry-run**: Show preview (file count, total size) and exit early
5. Sort files (local first, then iCloud)
6. Upload initial manifest to B2 (establishes snapshot immediately)
7. Upload changed files with progress tracking
   - **Path length validation**: Skips files with paths >950 bytes (B2 limit)
   - For iCloud files: checks available disk space before downloading (requires 20% buffer)
   - Skips files if insufficient disk space with warning message
   - Checks for shutdown request before each file (graceful shutdown support)
   - Skipped files (long paths, no disk space) tracked separately from failed files
8. Incrementally update manifest every N files (prevents orphaned files on interruption)
9. Upload final manifest with deleted files filtered
10. Upload success marker to indicate backup completed successfully (skipped if shutdown requested)
11. Evict iCloud files to free disk space
- Supports custom config via `--config` or `-c` flag
- Supports dry-run mode via `--dry-run` or `-n` flag
- Manifest update frequency controlled by `backup.manifestUpdateInterval` (default: 50 files)
- **Graceful shutdown**: On SIGINT/SIGTERM, finishes current file, saves partial manifest, exits cleanly
- **Dry-run**: Shows files to upload and total size without making any changes

**`kodema mirror [--config <path>]`** (MirrorCommand.swift)
1. Scan all files
2. Sort files (local first)
3. Upload all files (no change detection)
4. Simple flat structure in B2
- Supports custom config via `--config` or `-c` flag

**`kodema cleanup [--config <path>] [--dry-run]`** (CleanupCommand.swift)
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

**`kodema restore [options]`** (RestoreCommand.swift)
1. Parse restore options (snapshot, paths, output, force, list-snapshots, dry-run)
2. If `--list-snapshots`: display all available snapshots and exit
3. Get target snapshot (interactive selection or via `--snapshot` flag)
4. Filter files to restore (all or specific paths via `--path`)
5. Determine output directory (original location or `--output`)
6. **Safety warning**: If `--output` not specified (restoring to original locations), warn user and prompt for confirmation (skipped if `--force` or `--dry-run`)
7. Check for file conflicts with existing files
8. **If --dry-run**: Show preview (files, size, conflicts) and exit
9. If conflicts and no `--force`: prompt user for confirmation (skipped in dry-run)
10. Download files from B2 with progress tracking
11. Write files and restore modification timestamps
12. Report completion with success/failure counts

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
- B2 errors mapped to `B2Error` enum: `.unauthorized`, `.expiredUploadUrl`, `.rateLimited`, `.temporary`, `.client`
- Upload URL expiration (401) handled transparently with immediate retry
- Rate limits (429) trigger exponential backoff with user-visible warnings
- 5xx temporary errors trigger exponential backoff
- Client errors (4xx except 401/429) fail immediately without retry
- File-level failures tracked but don't abort entire backup

**Glob Pattern Filtering** (FileSystem/GlobMatcher.swift)
- Custom glob implementation using `fnmatch()` from Darwin
- Special handling for directory patterns: `/**` and trailing `/`
- Supports tilde expansion: `~/.Trash/**`

## Important Implementation Notes

### When Adding Features

**Config Changes**: Update both `config.example.yml` and the Decodable structs in `kodema/Models/Config.swift`

**New B2 Operations**: Follow the pattern in `kodema/Network/B2Client.swift`:
- Add response struct conforming to `Decodable` in `kodema/Network/B2Models.swift`
- Implement retry logic with `mapHTTPErrorToB2()` in `kodema/Network/B2Error.swift`
- Use `session.data(for:timeout:)` extension from `kodema/Network/URLSessionExtensions.swift`

**Progress Updates**: Call `await progress.printProgress()` before and after long operations (see `kodema/Core/ProgressTracker.swift`)

**iCloud File Handling**: Always check `checkFileStatus()` before accessing files, use `startDownloadIfNeeded()` + `waitForICloudDownload()` for cloud files (see `kodema/FileSystem/iCloudManager.swift`)

**New Commands**: Create new file in `kodema/Commands/` following existing patterns, add entry to switch statement in `kodema/main.swift`

### Testing Considerations

**No Tests Yet**: Test infrastructure not implemented

**Manual Testing Approach**:
1. Use `kodema list` to verify iCloud access
2. Test with small folder first
3. Verify uploads in B2 web interface
4. Test retention with `kodema cleanup --dry-run`

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

**Modular Architecture**: Code is organized into logical modules (28 files, ~4100 lines total)

```
kodema/
├── Models/              (4 files, ~118 lines) - Data structures
│   ├── Config.swift
│   ├── FileItem.swift
│   ├── RestoreModels.swift
│   └── Snapshot.swift
├── Core/                (3 files, ~280 lines) - Core utilities
│   ├── Constants.swift
│   ├── Helpers.swift
│   └── ProgressTracker.swift
├── Security/            (2 files, ~579 lines) - Encryption & hashing
│   ├── EncryptionManager.swift
│   └── SHA1.swift
├── FileSystem/          (3 files, ~254 lines) - File operations
│   ├── FileScanner.swift
│   ├── GlobMatcher.swift
│   └── iCloudManager.swift
├── Network/             (4 files, ~587 lines) - B2 API client
│   ├── B2Client.swift
│   ├── B2Error.swift
│   ├── B2Models.swift
│   └── URLSessionExtensions.swift
├── Commands/            (8 files, ~2040 lines) - Command implementations
│   ├── BackupCommand.swift
│   ├── CleanupCommand.swift
│   ├── HelpCommand.swift
│   ├── ListCommand.swift
│   ├── MirrorCommand.swift
│   ├── RestoreCommand.swift
│   ├── SnapshotHelpers.swift
│   └── TestConfigCommand.swift
├── Utilities/           (3 files, ~57 lines) - Helper functions
│   ├── ContentType.swift
│   ├── RemotePath.swift
│   └── SignalHandler.swift
├── main.swift           (105 lines) - Entry point with top-level await
└── Version.swift        (1 line) - Version constant
```

- Entry point: `kodema/main.swift` uses top-level await for async execution
- Version: `kodema/Version.swift` exports `KODEMA_VERSION` constant
- All files use MARK comments for internal organization
- Package.swift auto-discovers all Swift files in target directory

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

1. **iCloud Download Strategy**: Kodema uses on-demand download for iCloud files - attempts to open files with `nil` or `.notDownloaded` status, triggering macOS automatic download. This is much faster than waiting for status metadata to update. Default 30min timeout (`icloudDownloadSeconds`) should be sufficient for most files. If files have status `.current` but are actually stub files, they will be downloaded on-demand when accessed.

2. **Part Size**: Must be ≥ B2 minimum (5MB), configured in MB not bytes

3. **File Size Threshold**: Currently 5GB (see `BackupCommand.swift` and `MirrorCommand.swift`) - could make configurable

4. **Retention Cleanup**: Irreversible! Users should test policy before running cleanup

5. **B2 Rate Limits**: B2 returns 429 when API limits are hit. Kodema handles this automatically with exponential backoff (1s, 2s, 4s) and retries. `uploadConcurrency > 1` increases rate limit risk. If hitting rate limits frequently, reduce concurrency or use smaller `partSizeMB`.

6. **Signal Handling**: `setupSignalHandlers()` must be called early (see `main.swift`). Implements graceful shutdown - finishes current file and saves progress before exiting. Don't use SIGKILL (kill -9) as it bypasses graceful shutdown.

7. **Restore Memory Usage**: Now uses streaming downloads (constant ~8-16MB RAM usage regardless of file size). Manifests still load into RAM but are small (~500KB).

8. **Restore Conflicts**: Without `--force`, user must manually confirm overwrites - be careful when restoring to original location

9. **Sequential Downloads**: Restore downloads files one at a time - no parallelization (avoids B2 rate limits but slower for many small files)

10. **Manifest Update Frequency**: Low `manifestUpdateInterval` values (e.g., <10) increase B2 API calls and may slow down backup. High values (e.g., >100) mean more orphaned files if backup is interrupted. Default of 50 is a good balance.

11. **Path Length Limits**: B2 has 1000-byte limit for file names. Kodema uses 950-byte limit (safety margin). Files with longer paths (common in `node_modules`, nested projects) are automatically skipped with warning. Use `kodema test-config` to detect these before backup. Recommend using `excludeGlobs` to filter deep folder structures: `**/node_modules/**`, `**/.git/**`, `**/vendor/**`.
