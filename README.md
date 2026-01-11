# **ios-local-consumerBuildAutomation**

This tool is a local-first build automation tool enabling app-specific configurations eliminating manual copy-paste and drag-and-drop operations. It separates automation logic from the ios-consumer-app.

---

## **System Architecture**


---

## **Installation & Setup**

### Prerequisites
- macOS with bash
- Git installed
- Both repositories cloned locally

### Configuration

Edit `config.env` to point to your local paths:

```bash
# Path to your automation base folder (contains app-specific configs)
BASE_DIR="/path/to/appAssets"

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

---

## **Usage**

### Apply Configuration

Apply a specific app's configuration to your iOS repository:

```bash
# Interactive mode (shows menu)
./apply.sh
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

---

## **Troubleshooting**

- If `replace.sh` exits with a missing-file error, verify the selected app folder contains `Configuration.xcconfig`, `GoogleService-Info.plist`, and `_Configuration/`.

- If `reset.sh` prints an error about `cleanall`, confirm the alias exists in `git config --global --list` and that it points to the intended commands.

---

## **Contributing**

Maintain the principle of clarity and safety in all changes.
Branch naming convention:
- **bugFix** or **feat** or **misc**
- issue number
- small description in **camelCase**
- e.g. **bugFix/108/configurationManagementIssue**
