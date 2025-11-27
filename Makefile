# Makefile for Kodema

.PHONY: all build release clean install uninstall test help

# Default target
all: build

# Build debug version
build:
	@echo "🔨 Building Kodema (debug)..."
	swift build

# Build release version (optimized)
release:
	@echo "🚀 Building Kodema (release)..."
	swift build -c release

# Clean build artifacts
clean:
	@echo "🧹 Cleaning..."
	swift package clean
	rm -rf .build

# Install to /usr/local/bin
install: release
	@echo "📦 Installing Kodema..."
	sudo cp .build/release/kodema /usr/local/bin/kodema
	@echo "✅ Installed to /usr/local/bin/kodema"

# Uninstall from /usr/local/bin
uninstall:
	@echo "🗑️  Uninstalling Kodema..."
	sudo rm -f /usr/local/bin/kodema
	@echo "✅ Uninstalled"

# Run tests
test:
	@echo "🧪 Running tests..."
	@echo "No tests defined yet"

# Show help
help:
	@echo "Kodema Build System"
	@echo ""
	@echo "Available targets:"
	@echo "  make build     - Build debug version"
	@echo "  make release   - Build optimized release version"
	@echo "  make clean     - Clean build artifacts"
	@echo "  make install   - Install to /usr/local/bin (requires sudo)"
	@echo "  make uninstall - Remove from /usr/local/bin (requires sudo)"
	@echo "  make test      - Run tests"
	@echo "  make help      - Show this help"
	@echo ""
	@echo "Quick commands:"
	@echo "  swift run kodema help           - Run without installing"
	@echo "  .build/release/kodema help      - Run built binary"
