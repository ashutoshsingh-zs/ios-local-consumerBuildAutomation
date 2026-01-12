# **ios-local-consumerBuildAutomation**

A local-first build automation tool enabling app-specific configurations eliminating manual copy-paste and drag-and-drop operations. It separates automation logic from the ios-consumer-app.

---

## **System Architecture**

<img width="693" height="613" alt="Screenshot 2026-01-13 at 12 06 41 AM" src="https://github.com/user-attachments/assets/4485f528-1ba8-4c36-8d55-4581513f9f42" />

---

## **Installation & Setup**

### Prerequisites
- macOS with bash
- Git installed
- Both repositories cloned locally

### Setup

- In a new terminal, enter the following command:
```bash
git config --global alias.cleanall "!git restore . && git clean -fd"
```

- Open a new terminal at the repo folder.
Then run the following command on it:

```bash
chmod +x *.sh
```

- Edit `config.env` to point to your local paths:

```bash
# Path to your app assets folder
BASE_DIR="/path/to/app-assets"

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

Run the interactive apply script to choose an app and apply its configuration:

```bash
./apply.sh
```

Notes:
- `apply.sh` is **interactive-only** and will show an indexed menu of app folders found under `BASE_DIR`.
- Scripts validate that `BASE_DIR` and `DEST` exist and that `DEST` is writable.

**What it does:**
1. Copies `Configuration.xcconfig` to the iOS repo root
2. Copies `GoogleService-Info.plist` to `Consumer/` directory
3. Replaces `Consumer/Assets/Assets.xcassets/_Configuration` with the app variant's `_Configuration` folder

**Output Example:**
```
🚀 Applying configs for: staging
✅ Config applied
✅ GoogleService-Info applied
✅ Assets replaced

🎉 Done. Build kar de boss.
```

### Reset Repository

Clean the working tree in the target iOS repository:

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

Maintain the principle of clarity and safety in all changes. Please run linters (`shellcheck`) locally before submitting PRs.

Branch naming convention:
- `bugFix/ISSUE_NUMBER/shortDescription` or `feat/ISSUE_NUMBER/shortDescription`

---

**Note:** Several quality improvements (atomic swaps, dry-run mode, backups, CI checks) are suggested for the future; they are intentionally left as feature work to be added incrementally.

