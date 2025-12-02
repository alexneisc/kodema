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

# Restore specific file
kodema restore --path Documents/myfile.txt

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

### Restore overwrites existing files

By default, Kodema asks for confirmation. Use `--force` to skip:
```bash
kodema restore --snapshot 2024-11-27_143022 --force
```

Or restore to different location:
```bash
kodema restore --output ~/restored-files/
```

## Technical Questions

### How does change detection work?

Kodema compares:
1. File size
2. Modification time (mtime)

If either changed, the file is uploaded. Fast and reliable for most use cases.

### Does it support encryption?

B2 has server-side encryption. Client-side encryption is planned for future releases.

### What happens if upload fails?

Kodema will:
1. Retry with exponential backoff (default: 3 times)
2. Mark file as failed
3. Continue with other files
4. Show failed count at end

Run `kodema backup` again to retry failed files.

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
