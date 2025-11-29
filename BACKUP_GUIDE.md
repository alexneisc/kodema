# Kodema Backup Guide

## Overview

Kodema provides two backup modes for your iCloud and local files to Backblaze B2:

1. **Incremental Backup** (`kodema backup`) - Smart versioned backups with snapshots
2. **Simple Mirror** (`kodema mirror`) - Upload all files every time

## Commands

### `kodema backup` - Incremental Backup with Snapshots

Creates versioned snapshots of your files. Only uploads files that have changed (based on size + modification time).

**Features:**
- 📸 **Snapshots** - Each backup creates a timestamped snapshot
- 🔄 **Versioning** - Keeps all versions of changed files
- 🚀 **Smart uploads** - Only uploads changed files
- 🗄️ **Manifest** - JSON metadata for each snapshot
- 🧹 **Retention policy** - Automatic cleanup of old versions

**Storage structure:**
```
backup/
├── snapshots/
│   ├── 2024-11-27_143022/
│   │   └── manifest.json
│   └── 2024-11-28_091545/
│       └── manifest.json
└── files/
    └── Documents/
        ├── myfile.txt/
        │   ├── 2024-11-27_143022
        │   └── 2024-11-28_091545
        └── photo.jpg/
            └── 2024-11-27_143022
```

**Usage:**
```bash
# Use default config (~/.config/kodema/config.yml)
kodema backup

# Use custom config
kodema backup --config ~/my-config.yml
```

---

### `kodema mirror` - Simple Mirroring

Uploads all files to B2 every time, without versioning. Best for simple syncing or when you don't need version history.

**Features:**
- 📤 **Simple** - Just uploads everything
- 🔄 **No versioning** - Latest file only
- 💾 **Space efficient** - No duplicate versions

**Storage structure:**
```
mirror/
└── Documents/
    ├── myfile.txt
    └── photo.jpg
```

**Usage:**
```bash
# Use default config (~/.config/kodema/config.yml)
kodema mirror

# Use custom config
kodema mirror --config ~/my-config.yml
```

---

### `kodema cleanup` - Clean Up Old Versions

Removes old backup versions according to your retention policy (Time Machine-style).

**Usage:**
```bash
# Use default config (~/.config/kodema/config.yml)
kodema cleanup

# Use custom config
kodema cleanup --config ~/my-config.yml
```

---

### `kodema restore` - Restore Files from Backup

Restores files from backup snapshots with flexible options for snapshot selection, file filtering, and destination.

**Features:**
- 📂 **Interactive selection** - Browse available snapshots with metadata
- 🎯 **Targeted restore** - Restore specific files or folders
- 📍 **Custom location** - Restore to any directory
- ⚠️ **Conflict detection** - Warns before overwriting existing files

**Usage:**
```bash
# Interactive snapshot selection (shows list with metadata)
kodema restore

# Restore specific snapshot
kodema restore --snapshot 2024-11-27_143022

# Restore specific file from latest snapshot
kodema restore --path Documents/myfile.txt

# Restore specific folder
kodema restore --path Documents/Photos/ --snapshot 2024-11-27_143022

# Restore to custom location
kodema restore --output ~/restored-files/

# List available snapshots
kodema restore --list-snapshots

# Force overwrite without confirmation
kodema restore --snapshot 2024-11-27_143022 --force

# Combined: restore specific files to custom location
kodema restore --snapshot 2024-11-27_143022 \
  --path Documents/important.txt \
  --path Documents/Photos/ \
  --output ~/recovered/
```

**How it works:**
1. Select snapshot (interactive or via `--snapshot`)
2. Filter files to restore (all or via `--path`)
3. Check for conflicts with existing files
4. Confirm overwrites (unless `--force`)
5. Download and restore with progress tracking
6. Restore original modification timestamps

**Conflict handling:**
- Shows list of files that will be overwritten
- Options: overwrite all or cancel
- Use `--force` to skip confirmation

---

### `kodema list` - Discover iCloud Folders

Lists all iCloud Drive folders and their contents to help you configure which folders to backup.

**Usage:**
```bash
kodema list
```

---

## Configuration

### Example: Full Config with Both Modes

```yaml
# B2 credentials (required for both modes)
b2:
  keyID: "your_key_id"
  applicationKey: "your_app_key"
  bucketName: "my-backup-bucket"
  bucketId: "bucket_id_optional"
  partSizeMB: 100
  maxRetries: 3
  uploadConcurrency: 1

# Timeouts (optional)
timeouts:
  icloudDownloadSeconds: 1800    # 30 minutes
  networkSeconds: 300             # 5 minutes
  overallUploadSeconds: 7200      # 2 hours

# Folders to backup (optional - defaults to all iCloud Drive folders)
include:
  folders:
    - ~/Documents
    - ~/Desktop
    - ~/Library/Mobile Documents/iCloud~md~obsidian/Documents

# File filters (optional)
filters:
  excludeHidden: true
  minSizeBytes: 0
  maxSizeBytes: 10737418240      # 10 GB
  excludeGlobs:
    - "*.tmp"
    - "*.cache"
    - "**/node_modules/**"
    - "~/.Trash/**"

# Incremental backup settings
backup:
  remotePrefix: "backup"          # B2 path prefix
  retention:
    hourly: 24                    # Keep all versions from last 24 hours
    daily: 30                     # Keep daily snapshots for 30 days
    weekly: 12                    # Keep weekly snapshots for 12 weeks
    monthly: 12                   # Keep monthly snapshots for 12 months

# Mirror settings
mirror:
  remotePrefix: "mirror"          # B2 path prefix
```

---

## Retention Policy Explained

The retention policy uses a **Time Machine-style** approach:

```yaml
backup:
  retention:
    hourly: 24     # Last 24 hours → keep ALL snapshots
    daily: 30      # Last 30 days → keep ONE snapshot per day
    weekly: 12     # Last 12 weeks → keep ONE snapshot per week
    monthly: 12    # Last 12 months → keep ONE snapshot per month
```

**Example timeline:**
- **Today 14:00** - Snapshot created ✅ (hourly)
- **Today 10:00** - Kept ✅ (hourly)
- **Yesterday 14:00** - Kept ✅ (daily)
- **3 days ago** - Kept ✅ (daily)
- **2 weeks ago** - Kept ✅ (weekly)
- **3 months ago** - Kept ✅ (monthly)
- **13 months ago** - **Deleted** ❌ (too old)

This gives you:
- Frequent recent backups (every backup in last 24h)
- Good recent coverage (daily for a month)
- Long-term coverage (weekly/monthly for a year)

---

## Choosing Between Backup and Mirror

### Use `kodema backup` when:
✅ You need version history  
✅ You want to restore files from specific points in time  
✅ You want efficient storage (only changed files uploaded)  
✅ You need Time Machine-style retention  
✅ You care about file change history

### Use `kodema mirror` when:
✅ You just want a simple copy in the cloud  
✅ You don't need version history  
✅ You're okay with uploading all files every time  
✅ You want simplest possible setup  
✅ You have limited number of files

---

## Recovery Examples

### Restore Entire Snapshot (Backup Mode)

1. List snapshots:
```bash
# Using B2 CLI or web interface, look in:
backup/snapshots/
```

2. Download manifest:
```bash
b2 download-file-by-name my-backup-bucket \
  backup/snapshots/2024-11-27_143022/manifest.json \
  manifest.json
```

3. Restore all files from that snapshot:
```bash
# Read manifest.json and download each file version
# Example file path: backup/files/Documents/myfile.txt/2024-11-27_143022
```

### Restore Single File Version

```bash
# Download specific version
b2 download-file-by-name my-backup-bucket \
  backup/files/Documents/myfile.txt/2024-11-27_143022 \
  myfile.txt
```

### Restore from Mirror

```bash
# Download latest version
b2 download-file-by-name my-backup-bucket \
  mirror/Documents/myfile.txt \
  myfile.txt

# Or sync entire directory
b2 sync b2://my-backup-bucket/mirror ~/restored-files
```

---

## Best Practices

### 1. Start with Discovery
```bash
kodema list
```
Review what's in your iCloud Drive before configuring.

### 2. Test with Small Folder First
```yaml
include:
  folders:
    - ~/Documents/test-folder
```

### 3. Monitor First Backup
The first incremental backup will upload everything (like a mirror). Subsequent backups will be much faster.

### 4. Set Reasonable Retention
```yaml
backup:
  retention:
    hourly: 24      # 1 day
    daily: 7        # 1 week  
    weekly: 4       # 1 month
    monthly: 12     # 1 year
```
Adjust based on your needs and B2 storage costs.

### 5. Use Filters to Exclude Junk
```yaml
filters:
  excludeGlobs:
    - "*.tmp"
    - "**/.DS_Store"
    - "**/node_modules/**"
    - "**/.git/**"
```

### 6. Schedule Regular Backups
```bash
# Add to crontab for daily backups at 2 AM
0 2 * * * /usr/local/bin/kodema backup
```

### 7. Run Cleanup Regularly
```bash
# Weekly cleanup on Sundays at 3 AM
0 3 * * 0 /usr/local/bin/kodema cleanup
```

---

## Troubleshooting

### iCloud Files Not Downloading
- Ensure iCloud Drive is enabled in System Settings
- Check available local storage space
- Increase `icloudDownloadSeconds` timeout

### Upload Failures
- Check B2 credentials
- Increase `networkSeconds` timeout
- Verify internet connection
- Check B2 bucket permissions

### Large Files Failing
- Increase `partSizeMB` (default: 100)
- Increase `overallUploadSeconds` timeout
- Check if file exceeds B2's limits

### Too Many Versions
- Adjust retention policy to be more aggressive
- Run `kodema cleanup` more frequently

---

## FAQ

**Q: Can I use both backup and mirror?**  
A: Yes! Use different `remotePrefix` values in config.

**Q: Can I restore on a different computer?**  
A: Yes, use B2 CLI or web interface to download files.

**Q: What happens if backup is interrupted?**  
A: Resume by running `kodema backup` again. Already uploaded files are detected and skipped.

**Q: Does cleanup delete files immediately?**  
A: Yes, and it's permanent. Test your retention policy carefully!

---

## Need Help?

Run `kodema help` for quick command reference.

For B2 account setup: https://www.backblaze.com/b2/cloud-storage.html
