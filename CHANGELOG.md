# Changelog

All notable changes to Kodema will be documented in this file.

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
