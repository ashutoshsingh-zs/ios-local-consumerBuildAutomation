# ios-local-consumerBuildAutomation

A local-first build automation tool for iOS app ecosystems that eliminates manual configuration management and enables consistent, reproducible builds across app variants.

## Overview

This tool separates automation logic from your iOS codebase by introducing a standalone, reusable automation repository. It provides controlled operations to apply app-specific configurations and reset the working tree—eliminating manual copy-paste, drag-and-drop operations, and Xcode target selection prompts.

### Key Features

- **Centralized Configuration Management**: Store app-specific assets and configurations separately from the iOS repository
- **Isolation Layer**: Local cache acts as a buffer between external sources (Google Drive) and your iOS codebase
- **Safety-First Design**: Clear boundaries between tooling and application code; easy reset and recovery
- **Interactive App Selection**: Simple menu-driven interface for choosing which app configuration to apply
- **Extensible Architecture**: Built to support future phases (logging, version tracking, release workflows)

## System Architecture

```
Google Drive (external source)
    ↓
Local Cache (~consumerBuildAutomation/misc)
    ↓
Automation Scripts (this repository)
    ↓
iOS Repository (ios-consumer-app)
```

**Phase 1 (Current)**: Assets are manually managed in a local cache directory.  
**Future Phases**: Automated sync from Google Drive, version tracking, release workflows.

## Installation & Setup

### Prerequisites
- macOS with bash
- Git installed
- Both repositories cloned locally

### Configuration

Edit `config.env` to point to your local paths:

```bash
# Path to your automation base folder (contains app-specific configs)
BASE_DIR="/path/to/consumerBuildAutomation/misc"

# Path to the iOS consumer repository
DEST="/path/to/ios-consumer-app"
```

**Expected Directory Structure:**

```
BASE_DIR/
├── app-name-1/
│   ├── Configuration.xcconfig
│   ├── GoogleService-Info.plist
│   └── _Configuration/
├── app-name-2/
│   ├── Configuration.xcconfig
│   ├── GoogleService-Info.plist
│   └── _Configuration/
└── ...
```

Each app variant directory should contain:
- `Configuration.xcconfig`: Build settings
- `GoogleService-Info.plist`: Firebase configuration
- `_Configuration/`: Asset folder for icons, splash screens, etc.

## Usage

### Apply Configuration

Apply a specific app's configuration to your iOS repository:

```bash
# Interactive mode (shows menu)
./replace.sh

# Direct mode (with app name)
./replace.sh app-name-1
```

**What it does:**
1. Copies `Configuration.xcconfig` to the iOS repo root
2. Copies `GoogleService-Info.plist` to `Consumer/` directory
3. Replaces `Consumer/Assets/Assets.xcassets/_Configuration` with the app variant's assets

**Output Example:**
```
🚀 Applying configs for: staging
✅ Config applied
✅ GoogleService-Info applied
✅ Assets replaced

🎉 Done. Build kar de boss.
```

### Reset Repository

Discard all uncommitted changes and restore the iOS repository to a clean state:

```bash
./reset.sh
```

⚠️ **Warning**: This will remove ALL uncommitted changes. Use with caution.

## Design Principles

### 1. **Separation of Concerns**
Automation logic lives separately from the iOS codebase, reducing clutter and enabling reuse across projects.

### 2. **Safety First**
- Clear, reversible operations
- Interactive confirmations for destructive actions
- Obvious error messages with recovery suggestions

### 3. **Clarity**
- Explicit directory structure
- Self-documenting script behavior
- Emoji-based visual feedback for quick scanning

### 4. **Extensibility**
The current design anticipates:
- Automated asset synchronization from cloud storage
- Build artifact versioning and tracking
- Multi-environment release workflows
- Configuration validation and linting

## Troubleshooting

### "Missing Configuration.xcconfig"
Ensure the app variant folder exists in `BASE_DIR` and contains all required files:
```bash
ls -la "$BASE_DIR/your-app-name/"
```

### "Missing GoogleService-Info.plist"
Verify the file exists and has correct permissions:
```bash
ls -la "$BASE_DIR/your-app-name/GoogleService-Info.plist"
```

### Need to recover from accidental changes?
```bash
./reset.sh
```
Then reapply your configuration:
```bash
./replace.sh your-app-name
```

## Future Roadmap

- **Phase 2**: Automated Google Drive sync with local caching
- **Phase 3**: Build artifact versioning and changelog generation
- **Phase 4**: Multi-environment release automation
- **Phase 5**: CI/CD integration and deployment workflows

## Contributing

Improvements and optimizations welcome. Maintain the principle of clarity and safety in all changes.

---

**Motto**: Build kar de boss. 🚀
