# Changelog

All notable changes to Kodema will be documented in this file.

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
