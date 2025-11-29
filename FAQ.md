# Frequently Asked Questions (FAQ)

Common questions about Kodema backup tool.

## General Questions

### What is Kodema?

Kodema is a backup tool for macOS that backs up your iCloud Drive and local files to Backblaze B2 cloud storage. It features incremental backups with versioning, Time Machine-style retention, and automatic cleanup.

### Is it free?

Yes! Kodema is open source (MIT License) and free to use. You only pay for Backblaze B2 storage.

### What's the difference between backup and mirror?

| Feature | `kodema backup` | `kodema mirror` |
|---------|----------------|----------------|
| Versioning | ✅ Yes | ❌ No |
| Speed | ⚡ Fast (only changes) | 🐌 Slower (all files) |
| Storage | More (versions) | Less (latest only) |
| Recovery | Point-in-time | Latest only |

**TL;DR**: Use `backup` for important stuff, `mirror` for static files.

## Installation & Setup

### How do I install Kodema?

```bash
# 1. Install Swift
xcode-select --install

# 2. Build Kodema
cd kodema && make release

# 3. Install to /usr/local/bin
make install
```

### Where do I get B2 credentials?

1. Sign up: https://www.backblaze.com/b2/sign-up.html
2. Create bucket
3. Create application key: https://secure.backblaze.com/app_keys.htm
4. Copy Key ID and Application Key to config

### Where is the config file?

Default location: `~/.config/kodema/config.yml`

Or specify custom path:
```bash
kodema backup --config ~/my-config.yml
```

### Do I need iCloud Drive?

No! Kodema works with:
- ✅ iCloud Drive folders (auto-downloads if needed)
- ✅ Local folders (~/Documents, ~/Desktop, etc.)
- ✅ External drives
- ✅ Any accessible folder

## Usage Questions

### How do I backup my files?

```bash
# Incremental backup (recommended)
kodema backup

# Simple mirror
kodema mirror
```

### How do I restore files?

Use the `kodema restore` command:

```bash
# Interactive selection - shows list of snapshots
kodema restore

# Restore specific snapshot
kodema restore --snapshot 2024-11-27_143022

# Restore specific file
kodema restore --path Documents/myfile.txt

# Restore to custom location
kodema restore --output ~/restored-files/

# List available snapshots
kodema restore --list-snapshots
```

See [BACKUP_GUIDE.md](BACKUP_GUIDE.md) for more examples.

### How do I schedule automatic backups?

Using cron:
```bash
crontab -e

# Add these lines:
0 2 * * * /usr/local/bin/kodema backup >> /var/log/kodema.log 2>&1
0 3 * * 0 /usr/local/bin/kodema cleanup >> /var/log/kodema-cleanup.log 2>&1
```

### How often should I run cleanup?

Weekly is usually good:
```bash
# Every Sunday at 3 AM
0 3 * * 0 /usr/local/bin/kodema cleanup
```

But it depends on your retention policy and how often files change.

### Can I pause a backup?

Yes! Press `Ctrl+C` to stop. Just run `kodema backup` again to resume (it will skip already-uploaded files).

## Configuration Questions

### What's a good retention policy?

**Conservative** (keeps more, costs more):
```yaml
backup:
  retention:
    hourly: 48     # 2 days
    daily: 90      # 3 months
    weekly: 52     # 1 year
    monthly: 24    # 2 years
```

**Balanced** (recommended):
```yaml
backup:
  retention:
    hourly: 24     # 1 day
    daily: 30      # 1 month
    weekly: 12     # 3 months
    monthly: 12    # 1 year
```

**Aggressive** (saves money):
```yaml
backup:
  retention:
    hourly: 6      # 6 hours
    daily: 7       # 1 week
    weekly: 4      # 1 month
    monthly: 6     # 6 months
```

### How do I exclude certain files?

```yaml
filters:
  excludeGlobs:
    - "*.tmp"                # Temp files
    - "**/.DS_Store"         # macOS metadata
    - "**/node_modules/**"   # Dependencies
    - "**/.git/**"           # Git repos
    - "*.cache"              # Cache files
```

See [config.example.yml](config.example.yml) for more patterns.

### Can I backup external drives?

Yes! Add them to your config:
```yaml
include:
  folders:
    - /Volumes/MyExternalDrive/Important
```

### Can I use multiple configs?

Yes! Specify path with --config flag:
```bash
kodema backup --config ~/configs/work.yml
kodema backup --config ~/configs/personal.yml
```

## Technical Questions

### How does change detection work?

Kodema compares:
1. File size
2. Modification time (mtime)

If either changed, the file is uploaded. This is fast and reliable for most use cases.

### Does it support encryption?

Not yet. B2 has server-side encryption, but client-side encryption is on the roadmap. See [TODO.md](TODO.md).

### Can I backup to multiple destinations?

Not directly, but you can:
1. Use different configs with different buckets
2. Run multiple commands sequentially

### What happens if upload fails?

Kodema will:
1. Retry with exponential backoff (default: 3 times)
2. Mark file as failed
3. Continue with other files
4. Show failed count at end

Just run `kodema backup` again to retry failed files.

### How much bandwidth does it use?

First backup: Uploads everything (can be large)  
Subsequent backups: Only changed files (minimal)

You can limit bandwidth by adjusting `partSizeMB`:
```yaml
b2:
  partSizeMB: 50  # Smaller = less burst bandwidth
```

### Does it work offline?

No - Kodema needs internet to upload to B2.

## Restore Questions

### How do I see which snapshots are available?

```bash
kodema restore --list-snapshots
```

This shows all snapshots with dates, file counts, and sizes.

### Can I restore just one file?

Yes! Use the `--path` flag:

```bash
kodema restore --path Documents/myfile.txt
```

You can also restore entire folders:
```bash
kodema restore --path Documents/Photos/
```

### Will restore overwrite my current files?

By default, Kodema asks for confirmation before overwriting. You'll see:
- List of files that will be overwritten
- Options to proceed or cancel

Use `--force` to skip confirmation:
```bash
kodema restore --snapshot 2024-11-27_143022 --force
```

### Can I restore to a different location?

Yes! Use `--output`:

```bash
kodema restore --output ~/restored-files/
```

This preserves the original directory structure within the output folder.

### How do I restore to a specific date?

First, list available snapshots:
```bash
kodema restore --list-snapshots
```

Then restore that snapshot:
```bash
kodema restore --snapshot 2024-11-27_143022
```

### What if restore fails partway through?

Kodema continues on errors and shows failed count at the end. Just run the restore again - it will:
- Detect already-restored files (if using `--force`)
- Or prompt you to overwrite (without `--force`)

### Does restore preserve file timestamps?

Yes! Kodema restores the original modification dates from when files were backed up.

## Troubleshooting

### "Bucket not found" error

Check:
- ✅ Bucket name matches exactly (case-sensitive)
- ✅ B2 key has access to bucket
- ✅ Bucket exists in correct B2 account

### iCloud files won't download

Check:
- ✅ iCloud Drive enabled in System Settings
- ✅ Enough local disk space
- ✅ Internet connection stable

Increase timeout:
```yaml
timeouts:
  icloudDownloadSeconds: 3600  # 1 hour
```

### Upload timeouts

Increase timeouts:
```yaml
timeouts:
  networkSeconds: 600         # 10 minutes
  overallUploadSeconds: 14400 # 4 hours
```

Or reduce part size:
```yaml
b2:
  partSizeMB: 50  # Default: 100
```

### "Permission denied" errors

Check file permissions:
```bash
ls -la ~/Documents
```

Kodema needs read access to backup files.

### Cleanup deletes too much

Test retention policy first:
```yaml
backup:
  retention:
    hourly: 48   # Increase these
    daily: 60
    weekly: 24
    monthly: 24
```

Always review what will be deleted before confirming cleanup.

### Out of memory errors

Kodema streams large files, but if you hit memory limits:

1. Reduce `partSizeMB`:
   ```yaml
   b2:
     partSizeMB: 50
   ```

2. Close other apps

3. Check for very large files (>10 GB)

## Advanced Questions

### Can I run multiple backups simultaneously?

Not recommended - could cause conflicts. Use sequential runs:
```bash
kodema backup --config work.yml && kodema backup --config personal.yml
```

### Can I backup to multiple clouds?

Not directly. Planned for future.

Workaround: Use different configs pointing to different buckets.

### Can I use it commercially?

Yes! MIT License allows commercial use.

### Is my data private?

Yes! Your data:
- ✅ Never shared with third parties
- ✅ Stored in your own B2 account
- ✅ Only you have access

**Note**: B2 has server-side encryption, but client-side encryption is planned for extra security.

## Get Help

1. **Search this FAQ** - Your question might be answered
2. **Search GitHub Issues** - Someone may have asked already
3. **Open new issue** - If problem persists
