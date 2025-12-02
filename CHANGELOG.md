# Changelog

All notable changes to Kodema will be documented in this file.

## [0.6.0] - 2025-12-03

### Added - Configuration Validation & Resource Management

#### Configuration Testing Command
- **`kodema test-config`** - Validate configuration before running backups
- **Config validation** - Checks YAML syntax and required fields
- **B2 connection test** - Verifies authentication and bucket access with API probe
- **Folder accessibility** - Ensures configured folders exist and are readable
- **File counting** - Scans folders to show file counts and total size
- **iCloud detection** - Identifies files not yet downloaded locally
- **Disk space check** - Shows available space and warns if insufficient for iCloud files
- **Settings display** - Shows all configuration settings (filters, retention, timeouts)
- **Summary output** - Total files to scan and estimated size
- **Warning system** - Flags potential issues before backup starts
- Helps catch configuration errors early and understand backup scope

#### Disk Space Validation for iCloud Downloads
- **Pre-download space check** - Validates available disk space before iCloud file downloads
- **20% safety buffer** - Requires 120% of file size to account for overhead
- **Automatic skip** - Files too large for available space are skipped with clear warnings
- **Detailed messages** - Shows required vs available space when skipping files
- **Backup continuation** - Other files continue backing up after space issues
- **test-config warning** - Estimates space needed for iCloud files and warns if insufficient
- **Failed file tracking** - Skipped files shown in final summary for retry after freeing space
- Prevents disk full situations that would cause backup failures

#### B2 Rate Limit Handling
- **429 detection** - Recognizes B2 rate limit responses (Too Many Requests)
- **Exponential backoff** - Waits 1s, 2s, 4s before retries (configurable via maxRetries)
- **User-visible warnings** - Shows clear messages: "Rate limit reached, waiting Ns before retry..."
- **Automatic retry** - Resumes upload after backoff period
- **Per-part handling** - Large file parts handled individually with rate limit awareness
- **Dedicated error case** - `.rateLimited(Int?, String)` in B2Error enum with retry-after support
- **Continued backup** - Backup continues successfully after rate limit clears
- Prevents cascading failures when hitting B2 API limits

### Changed

#### Documentation Improvements
- **iCloud integration** - Added prominent callout in README about automatic download/evict
- **Installation options** - Clear sections for downloading binary vs building from source
- **Makefile usage** - Replaced direct Swift commands with make targets throughout docs
- **FAQ optimization** - Reduced from 418 to 276 lines (34% reduction) by removing duplications
- **Cross-references** - Added links from FAQ to detailed guides (BACKUP_GUIDE, README, CLAUDE)
- **Removed INSTALLATION.md** - Content consolidated into README Quick Start
- **test-config documentation** - Added to all guides with examples and use cases
- **Disk space guidance** - Added troubleshooting for insufficient space scenarios
- **Rate limit guidance** - Added FAQ entry and mitigation strategies

#### Configuration Requirements
- **Explicit folder configuration** - Now requires folders to be explicitly listed in config
- Previously allowed defaulting to all iCloud folders, now requires conscious choice
- Prevents accidental backup of unwanted folders
- Use `kodema list` to discover folders, then configure explicitly

### Technical Details

**New Functions:**
- `getAvailableDiskSpace()` - Checks disk space using volumeAvailableCapacityForImportantUsageKey
- `testConfig()` - Comprehensive configuration validation and testing

**New Error Cases:**
- `B2Error.rateLimited(Int?, String)` - Dedicated handling for 429 rate limits
- `ConfigError.noFoldersConfigured` - Error when no folders specified
- `ConfigError.validationFailed` - General validation failure

**Modified Functions:**
- `mapHTTPErrorToB2()` - Added 429 handling, maps to .rateLimited instead of .client
- `uploadSmallFile()` - Added rate limit case with exponential backoff and user warnings
- `uploadLargeFile()` - Added rate limit handling for each part upload with progress context
- `runIncrementalBackup()` - Added disk space check before iCloud downloads (lines 2263-2274)

**Command Flow:**
- Added test-config case in main CLI switch (lines 2704-2713)
- Validates config, tests B2, scans folders, checks disk space
- No modifications to files or remote state

**Error Handling Strategy:**
- Rate limits (429): Exponential backoff with visible warnings
- Client errors (4xx except 401/429): Fail immediately without retry
- Improved separation of error types for appropriate handling

### Documentation
- Updated README.md with iCloud features, installation options, test-config command
- Updated BACKUP_GUIDE.md with test-config section and disk space features
- Optimized FAQ.md structure with cross-references and rate limit guidance
- Updated CLAUDE.md with disk space validation, rate limit handling, and error strategy
- Removed INSTALLATION.md (consolidated into README)

## [0.5.0] - 2025-11-30

### Added - Reliability & Safety Features

#### Dry-Run Mode
- **`--dry-run` flag** (also `-n`) - Preview operations without making changes
- **Backup preview** - Shows file count and total size to upload
- **Cleanup preview** - Shows snapshots to delete, orphaned files count
- **Restore preview** - Shows files to restore, size, and conflict warnings
- Safe testing of retention policies before actual cleanup
- No remote state modifications in dry-run mode

#### Incremental Manifest Updates
- **Periodic manifest uploads** during backup to prevent orphaned files
- Configurable update interval via `backup.manifestUpdateInterval` (default: 50 files)
- Reduces orphaned files from potentially thousands to maximum N files
- Initial manifest created before uploading files
- Final manifest uploaded on completion with deleted files filtered
- More reliable backup recovery on interruption

#### Success Markers & Hybrid Orphan Detection
- **Success markers** - Small completion markers distinguish complete vs incomplete backups
- **Hybrid orphan detection** - Efficient cleanup without downloading all manifests
  - Completed backups: All files with that timestamp are valid (no manifest download)
  - Incomplete backups: Download manifest to verify referenced files
- Performance: +100ms best case, +5 seconds worst case (vs +25-30 for all manifests)
- Only 0-5% of backups typically need manifest download

#### Graceful Shutdown
- **SIGINT/SIGTERM handling** - Ctrl+C allows current file to complete
- Sets shutdown flag instead of immediate exit
- Saves partial manifest with progress before exit
- Next backup resumes from checkpoint
- Clean exit with appropriate exit code (130 for SIGINT)
- Cursor visibility restored on shutdown

#### Streaming Downloads for Restore
- **Memory efficient restore** - Downloads stream directly to disk
- Constant 8-16MB RAM usage regardless of file size
- No RAM limits for large file restoration
- `downloadFileStreaming()` uses URLSession.download(for:)
- Small files (manifests) still use in-memory download

### Changed

#### Configuration
- Added `backup.manifestUpdateInterval` parameter (default: 50)
- Controls frequency of manifest updates during backup

### Technical Details

**New Functions:**
- `hasDryRunFlag()` - Parse --dry-run/-n flags from arguments
- `uploadManifest()` - Helper to create and upload snapshot manifest
- `uploadSuccessMarker()` - Create completion marker for backup
- `downloadFileStreaming()` - Stream files directly to disk
- `setShutdownRequested()`, `isShutdownRequested()` - Thread-safe shutdown flag

**Modified Functions:**
- `runCleanup()` - Added dryRun parameter, skip deletions in dry-run
- `runIncrementalBackup()` - Added dryRun parameter, manifest updates, graceful shutdown
- `runRestore()` - Added dryRun parameter, streaming downloads

**Signal Handling:**
- Global `shutdownRequested` flag with NSLock for thread safety
- Check before each file upload in backup loop
- Save partial manifest on shutdown request

**Storage Structure:**
- Added `backup/.success-markers/<timestamp>` completion markers
- Markers used to avoid downloading manifests for completed backups

### Documentation
- Updated CLAUDE.md with all new features and line numbers
- Updated README.md with dry-run examples and usage
- Updated help text with --dry-run flag documentation

## [0.4.0] - 2025-11-30

### Added - Restore Functionality

#### New Command: `kodema restore`
- **Full restore capabilities** - Recover files from backup snapshots
- **Interactive snapshot selection** - Browse snapshots with metadata (date, file count, size, age)
- **Flexible file filtering** - Restore entire snapshots or specific files/folders via `--path`
- **Custom restore location** - Use `--output` to restore to any directory (default: original location)
- **Conflict detection** - Warns before overwriting existing files with confirmation prompt
- **Force mode** - Skip confirmation with `--force` flag
- **Snapshot listing** - `--list-snapshots` shows available snapshots
- **Path-filtered listing** - Combine `--path` with `--list-snapshots` to show only relevant snapshots

#### Restore Features
- 📂 **Smart path matching** - Flexible filtering supports exact paths, prefixes, and directory components
- 💾 **Metadata preservation** - Restores original file modification timestamps
- 📊 **Progress tracking** - Download progress with speed, ETA, and file-by-file status
- ⚠️ **Error resilience** - Continues on individual file failures, shows summary at end
- 🔍 **Multiple paths** - Can specify multiple `--path` flags to restore specific files/folders

#### Examples
```bash
kodema restore                                 # Interactive selection
kodema restore --snapshot 2024-11-27_143022    # Specific snapshot
kodema restore --path folder1                  # Specific folder from latest
kodema restore --path file.txt --output ~/recovered/
kodema restore --list-snapshots                # List all snapshots
kodema restore --path folder1 --list-snapshots # Filter snapshots
```

### Fixed

#### Critical: Snapshot Manifest Completeness
- **Fixed incremental backup manifests** - Now include ALL existing files, not just changed ones
- Previous behavior: Each snapshot only tracked newly uploaded files
- New behavior: Snapshots inherit files from previous snapshot, update changed files, remove deleted files
- This ensures restore can recover complete filesystem state from any snapshot

#### Restore Path Filtering
- **Improved path matching** - Now correctly matches files at any directory level
- Supports exact match, prefix match, and directory component matching
- Works with or without trailing slashes: `folder1` = `folder1/`
- Example: `--path folder1` now matches `Documents/folder1/file.txt`

#### Snapshot Listing with Filters
- **`--list-snapshots` respects `--path` filter** - Only shows snapshots containing specified files
- Displays correct file counts for filtered paths
- Shows appropriate message when no matching snapshots found

### Changed

#### Configuration
- **`--config` flag replaces positional argument** - More explicit and standard CLI pattern
- Old: `kodema backup ~/my-config.yml`
- New: `kodema backup --config ~/my-config.yml` or `kodema backup -c ~/my-config.yml`
- Default config location unchanged: `~/.config/kodema/config.yml`

### Documentation
- Updated all docs (README, BACKUP_GUIDE, FAQ, CLAUDE.md) with restore examples
- Added restore troubleshooting section to FAQ
- Documented snapshot manifest behavior and path filtering logic

## [0.3.0] - 2025-11-28

### Added

#### New Command: `kodema version`
- Display version information: `kodema version`, `kodema -v`, `kodema --version`
- Version displayed in help message header
- Help command aliases: `-h`, `--help`

#### B2 Client Enhancements
- New `downloadFile()` method for retrieving files from B2
- New `fetchLatestManifest()` to download and parse snapshot manifests

### Fixed

#### Critical: Incremental Backup Change Detection
- **Fixed incremental backup detecting unchanged files as modified**
- Previous behavior: All files were re-uploaded on every backup run
- Root cause: Missing manifest-based comparison logic
- New behavior: Correctly compares files against previous snapshot manifest
- Impact: Significantly reduces backup time and bandwidth usage after first backup

#### Implementation
- Rewrote `fileNeedsBackup()` to use manifest-based comparison
- Compare file size and modification time against previous snapshot
- Only upload files that are new or have changed

### Documentation
- Updated CLAUDE.md with new command references and updated line numbers

## [0.2] - 2025-11-27

### Added - Major Feature Release: Incremental Backup with Versioning

#### Commands
- **NEW: `kodema backup`** - Incremental backup with snapshot-based versioning
- **NEW: `kodema cleanup`** - Automatic cleanup of old versions per retention policy
- **RENAMED: Previous behavior** - Old `backup` command is now `kodema mirror`
- Enhanced `kodema help` with better descriptions of all commands

#### Backup Features
- 📸 **Snapshot architecture** - Each backup creates a timestamped snapshot
- 🔄 **Smart incremental uploads** - Only uploads changed files (size + mtime detection)
- 📋 **Manifest files** - JSON metadata for each snapshot (easy restore planning)
- 🗂️ **Per-file versioning** - Multiple versions of same file stored efficiently
- ⚡ **Skip unchanged files** - Dramatically faster backups after first run

#### Versioning & Storage
- Hybrid storage structure: `snapshots/` for manifests + `files/` for versions
- Version timestamps in ISO format: `2024-11-27_143022`
- Restore options: entire snapshots OR individual file versions
- No dependency on B2 versioning (portable to other storage backends)

#### Retention Policy (Time Machine-style)
- **Hourly**: Keep ALL snapshots from recent hours
- **Daily**: Keep ONE snapshot per day for recent days
- **Weekly**: Keep ONE snapshot per week for recent weeks
- **Monthly**: Keep ONE snapshot per month for recent months
- Fully configurable via `backup.retention` in config
- Automatic orphaned version cleanup

#### Configuration
- New `backup:` section with `remotePrefix` and `retention` settings
- New `mirror:` section with `remotePrefix` setting
- Better config structure for future extensibility
- Full example config with detailed comments

#### B2 API Enhancements
- New `listFiles()` method for fetching existing files with prefix
- New `deleteFileVersion()` method for cleanup operations
- Pagination support for large file lists
- Better error handling for B2 operations

#### File Tracking
- Track modification dates alongside file sizes
- Build relative paths from scan roots
- Smart file change detection (size + mtime)
- Improved file metadata structures

#### Documentation
- 📖 **NEW: BACKUP_GUIDE.md** - Complete guide with examples
- 📖 **NEW: README.md** - Quick start and feature overview
- 📖 **NEW: config.example.yml** - Fully commented example config
- 📖 **NEW: CHANGELOG.md** - This file!

### Changed
- **BREAKING**: Old `kodema backup` is now `kodema mirror`
- Improved progress output with better formatting
- Enhanced help messages with mode explanations
- Better error messages for missing config sections

### Technical Details
- New data structures: `FileVersionInfo`, `SnapshotManifest`, `SnapshotInfo`
- New retention logic: `classifySnapshot()`, `selectSnapshotsToKeep()`
- Improved timestamp handling with `generateTimestamp()` and `parseTimestamp()`
- Better code organization with clear MARK sections

---

## [0.1] - 2025-11-26

### Features
- Simple backup of iCloud and local files to Backblaze B2
- iCloud file auto-download with timeout handling
- Smart file scanning with filters (size, globs, hidden files)
- Progress tracking with beautiful terminal UI
- Streaming uploads for large files (no RAM limits)
- Retry logic with exponential backoff
- `kodema list` command to discover iCloud folders
- YAML configuration support

### Supported Platforms
- macOS 26.0+

---

## Roadmap / Future Ideas

### Planned Features
- `kodema restore` command for easy file recovery
- Encryption support (client-side encryption)

### Under Consideration
- `kodema verify` command to check backup integrity
- Support for other storage backends (S3, Google Cloud, etc.)
- Compression support (gzip/zstd before upload)
- Bandwidth limiting
- Parallel file uploads (improve `uploadConcurrency`)
- Email notifications on completion/failure
- SQLite cache for faster incremental checks
- Integration with macOS Shortcuts

---

## Support

- Report bugs: Open an issue on GitHub
- Documentation: See README.md and BACKUP_GUIDE.md
