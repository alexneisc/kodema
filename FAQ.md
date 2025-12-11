# Frequently Asked Questions (FAQ)

Quick answers to common questions about Kodema. For detailed guides, see [BACKUP_GUIDE.md](BACKUP_GUIDE.md).

## Quick Start

### How do I install Kodema?

See [README.md - Quick Start](README.md#quick-start) for installation instructions.

### Where do I get B2 credentials?

1. Sign up: https://www.backblaze.com/b2/sign-up.html
2. Create bucket and application key
3. Copy Key ID and Application Key to `~/.config/kodema/config.yml`

### How do I validate my configuration?

```bash
kodema test-config
```

This checks your config, tests B2 connection, and shows what will be backed up. Always run this before your first backup!

### Where is the config file?

Default: `~/.config/kodema/config.yml`

Or specify custom path:
```bash
kodema backup --config ~/my-config.yml
```

## Backup & Restore

### What's the difference between backup and mirror?

| Feature | `kodema backup` | `kodema mirror` |
|---------|----------------|----------------|
| Versioning | ✅ Yes | ❌ No |
| Speed | ⚡ Fast (only changes) | 🐌 Slower (all files) |
| Storage | More (versions) | Less (latest only) |
| Recovery | Point-in-time | Latest only |

**TL;DR**: Use `backup` for important data with version history, `mirror` for simple syncing.

See [BACKUP_GUIDE.md - Choosing Between Backup and Mirror](BACKUP_GUIDE.md#choosing-between-backup-and-mirror) for details.

### How do I backup my files?

```bash
# Incremental backup (recommended)
kodema backup

# Simple mirror
kodema mirror
```

See [BACKUP_GUIDE.md - Commands](BACKUP_GUIDE.md#commands) for full documentation.

### How do I restore files?

```bash
# Interactive selection
kodema restore

# Restore specific snapshot
kodema restore --snapshot 2024-11-27_143022

# Restore specific file (standard ~/Documents file)
kodema restore --path Documents/myfile.txt

# Restore iCloud file
kodema restore --path "Library/Mobile Documents/iCloud~md~obsidian/notes.md"

# List available snapshots
kodema restore --list-snapshots
```

See [BACKUP_GUIDE.md - Restore](BACKUP_GUIDE.md#kodema-restore---restore-files-from-backup) for all options.

### Can I pause a backup?

Yes! Press `Ctrl+C`. The backup will finish the current file and save progress. Run `kodema backup` again to resume.

See [CLAUDE.md - Graceful Shutdown](CLAUDE.md#graceful-shutdown) for technical details.

## Configuration

### What's a good retention policy?

**Balanced** (recommended):
```yaml
backup:
  retention:
    hourly: 24     # 1 day
    daily: 30      # 1 month
    weekly: 12     # 3 months
    monthly: 12    # 1 year
```

See [BACKUP_GUIDE.md - Retention Policy](BACKUP_GUIDE.md#retention-policy-explained) for other examples.

### How do I exclude certain files?

```yaml
filters:
  excludeGlobs:
    - "*.tmp"
    - "**/.DS_Store"
    - "**/node_modules/**"
    - "**/.git/**"
```

See [BACKUP_GUIDE.md - Configuration](BACKUP_GUIDE.md#configuration) for full config examples.

### Can I backup individual files instead of entire folders?

Yes! You can specify individual files in your config:

```yaml
include:
  files:
    - ~/.ssh/config
    - ~/.zshrc
    - ~/important-notes.txt
    - ~/Documents/project/database.sqlite
```

You can also mix folders and files in the same config:

```yaml
include:
  folders:
    - ~/Documents
  files:
    - ~/.ssh/config
    - ~/important.txt
```

This is useful for:
- Configuration files (SSH, shell configs, etc.)
- Individual important documents
- Database files
- Any files you want versioned separately from folders

### Can I use multiple configs?

Yes! Use the `--config` flag:
```bash
kodema backup --config ~/.config/kodema/work.yml
kodema backup --config ~/.config/kodema/personal.yml
```

### Do I need iCloud Drive?

No! Kodema works with:
- ✅ iCloud Drive folders (auto-downloads if needed)
- ✅ Local folders (~/Documents, ~/Desktop, etc.)
- ✅ External drives
- ✅ Any accessible folder

## Scheduling & Automation

### How do I schedule automatic backups?

**Using cron:**
```bash
crontab -e

# Add these lines:
0 2 * * * /usr/local/bin/kodema backup >> /var/log/kodema.log 2>&1
0 3 * * 0 /usr/local/bin/kodema cleanup >> /var/log/kodema-cleanup.log 2>&1
```

See [README.md - Scheduling](README.md#scheduling-automatic-backups) for launchd setup.

### How often should I run cleanup?

Weekly is usually good:
```bash
# Every Sunday at 3 AM
0 3 * * 0 /usr/local/bin/kodema cleanup
```

Depends on your retention policy and how often files change.

## Troubleshooting

### Configuration validation fails

Run `kodema test-config` to see specific errors:
- Check B2 credentials are correct
- Verify bucket name matches exactly
- Ensure configured folders exist

### "Bucket not found" error

- ✅ Bucket name matches exactly (case-sensitive)
- ✅ B2 key has access to bucket
- ✅ Bucket exists in correct B2 account

### iCloud files won't download

- ✅ iCloud Drive enabled in System Settings
- ✅ Enough local disk space
- ✅ Internet connection stable

Increase timeout:
```yaml
timeouts:
  icloudDownloadSeconds: 3600  # 1 hour
```

### Not enough disk space for iCloud files

Kodema checks available disk space before downloading iCloud files. If a file is too large:

**What happens:**
- Backup skips the file with a warning
- Other files continue backing up
- Failed file shown in final summary

**Solutions:**
1. Free up disk space before backup
2. Run `kodema test-config` to see space requirements
3. Exclude large files temporarily:
   ```yaml
   filters:
     maxSizeBytes: 5368709120  # 5 GB limit
   ```

### Upload timeouts

Increase timeouts or reduce part size:
```yaml
timeouts:
  networkSeconds: 600         # 10 minutes
  overallUploadSeconds: 14400 # 4 hours

b2:
  partSizeMB: 50  # Smaller parts (default: 100)
```

### "Permission denied" errors

Check file permissions:
```bash
ls -la ~/Documents
```

Kodema needs read access to backup files.

### Files skipped: "path too long"

**What it means:**
Backblaze B2 has a 1000-byte limit for file names. Files with very long paths are automatically skipped with a warning.

**Example warning:**
```
⚠️  Skipping file with path too long (1039 bytes > 950 limit)
   Path: backup/files/Documents/Work/Project/node_modules/.../very-long-filename.js/20250103_120000
```

**Note:** Paths include full directory structure from home directory (e.g., `Documents/...`, `Library/Mobile Documents/...`).

**Why it happens:**
- Deep folder structures (e.g., `node_modules`, nested projects)
- Long folder/file names
- Each backup path includes: `backup/files/` + your path + `/timestamp`

**Solutions:**

1. **Check before backup:**
   ```bash
   kodema test-config  # Shows count of files with long paths
   ```

2. **Exclude deep structures:**
   ```yaml
   filters:
     excludeGlobs:
       - "**/node_modules/**"    # npm dependencies
       - "**/.git/objects/**"    # git internals
       - "**/vendor/**"          # package managers
   ```

3. **Use shorter backup paths:**
   ```yaml
   # Instead of:
   - ~/Documents/Work/Clients/CompanyName/Projects/ProjectName

   # Use:
   - ~/Documents/Work/Clients/CompanyName/Projects/ProjectName  # Backup this specific folder
   ```

4. **Find problematic files:**
   ```bash
   find ~/Documents -type f | awk 'length > 900 {print length, $0}' | sort -n
   ```

**What files are affected:**
- Typically development dependencies (`node_modules`, `vendor`, `.git`)
- Nested project structures
- Very long filenames combined with deep folders

**Good news:** Most important files (documents, photos, etc.) have short paths and won't be affected!

### Restore overwrites existing files

Kodema has two layers of protection:

1. **Original location warning** (if `--output` not specified):
   - Warns that files will be restored to their original locations
   - Shows "Continue" or "Cancel" options
   - Skipped with `--force` or `--dry-run`

2. **Conflict detection** (if files exist):
   - Shows which files will be overwritten
   - Asks for confirmation
   - Skipped with `--force` or `--dry-run`

Use `--force` to skip all confirmations:
```bash
kodema restore --snapshot 2024-11-27_143022 --force
```

Or restore to different location (safer):
```bash
kodema restore --output ~/restored-files/
```

Preview before restoring:
```bash
kodema restore --dry-run --snapshot 2024-11-27_143022
```

## Technical Questions

### How does change detection work?

Kodema compares:
1. File size
2. Modification time (mtime)

If either changed, the file is uploaded. Fast and reliable for most use cases.

### Does it support encryption?

Yes! Kodema now supports **client-side encryption** with AES-256-CBC:

```yaml
encryption:
  enabled: true
  keySource: keychain  # or file, or passphrase
  encryptFilenames: false  # Optional: encrypt filenames too
```

**Key features:**
- Files encrypted **before** upload to B2
- Three key storage methods (keychain, file, passphrase)
- Optional filename encryption
- **Manifest encryption** (hides backup structure and metadata)
- Streaming encryption (8MB chunks, no RAM limits)
- Mixed backups (encrypted + plain files supported)

See [BACKUP_GUIDE.md](BACKUP_GUIDE.md) for detailed setup instructions.

**⚠️ Important:** Keep your encryption key safe! Without it, backups are unrecoverable.

### What happens if upload fails?

Kodema will:
1. Retry with exponential backoff (default: 3 times)
2. Mark file as failed
3. Continue with other files
4. Show failed count at end

Run `kodema backup` again to retry failed files.

### What happens if I hit B2 rate limits?

Kodema automatically handles B2 rate limits (429 errors):
- Detects rate limit responses from B2
- Waits with exponential backoff (1s, 2s, 4s)
- Retries automatically after waiting
- Shows warning message during wait
- Continues backup after rate limit clears

**Example:**
```
⚠️  Rate limit reached, waiting 2s before retry...
```

You can reduce rate limit hits by:
- Lowering `uploadConcurrency` (default: 1)
- Using smaller `partSizeMB` for fewer API calls
- Spreading backups across different times

### Can I run multiple backups simultaneously?

Not recommended - could cause conflicts. Use sequential runs:
```bash
kodema backup --config work.yml && kodema backup --config personal.yml
```

### Does restore preserve file timestamps?

Yes! Kodema restores original modification dates from when files were backed up.

## About

### What is Kodema?

Kodema is an open source backup tool for macOS that backs up iCloud Drive and local files to Backblaze B2 cloud storage with incremental backups, versioning, and Time Machine-style retention.

### Is it free?

Yes! Kodema is open source (MIT License). You only pay for Backblaze B2 storage (very affordable).

### Is my data private?

Yes! Your data:
- ✅ Stored in your own B2 account
- ✅ Only you have access
- ✅ Not shared with anyone

**Note**: B2 has server-side encryption. Client-side encryption planned for future.

## Need More Help?

- **Detailed guides**: [BACKUP_GUIDE.md](BACKUP_GUIDE.md)
- **Technical docs**: [CLAUDE.md](CLAUDE.md)
- **Quick start**: [README.md](README.md)
- **Command help**: Run `kodema help`
- **Issues**: https://github.com/alexneisc/kodema/issues
