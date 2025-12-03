# Kodema

🚀 **Smart iCloud and local files backup to Backblaze B2**

Kodema is a backup tool for macOS that backs up your iCloud Drive and local files to Backblaze B2 cloud storage.

**iCloud Integration:** Automatically downloads iCloud files on-demand during backup and evicts them back to the cloud after upload to save local disk space. No manual file management needed!

## Features

✨ **Two Backup Modes:**
- 📸 **Incremental Backup** - Time Machine-style snapshots with versioning
- 🔄 **Simple Mirror** - Straightforward file sync

☁️ **Seamless iCloud Integration:**
- Automatically downloads iCloud files on-demand (no manual pre-download needed)
- Backs up files stored only in iCloud (not yet downloaded locally)
- Evicts files back to iCloud after upload to free up disk space
- Configurable timeouts for large iCloud downloads

🎯 **Smart & Efficient:**
- Only uploads changed files (size + modification time detection)
- Incremental manifest updates (prevents orphaned files on interruption)
- Graceful shutdown (Ctrl+C saves progress and allows resume)
- Streams large files for upload and download (no RAM limits)
- Configurable retry logic with exponential backoff
- Beautiful progress tracking with ETA

🗄️ **Version Management:**
- Snapshot-based architecture (restore entire system state)
- Per-file versioning (restore specific file versions)
- Time Machine-style retention policy
- Automatic cleanup of old versions
- Success markers for efficient orphan detection

💾 **Restore Capabilities:**
- Interactive snapshot selection with metadata
- Restore entire snapshots or specific files/folders
- Custom restore location support
- Conflict detection with overwrite confirmation
- Preserves original modification timestamps

🔐 **Client-Side Encryption:**
- AES-256-CBC encryption before upload to B2
- Three key storage methods: macOS Keychain, file, or passphrase
- Optional filename encryption (hides file structure)
- Streaming encryption (8MB chunks, no RAM limits)
- Mixed backups (encrypted + plain files in same backup)
- Automatic decryption on restore with skip logic

🎨 **User Friendly:**
- Discover iCloud folders with `kodema list`
- Rich terminal UI with colors and progress bars
- Flexible glob patterns for exclusions
- YAML configuration

## Quick Start

### 1. Install Kodema

**Option A: Download Pre-built Binary (Recommended)**

Visit: https://github.com/alexneisc/kodema/releases
Download kodema binary and move to /usr/local/bin/

```bash
sudo mv kodema /usr/local/bin/
cd /usr/local/bin/
chmod +x kodema
```

**Option B: Build from Source**

```bash
# Clone repository
git clone https://github.com/alexneisc/kodema.git
cd kodema

# Build and install (automatically builds release version)
make install

# Or just build without installing
make release

# Run without installing
.build/release/kodema help
```

### 2. Discover Your Files

```bash
kodema list
```

This shows all your iCloud apps and folders with file counts and sizes.

### 3. Create Config

Create `~/.config/kodema/config.yml`:

```yaml
b2:
  keyID: "your_key_id_here"
  applicationKey: "your_app_key_here"
  bucketName: "my-backup-bucket"

include:
  folders:
    - ~/Documents
    - ~/Desktop
  # Optional: backup specific files
  files:
    - ~/.ssh/config
    - ~/important-notes.txt

backup:
  remotePrefix: "backup"
  retention:
    hourly: 24
    daily: 30
    weekly: 12
    monthly: 12

# Optional: Enable encryption
encryption:
  enabled: false  # Set to true to enable encryption
  keySource: keychain
  encryptFilenames: false

mirror:
  remotePrefix: "mirror"
```

Get your B2 credentials from: https://www.backblaze.com/b2/cloud-storage.html

### 4. Validate Configuration

```bash
kodema test-config
```

This validates your config file, tests B2 connection, and shows what will be backed up.

### 5. Run Your First Backup

```bash
# Incremental backup with versioning
kodema backup

# OR simple mirror (no versioning)
kodema mirror
```

## Commands

| Command | Description |
|---------|-------------|
| `kodema test-config` | Validate configuration and test B2 connection |
| `kodema backup` | Incremental backup with snapshots |
| `kodema mirror` | Simple mirror (upload all files) |
| `kodema cleanup` | Clean up old versions per retention policy |
| `kodema restore` | Restore files from backup snapshots |
| `kodema list` | Discover iCloud folders |
| `kodema help` | Show help message |

### Configuration Testing

Before running your first backup, validate your configuration:

```bash
kodema test-config
```

This command:
- ✅ Validates YAML syntax and required fields
- ✅ Tests B2 authentication and bucket access
- ✅ Checks if configured folders exist and are readable
- ✅ Scans folders to show file counts and sizes
- ✅ Detects iCloud files not yet downloaded locally
- ✅ Checks available disk space
- ✅ Warns if not enough space for iCloud downloads
- ✅ Displays all configuration settings
- ⚠️ Shows warnings for potential issues

**Example output:**
```
Testing Kodema Configuration
═══════════════════════════════════════════════════════════════

Configuration File:
  ✓ Config loaded: ~/.config/kodema/config.yml

B2 Connection:
  ✓ Authentication successful (key: ***0002)
  ✓ Bucket found: my-backup-bucket (id: 761c061262bca...)
  ✓ API access verified

Folders and Files to Backup:
  ✓ ~/Documents (1,234 files, 2.3 GB)
  ✓ ~/Desktop (89 files, 456 MB)
  ✓ ~/.ssh/config (2 KB)

Disk Space:
  ✓ Available: 45.2 GB

Summary:
  • Total files to scan: ~1,323 files
  • Estimated size: ~2.7 GB
```

### Dry Run Mode

Preview changes before making them with the `--dry-run` (or `-n`) flag:

```bash
# Preview what would be backed up
kodema backup --dry-run

# Preview what would be deleted
kodema cleanup --dry-run

# Preview what would be restored
kodema restore --dry-run --snapshot 2024-11-27_143022
```

Dry run mode:
- Shows file counts and total sizes
- Displays conflicts (for restore)
- Does not upload, download, or delete anything
- Does not modify any remote state

## Configuration

### Minimal Config

```yaml
b2:
  keyID: "your_key_id"
  applicationKey: "your_app_key"
  bucketName: "my-backup"
```

### Full Config Example

See [BACKUP_GUIDE.md](BACKUP_GUIDE.md) for complete configuration options and examples.

## Storage Structure

### Incremental Backup
```
backup/
├── snapshots/
│   └── 2024-11-27_143022/
│       └── manifest.json         # Metadata for this snapshot
├── .success-markers/
│   └── 2024-11-27_143022         # Completion marker
└── files/
    └── Documents/
        └── myfile.txt/
            ├── 2024-11-27_143022  # Version from Nov 27
            └── 2024-11-28_091545  # Version from Nov 28
```

### Mirror
```
mirror/
└── Documents/
    └── myfile.txt            # Latest version only
```

## Retention Policy

Time Machine-style retention:

```yaml
backup:
  retention:
    hourly: 24     # Keep all snapshots from last 24 hours
    daily: 30      # Keep 1 snapshot per day for 30 days
    weekly: 12     # Keep 1 snapshot per week for 12 weeks
    monthly: 12    # Keep 1 snapshot per month for 12 months
```

- **Recent**: Maximum detail (every backup)
- **Medium term**: Daily granularity
- **Long term**: Weekly/monthly granularity
- Automatic cleanup with `kodema cleanup`

## Advanced Features

### Filters

```yaml
filters:
  excludeHidden: true
  minSizeBytes: 1024
  maxSizeBytes: 10737418240  # 10 GB
  excludeGlobs:
    - "*.tmp"
    - "**/.DS_Store"
    - "**/node_modules/**"
    - "**/.git/**"
```

### iCloud Apps

Back up specific iCloud app folders:

```yaml
include:
  folders:
    # Obsidian notes
    - ~/Library/Mobile Documents/iCloud~md~obsidian/Documents
    
    # iA Writer
    - ~/Library/Mobile Documents/27N4MQEA55~pro~writer/Documents
    
    # Standard folders
    - ~/Documents
    - ~/Desktop
```

Use `kodema list` to discover your iCloud app folders!

### Individual Files

You can also backup specific files without backing up entire folders:

```yaml
include:
  files:
    - ~/.ssh/config
    - ~/.zshrc
    - ~/important-notes.txt
    - ~/Documents/project/database.sqlite
```

This is useful for:
- Configuration files (SSH, shell configs)
- Important individual documents
- Database files
- Any files you want versioned separately

You can mix `folders` and `files` in the same config - they work together seamlessly.

### Client-Side Encryption

Kodema supports optional client-side encryption for maximum security. Files are encrypted **before** upload to B2 using AES-256-CBC.

**Basic Setup (Keychain):**
```yaml
encryption:
  enabled: true
  keySource: keychain  # Store key securely in macOS Keychain
  encryptFilenames: false
```

**File-Based Key (for sharing across machines):**
```yaml
encryption:
  enabled: true
  keySource: file
  keyFile: "~/.config/kodema/encryption-key.bin"
  encryptFilenames: false
```

**Passphrase (interactive):**
```yaml
encryption:
  enabled: true
  keySource: passphrase  # Prompt on each backup/restore
  encryptFilenames: false
```

**Maximum Security (encrypt content + filenames):**
```yaml
encryption:
  enabled: true
  keySource: keychain
  encryptFilenames: true  # Hide file structure from B2
```

**Key Features:**
- 🔒 AES-256-CBC encryption (industry standard)
- 📦 Streaming encryption (8MB chunks, no RAM limits)
- 🔑 Three key storage methods (keychain, file, passphrase)
- 🗂️ Optional filename encryption
- 🔄 Mixed backups (encrypted + plain files supported)
- ⚠️ Skip encrypted files on restore if key not available

**⚠️ Important:**
- **Keep your encryption key safe!** Without it, backups are unrecoverable
- Keychain keys are tied to your macOS user account
- For file-based keys, back up the key file separately
- Filename encryption makes backups unreadable in B2 web interface

### Timeouts

```yaml
timeouts:
  icloudDownloadSeconds: 1800    # 30 min (large files)
  networkSeconds: 300             # 5 min per request
  overallUploadSeconds: 7200      # 2 hours per file
```

### Performance Tuning

```yaml
b2:
  partSizeMB: 100                 # Part size for large files
  uploadConcurrency: 1            # Parallel uploads (beta)
  maxRetries: 3                   # Retry failed uploads

backup:
  manifestUpdateInterval: 50      # Update manifest every N files
                                  # Lower = more reliable on interruption
                                  # Higher = fewer API calls
```

## Building from Source

```bash
# Debug build
make build

# Release build (optimized)
make release

# Run without installing
.build/release/kodema help
```

### Install System-wide

```bash
# Build and install in one command
make install

# Or uninstall
make uninstall
```

## Scheduling Automatic Backups

### Using cron

```bash
# Edit crontab
crontab -e

# Add daily backup at 2 AM
0 2 * * * /usr/local/bin/kodema backup >> /var/log/kodema.log 2>&1

# Add weekly cleanup on Sundays at 3 AM
0 3 * * 0 /usr/local/bin/kodema cleanup >> /var/log/kodema-cleanup.log 2>&1
```

### Using launchd (macOS)

Create `~/Library/LaunchAgents/com.kodema.backup.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.kodema.backup</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/kodema</string>
        <string>backup</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>2</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/kodema.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/kodema.err</string>
</dict>
</plist>
```

Load it:
```bash
launchctl load ~/Library/LaunchAgents/com.kodema.backup.plist
```

## Recovery

### Restore Entire Snapshot

```bash
# List available snapshots
b2 ls my-backup-bucket backup/snapshots/

# Download manifest
b2 download-file-by-name my-backup-bucket \
  backup/snapshots/2024-11-27_143022/manifest.json \
  manifest.json

# Download all files from that snapshot
# (parse manifest.json and download each file version)
```

### Restore Single File

```bash
# From backup (specific version)
b2 download-file-by-name my-backup-bucket \
  backup/files/Documents/myfile.txt/2024-11-27_143022 \
  myfile.txt

# From mirror (latest version)
b2 download-file-by-name my-backup-bucket \
  mirror/Documents/myfile.txt \
  myfile.txt
```

### Restore Entire Directory

```bash
# Sync from mirror
b2 sync b2://my-backup-bucket/mirror/Documents ~/restored-docs
```

## Troubleshooting

### iCloud Files Won't Download
- Enable iCloud Drive in System Settings
- Check available storage space
- Increase `icloudDownloadSeconds` timeout

### Uploads Fail or Timeout
- Verify B2 credentials and bucket permissions
- Check internet connection
- Increase `networkSeconds` and `overallUploadSeconds`
- Try lower `partSizeMB` value

### "Bucket not found" Error
- Verify `bucketName` matches exactly
- Check B2 key has access to bucket
- Optionally specify `bucketId` in config

### First Backup Is Slow
- First incremental backup uploads everything (like mirror)
- Subsequent backups are much faster (only changed files)
- Use `mirror` if you always want full uploads

## Requirements

- macOS 26.0+
- Swift 6.0+
- Backblaze B2 account

## Dependencies

- [Yams](https://github.com/jpsim/Yams) - YAML parsing
- CommonCrypto - SHA1 hashing
- Foundation - File system operations

## License

MIT License - See LICENSE file for details

---

Made with ❤️ for backing up important files
