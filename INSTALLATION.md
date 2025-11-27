# Installation Guide

## Prerequisites

- macOS 26.0 or later
- Swift 5.9 or later (comes with Xcode Command Line Tools)
- Backblaze B2 account

## Install Swift / Xcode Command Line Tools

Check if you already have Swift:
```bash
swift --version
```

If not installed:
```bash
xcode-select --install
```

## Method 1: Build from Source (Recommended)

### 1. Clone or Download

```bash
cd ~/Downloads
# (assuming you have the kodema source code here)
cd kodema
```

### 2. Build

```bash
# Quick build
make release

# Or manually
swift build -c release
```

### 3. Install System-wide

```bash
# Install to /usr/local/bin
make install

# Or manually
sudo cp .build/release/kodema /usr/local/bin/
```

### 4. Verify Installation

```bash
kodema help
```

## Method 2: Build Without Installing

If you prefer not to install system-wide:

```bash
# Build
swift build -c release

# Run directly
.build/release/kodema help
```

Then create an alias in your shell:
```bash
# Add to ~/.zshrc or ~/.bashrc
alias kodema="/path/to/kodema/.build/release/kodema"
```

## Setup Configuration

### 1. Create Config Directory

```bash
mkdir -p ~/.config/kodema
```

### 2. Create Config File

```bash
nano ~/.config/kodema/config.yml
```

Paste this minimal config:
```yaml
b2:
  keyID: "your_key_id_here"
  applicationKey: "your_app_key_here"
  bucketName: "my-backup-bucket"

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

### 3. Get B2 Credentials

1. Sign up at https://www.backblaze.com/b2/sign-up.html
2. Create a bucket (e.g., "my-backup-bucket")
3. Create application key:
   - Go to https://secure.backblaze.com/app_keys.htm
   - Click "Add a New Application Key"
   - Give it a name (e.g., "kodema-key")
   - Allow access to your bucket
   - Copy the Key ID and Application Key

4. Update your config.yml with these credentials

## First Run

### Test Connection

```bash
kodema list
```

This will show your iCloud folders and verify B2 connection works.

### Test Backup with Small Folder

Create a test folder:
```bash
mkdir -p ~/Documents/kodema-test
echo "Hello Kodema!" > ~/Documents/kodema-test/test.txt
```

Update config to only backup this folder:
```yaml
include:
  folders:
    - ~/Documents/kodema-test
```

Run your first backup:
```bash
kodema backup
```

Check B2 web interface to verify files are uploaded!

## Scheduling Automatic Backups

### Option 1: Using cron

```bash
# Edit crontab
crontab -e

# Add daily backup at 2 AM
0 2 * * * /usr/local/bin/kodema backup >> /var/log/kodema.log 2>&1
```

### Option 2: Using launchd (macOS native)

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

## Uninstallation

### Remove Binary

```bash
# If installed with make
make uninstall

# Or manually
sudo rm /usr/local/bin/kodema
```

### Remove Config (Optional)

```bash
rm -rf ~/.config/kodema
```

### Remove launchd Job (If Using)

```bash
launchctl unload ~/Library/LaunchAgents/com.kodema.backup.plist
rm ~/Library/LaunchAgents/com.kodema.backup.plist
```

## Troubleshooting

### "command not found: swift"

Install Xcode Command Line Tools:
```bash
xcode-select --install
```

### "error: unable to invoke subcommand: /usr/bin/swift-package"

Update Xcode Command Line Tools:
```bash
sudo rm -rf /Library/Developer/CommandLineTools
xcode-select --install
```

### Build fails with "missing package"

```bash
swift package clean
swift package update
swift build -c release
```

### Permission denied when installing

Make sure you use `sudo`:
```bash
sudo cp .build/release/kodema /usr/local/bin/
```

### Can't find config file

Kodema looks for config at: `~/.config/kodema/config.yml`

Check if it exists:
```bash
ls -la ~/.config/kodema/config.yml
```

Or specify custom location:
```bash
kodema backup ~/my-custom-config.yml
```

## Getting Help

- Run `kodema help` for command reference
- Check documentation in this repository
- Review B2 documentation: https://www.backblaze.com/b2/docs/
