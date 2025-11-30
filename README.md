# Kodema

🚀 **Smart iCloud and local files backup to Backblaze B2**

Kodema is a backup tool for macOS that backs up your iCloud Drive and local files to Backblaze B2 cloud storage.

## Features

✨ **Two Backup Modes:**
- 📸 **Incremental Backup** - Time Machine-style snapshots with versioning
- 🔄 **Simple Mirror** - Straightforward file sync

🎯 **Smart & Efficient:**
- Only uploads changed files (size + modification time detection)
- Incremental manifest updates (prevents orphaned files on interruption)
- Handles iCloud files automatically (downloads on-demand)
- Streams large files (no RAM limits)
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

🎨 **User Friendly:**
- Discover iCloud folders with `kodema list`
- Rich terminal UI with colors and progress bars
- Flexible glob patterns for exclusions
- YAML configuration

## Quick Start

### 1. Install Dependencies

```bash
# Install Swift Package Manager dependencies
swift build -c release
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

backup:
  remotePrefix: "backup"
  retention:
    hourly: 24
    daily: 30
    weekly: 12
    monthly: 12

mirror:
  remotePrefix: "mirror"
```

Get your B2 credentials from: https://www.backblaze.com/b2/cloud-storage.html

### 4. Run Your First Backup

```bash
# Incremental backup with versioning
kodema backup

# OR simple mirror (no versioning)
kodema mirror
```

## Commands

| Command | Description |
|---------|-------------|
| `kodema backup` | Incremental backup with snapshots |
| `kodema mirror` | Simple mirror (upload all files) |
| `kodema cleanup` | Clean up old versions per retention policy |
| `kodema restore` | Restore files from backup snapshots |
| `kodema list` | Discover iCloud folders |
| `kodema help` | Show help message |

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
swift build

# Release build (optimized)
swift build -c release

# Run
.build/release/kodema help
```

### Install System-wide

```bash
swift build -c release
sudo cp .build/release/kodema /usr/local/bin/
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
