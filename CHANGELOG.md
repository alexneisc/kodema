# Changelog

All notable changes to Kodema will be documented in this file.

## [Unreleased]

### Improved - iCloud Download Progress Indicator

#### Enhancement
- **Added visual feedback for iCloud file downloads** with animated spinner and elapsed time
- Previous implementation silently waited without user feedback
- Users couldn't tell if backup was stuck or actively downloading

#### Implementation
- Added animated spinner (⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) rotating during download
- Displays elapsed time: `☁️ ⠋ Downloading from iCloud... (15s elapsed)`
- Progress message updates every 500ms
- Properly clears progress line when download completes or times out
- Clean terminal output - no orphaned progress messages

#### Impact
- ✅ Users can see backup is actively working
- ✅ Elapsed time helps estimate if timeout adjustment needed
- ✅ Better UX during iCloud file processing
- ✅ Distinguishes between hanging and slow downloads

### Fixed - iCloud On-Demand Download

#### Problem
- **Backup hung indefinitely** when processing iCloud files with `nil` or `.notDownloaded` status
- Previous implementation only checked for `.current` status, waiting up to 30 minutes for status change
- Files were readable (macOS provides on-demand download) but kodema couldn't detect availability
- Affected files in iCloud containers where sync metadata was stale or incomplete

#### Solution
- **Implemented on-demand download detection** in `waitForICloudDownload()`
- Now attempts to open files with `nil` or `.notDownloaded` status for reading
- macOS automatically downloads file content when accessed (on-demand behavior)
- Much faster than waiting for status metadata to update (instant vs. minutes/timeout)
- Handles three status cases:
  - `.current` - File already downloaded, proceed immediately
  - `.notDownloaded` - Try to open file, triggers on-demand download
  - `nil` - Try to open file, triggers on-demand download

#### Technical Changes
- Modified `kodema/FileSystem/iCloudManager.swift`
- Added file readability check using `FileHandle(forReadingFrom:)`
- If file can be opened, considers it available regardless of status metadata
- Falls back to waiting loop if file cannot be opened yet

#### Impact
- ✅ No more hanging on iCloud files with stale metadata
- ✅ Faster backups - leverages macOS on-demand download
- ✅ Works with files that have incorrect/cached status
- ✅ More reliable for apps with non-standard iCloud sync (e.g., SnippetsLab)

## [0.9.0] - 2025-12-12

### Fixed - Path Handling for Multiple Backup Folders

#### Critical Path Structure Fix
- **Fixed file path collisions when backing up multiple folders**
- **Previous behavior**: When backing up multiple folders (e.g., different iCloud apps), files with identical relative paths would overwrite each other
  - Example: `iCloud~md~obsidian/notes/work.md` and `iCloud~com~renfei~SnippetsLab/notes/work.md` both stored as `backup/files/notes/work.md/{timestamp}`
  - Result: Files from different folders collided, losing folder context
- **New behavior**: Preserves full path structure from home directory
  - Example paths in B2:
    - `backup/files/Library/Mobile Documents/iCloud~md~obsidian/notes/work.md/{timestamp}`
    - `backup/files/Library/Mobile Documents/iCloud~com~renfei~SnippetsLab/notes/work.md/{timestamp}`
  - Each folder maintains its complete structure with no collisions

#### Implementation Changes
- **Rewrote `buildRelativePath()`** - Now preserves full path from home directory
  - For folders inside home: uses complete path from `~/` to maintain structure
  - For folders outside home: uses folder name + relative path
  - Prevents path collisions between different backup sources
- **Updated CleanupCommand comment** - Reflects new path structure in orphan detection
- **Restore behavior improved** - Files restore to correct original locations
  - Without `--output`: restores to original path (e.g., `~/Library/Mobile Documents/iCloud~md~obsidian/notes/work.md`)
  - With `--output /tmp/restore`: preserves structure in custom location (e.g., `/tmp/restore/Library/Mobile Documents/iCloud~md~obsidian/notes/work.md`)

#### Impact & Migration
- **Breaking change** - Old backups used different path structure
- **Action required**: Delete old backups and create new ones with `kodema backup`
- **Benefits**:
  - ✅ No file collisions between different folders
  - ✅ Clear identification of file origins in backup
  - ✅ Proper restore to original locations
  - ✅ Support for backing up multiple app folders simultaneously

### Technical Details

**Modified Functions:**
- `buildRelativePath()` - Complete rewrite to preserve full path structure from home directory

**Storage Structure Impact:**
- Old format: `backup/files/{relative-path}/{timestamp}`
- New format: `backup/files/{full-path-from-home}/{timestamp}`
- Example: `backup/files/Library/Mobile Documents/iCloud~md~obsidian/notes/work.md/2025-12-12_143022`

**Affected Commands:**
- `kodema backup` - Uses new path structure for all uploads
- `kodema restore` - Correctly restores to original locations
- `kodema test-config` - Validates path lengths with new structure
- `kodema cleanup` - Works with new path format (no changes needed)

## [0.8.0] - 2025-12-12

### Added - Modular Architecture, Testing Framework & Notifications

#### Modular Codebase Architecture
- **Complete architectural refactoring** - Organized into 28 focused modules for better maintainability
- **Logical module structure**:
  - `Models/` (4 files) - Data structures and configuration
  - `Core/` (3 files) - Core utilities and progress tracking
  - `Security/` (2 files) - Encryption and hashing
  - `FileSystem/` (3 files) - File scanning and iCloud integration
  - `Network/` (4 files) - Backblaze B2 API client
  - `Commands/` (8 files) - Command implementations
  - `Utilities/` (4 files) - Helper functions and notifications
  - `main.swift` - Entry point with top-level await
  - `Version.swift` - Version constant
- **Benefits**: Easier navigation, better code organization, improved testability, reduced merge conflicts
- **No functional changes** - All features work exactly the same

#### Comprehensive Test Suite
- **150 tests** across unit, integration, and E2E layers
- **Unit Tests (69 tests)**: GlobMatcher, RemotePath, ContentType, SHA1, FileChangeDetection
- **Integration Tests (79 tests)**: B2Client, Config Parsing, Encryption, Retention Policy, Snapshot Manifest
- **E2E Tests (2 tests)**: Backup and Restore workflow tests
- **Test Infrastructure**:
  - Swift Testing framework support
  - OHHTTPStubs for HTTP mocking
  - Dependency injection in B2Client for testability
  - In-memory encryption test keys for non-interactive testing
  - Strict concurrency enabled for main target
- All tests passing ✅

#### macOS Native Notifications
- **Native notification support** using osascript for operation status
- **Detailed status reporting**:
  - Success notification: All files uploaded successfully
  - Success with note: Files uploaded with skipped files
  - Warning notification: Files uploaded with failures
- **Shows operation statistics**: Uploaded files, skipped files, failed files, total size
- **Configurable** via `notifications.enabled` in config (default: true)
- **Dependency injection** with NotificationProtocol for testability
- **MockNotificationManager** for unit tests (no real notifications during testing)
- **Integrated in all commands**: backup, restore, cleanup, mirror

### Fixed

#### Code Quality Improvements
- **Fixed all Swift compiler warnings** - Clean build with zero warnings
  - Removed unnecessary type cast (Substring to Substring) in CleanupCommand
  - Replaced unused variable with underscore in ProgressTracker
  - Removed unused FileManager variable in FileScanner
  - Removed unused error tracking variable in B2Client
  - Changed var to let for non-mutated encryptor/decryptor instances in EncryptionManager
- **Improved code quality** - Better adherence to Swift best practices
- Build now completes cleanly without any warnings

#### Documentation
- **Fixed macOS version requirement** - Corrected from macOS 26.0+ to macOS 13.0+ in README and CHANGELOG
- **Updated CLAUDE.md** - Complete architecture guide for developers with module documentation

### Technical Details

**New Dependencies:**
- **OHHTTPStubs** (9.1.0) - HTTP mocking for tests

**New Files:**
- `kodema/Utilities/NotificationManager.swift` - Native macOS notification support
- `Tests/MockNotificationManager.swift` - Mock for testing
- 13 new test files organized by layer (Unit/Integration/E2E)
- `Tests/IntegrationTests/Mocks/B2ClientTestHelpers.swift` - Test utilities

**New Data Structures:**
- `NotificationConfig` - Configuration for notifications
- `NotificationProtocol` - Protocol for dependency injection
- `ProgressStats` - Statistics for operation reporting

**Modified Functions:**
- All command files updated to use notification manager
- `ProgressTracker.getStats()` - Retrieve operation statistics
- `B2Client` - Added URLSession dependency injection for testing

**Package Changes:**
- Added test target with Swift Testing framework
- Added OHHTTPStubs dependency for HTTP mocking
- StrictConcurrency enabled for better safety

## [0.7.2] - 2025-12-09

### Added - Manifest Encryption

#### Security Enhancement
- **Manifest encryption** - Snapshot manifests now encrypted when encryption is enabled
  - Hides backup structure and metadata from unauthorized access
  - Protects file paths, sizes, timestamps, and version information
  - Uses same encryption key as file encryption (AES-256-CBC)
  - Automatic encryption when `encryption.enabled = true`
  - Backward compatible with plaintext manifests (auto-detects and parses)
- **Enhanced privacy** - Complete backup metadata now hidden in encrypted storage
  - File structure no longer visible in B2 storage
  - Only encrypted binary data visible in manifest.json files
  - Requires decryption key to view any backup information

**Security Impact:** With encryption enabled, all backup data is now fully encrypted:
- File contents (encrypted)
- File names (encrypted if `encryptFilenames: true`)
- Snapshot manifests (encrypted) - **NEW**

**Implementation:**
- Added `encryptData()` and `decryptData()` methods to EncryptionManager
- Modified `uploadManifest()` to encrypt before upload
- Modified `fetchLatestManifest()` to decrypt after download
- Updated all manifest operations: backup, cleanup, restore, list-snapshots
- Content-Type changes to `application/octet-stream` for encrypted manifests

## [0.7.1] - 2025-12-09

### Fixed - Critical Encryption Bug

#### Encryption Implementation
- **Fixed RNCryptor API usage** - Corrected key-based encryption implementation
  - Previous version incorrectly tried to convert binary keys to UTF-8 strings
  - Caused SIGTRAP crash during backup with file/keychain key sources
  - Now properly uses `EncryptorV3` with separate encryption and HMAC keys
- **Updated key file format** - File-based keys now require 64 bytes (32 encryption + 32 HMAC)
  - Previous: 32 bytes (incorrect, caused crashes)
  - Current: 64 bytes (32-byte encryption key + 32-byte HMAC key)
- **Improved key generation** - Auto-generates both keys for file-based storage
  - Automatically creates 64-byte key file on first backup if missing
  - Creates config directory if it doesn't exist
- **Fixed encryption/decryption** - Separate code paths for password-based vs key-based encryption
  - Password-based: Uses `Encryptor(password:)` / `Decryptor(password:)`
  - Key-based: Uses `EncryptorV3(encryptionKey:hmacKey:)` / `DecryptorV3(encryptionKey:hmacKey:)`

#### Documentation
- **Updated BACKUP_GUIDE.md** - Corrected key generation command
  - Changed from `openssl rand ... 32` to `openssl rand ... 64`
  - Updated expected file size from 32B to 64B
  - Added explanation of dual-key requirement

**Breaking Change:** Existing encryption key files from v0.7.0 are incompatible and must be regenerated:
```bash
# Generate new 64-byte key file
openssl rand -out ~/.config/kodema/encryption-key.bin 64
```

**Note:** Backups created with v0.7.0 encryption cannot be decrypted and should be deleted.

## [0.7.0] - 2025-12-03

### Added - Encryption, Individual Files, and Path Validation

#### Client-Side Encryption
- **AES-256-CBC encryption** - Files encrypted before upload to B2
- **Three key management methods**:
  - **Keychain** - Secure storage in macOS Keychain (recommended for single-user)
  - **File** - Store key in file for sharing across machines
  - **Passphrase** - Interactive prompt on each backup/restore
- **Optional filename encryption** - Hide file structure from B2 (`encryptFilenames: true`)
- **Streaming encryption** - 8MB chunks, no RAM limits regardless of file size
- **Mixed backup support** - Encrypted and plain files can coexist in same backup
- **Smart restore** - Automatically skips encrypted files if key unavailable with warning
- **Per-file tracking** - FileVersionInfo tracks encryption status for each file
- **`.encrypted` extension** - Encrypted files marked clearly in B2 storage
- **Key generation** - Automatic key generation and secure storage on first use
- **PBKDF2 key derivation** - Passphrase-based encryption uses secure key derivation
- **Terminal password input** - Secure password input with echo disabled
- RNCryptor library integration for robust encryption implementation

#### Individual File Backup Support
- **Backup specific files** - Not just folders, can backup individual files
- **New `files` config** - Add `include.files: []` array to configuration
- **Mixed includes** - Combine folders and files in same backup config
- **File scanning** - New `scanFile()` function for individual file handling
- **Use cases**: SSH configs, shell configs, important documents, database files

#### Path Length Validation & Handling
- **B2 path limit enforcement** - Validates file paths against B2's 1000-byte limit
- **Conservative threshold** - Uses 950-byte limit (safety margin for encoding)
- **Pre-backup detection** - `test-config` scans and warns about long paths before backup
- **Runtime validation** - Checks path length before each file upload during backup
- **Automatic skip** - Files with long paths skipped with clear warning messages
- **Separate tracking** - Skipped files tracked separately from failed files in progress
- **Progress indicator** - Shows skipped count in progress bar (⏭️) and final summary
- **Warning examples** - "Skipping file with path too long (1039 bytes > 950 limit)"
- **Common causes** - Deep folder structures (node_modules, .git, nested projects)
- **Recommended fix** - Use excludeGlobs to filter deep structures: `**/node_modules/**`, `**/.git/**`
- Prevents backup failures and provides clear guidance on problematic files

### Changed

#### Configuration Structure
- **New encryption section** - `encryption:` with enabled, keySource, keyFile, keychainAccount, encryptFilenames
- **Enhanced include section** - Now supports both `folders:` and `files:` arrays
- **Encryption is optional** - All encryption features are opt-in via config

#### Build System Improvements
- **`make resolve`** - New target for explicit dependency resolution
- **`make test`** - Updated with placeholder message (tests require refactoring)
- **Enhanced help** - Updated make help with new resolve target

#### Documentation Improvements
- **Encryption documentation** - Comprehensive guides in README, BACKUP_GUIDE, FAQ, config.example.yml
- **Individual files examples** - Added examples and use cases across all docs
- **Path length documentation** - Added comprehensive troubleshooting in BACKUP_GUIDE and FAQ
- **Path length solutions** - Examples of excludeGlobs patterns and finding problematic files
- **CLAUDE.md updates** - Added encryption, individual files, path length validation details

### Technical Details

**New Dependencies:**
- **RNCryptor** (5.2.0) - AES-256-CBC encryption library

**New Data Structures:**
- `EncryptionConfig` - Configuration for encryption settings
- `EncryptionKeySource` - Enum for key source types (keychain, file, passphrase)
- `EncryptionManager` - Complete encryption manager class (~180 lines)
- Updated `FileVersionInfo` - Added encrypted, encryptedPath, encryptedSize fields
- Updated `IncludeConfig` - Added `files: [String]?` array

**New Functions:**
- `EncryptionManager.getEncryptionKey()` - Unified key retrieval with caching
- `EncryptionManager.getKeyFromKeychain()` - Keychain key management
- `EncryptionManager.getKeyFromFile()` - File-based key management
- `EncryptionManager.getKeyFromPassphrase()` - Interactive passphrase input
- `EncryptionManager.deriveKeyFromPassphrase()` - PBKDF2 key derivation
- `EncryptionManager.storeKeyInKeychain()` - Store key in macOS Keychain
- `EncryptionManager.generateAndStoreKey()` - Generate new encryption key
- `EncryptionManager.encryptFile()` - Streaming file encryption (8MB chunks)
- `EncryptionManager.decryptFile()` - Streaming file decryption (8MB chunks)
- `EncryptionManager.encryptFilename()` - Filename encryption with Base64 URL-safe
- `EncryptionManager.decryptFilename()` - Filename decryption
- `scanFile()` - Scan individual file for backup
- `buildFilesToScan()` - Build list of individual files from config

**New Constants:**
- `maxB2PathLength` - 950 bytes (safety margin below B2's 1000-byte limit)

**Modified Functions:**
- `runIncrementalBackup()` - Integrated encryption with temp file handling, path length validation
- `downloadAndRestoreFiles()` - Integrated decryption with skip logic for missing keys
- `testConfig()` - Added path length check during folder scanning
- `ProgressTracker` - Added `skippedFiles` tracking and `fileSkipped()` method

**Error Handling Strategy:**
- Path length exceeded: Skip file with warning (separate from failures)
- Encrypted file restore without key: Skip with warning and track count

### Documentation
- **README.md** - Added encryption setup guide, individual files examples
- **BACKUP_GUIDE.md** - Added encryption best practices, individual files usage, path length troubleshooting
- **FAQ.md** - Updated encryption Q&A from "planned" to implemented, path length solutions
- **config.example.yml** - Comprehensive encryption examples for all three key sources
- **CLAUDE.md** - Added encryption implementation details, individual files, path length validation
- **Makefile** - Enhanced help with new resolve target

---

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
- macOS 13.0+

---

## Support

- Report bugs: Open an issue on GitHub
- Documentation: See README.md and BACKUP_GUIDE.md
