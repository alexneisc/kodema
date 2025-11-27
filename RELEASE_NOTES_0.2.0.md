# Kodema v0.2.0 - Incremental Backup with Versioning

🎉 **Major feature release!** Kodema now supports Time Machine-style incremental backups with versioning.

## 🆕 What's New

### New Backup Mode
- **`kodema backup`** - Smart incremental backup with snapshots
  - Only uploads changed files (size + mtime detection)
  - Creates timestamped snapshots for point-in-time recovery
  - Stores multiple versions of the same file
  - JSON manifests for easy restore planning

### Retention Policy
- **`kodema cleanup`** - Automatic cleanup of old versions
  - Time Machine-style retention: hourly → daily → weekly → monthly
  - Configurable policy via `backup.retention` in config
  - Automatically removes orphaned file versions

### Renamed Command
- **`kodema mirror`** - Simple mirroring (formerly `kodema backup`)
  - Uploads all files every time
  - No versioning, just latest copy
  - Good for simple sync scenarios

## 📦 Installation

### Option 1: Download Pre-built Binary (Recommended)

**macOS Apple Silicon (M1/M2/M3):**
```bash
# Download and extract
curl -L https://github.com/YOUR_USERNAME/kodema/releases/download/v0.2.0/kodema-0.2.0-macos-arm64.tar.gz | tar xz

# Make executable and move to PATH
chmod +x kodema
sudo mv kodema /usr/local/bin/

# Verify installation
kodema help
```

**Checksum (SHA256):**
```
056e67a30551eaca3e0babf798a744f5f3d454fe0787616d5bca0f90d7641284  kodema-0.2.0-macos-arm64.tar.gz
```

### Option 2: Build from Source

```bash
git clone https://github.com/YOUR_USERNAME/kodema.git
cd kodema
swift build -c release
sudo cp .build/release/kodema /usr/local/bin/
```

**Requirements:**
- macOS 13.0+
- Swift 6.0+ (comes with Xcode Command Line Tools)

### Option 3: Using Makefile

```bash
make release
make install
```

## 🚀 Quick Start

1. **Discover your files:**
   ```bash
   kodema list
   ```

2. **Create config:**
   ```bash
   mkdir -p ~/.config/kodema
   cp config.example.yml ~/.config/kodema/config.yml
   # Edit with your B2 credentials
   ```

3. **Run your first backup:**
   ```bash
   kodema backup
   ```

## 📖 Documentation

- **[README.md](README.md)** - Quick start and features overview
- **[BACKUP_GUIDE.md](BACKUP_GUIDE.md)** - Complete backup guide with examples
- **[INSTALLATION.md](INSTALLATION.md)** - Detailed installation instructions
- **[FAQ.md](FAQ.md)** - Frequently asked questions
- **[CHANGELOG.md](CHANGELOG.md)** - Full changelog

## ⚠️ Breaking Changes

- The old `kodema backup` command is now `kodema mirror`
- If you were using the previous version, update your scripts/cron jobs

## 🐛 Known Issues

- Binary is currently available for Apple Silicon (ARM64) only
- Intel Mac users must build from source (working on universal binary)

## 📝 Full Changelog

See [CHANGELOG.md](CHANGELOG.md) for complete details.

## 🙏 Support

- Report bugs: [Open an issue](https://github.com/YOUR_USERNAME/kodema/issues)
- Questions: Check [FAQ.md](FAQ.md)
- Backblaze B2: https://www.backblaze.com/b2/cloud-storage.html

---

Made with ❤️ for backing up important files
