# **ios-local-consumerBuildAutomation**

A local-first build automation tool enabling app-specific configurations eliminating manual copy-paste and drag-and-drop operations. It separates automation logic from the ios-consumer-app.

---

## **System Architecture**

<img width="628" height="564" alt="image" src="https://github.com/user-attachments/assets/3636ec3d-f14a-4a55-9500-535d187b3e20" />

---

## **Installation & Setup**

### Prerequisites
- macOS with bash
- Git installed
- `ios-consumer-app` cloned locally (alongside this repo)

### Setup

- Open a new terminal at the repo folder and run:

```bash
chmod +x apply.sh
```

- Edit `config.env` to point to your local checkout of `ios-consumer-app`:

```bash
# Path to your local checkout of ios-consumer-app.
CONSUMER_APP_DIR="/path/to/ios-consumer-app"
```

App configs are read from `$CONSUMER_APP_DIR/Apps` — the same folder structure
`ios-consumer-app`'s own `prebuild.sh` and `create_app_config.sh` scripts use —
and applied back into that same checkout, so there's nothing else to clone or configure.

**Expected Directory Structure (inside `ios-consumer-app`):**

```
Apps/
├── _default/
│   └── GoogleService-Info.plist      # fallback used when an app has none of its own
├── app-name-1/
│   ├── config.xcconfig
│   ├── GoogleService-Info.plist
│   └── Assets/
├── app-name-2/
│   ├── config.xcconfig
│   ├── GoogleService-Info.plist
│   └── Assets/
└── ...
```

Each app variant directory should contain:
- `config.xcconfig`: Build settings
- `GoogleService-Info.plist`: Firebase configuration (optional — falls back to `Apps/_default/GoogleService-Info.plist` if missing)
- `Assets/`: Asset folder for icons, splash screens, etc.

---

## **Usage**

One script handles both switching apps and resetting back — there's nothing else to run:

```bash
./apply.sh
```

Notes:
- `apply.sh` is **interactive-only**: pick a letter, then an app under that letter, and the config is applied.
- The last entry in the letter menu is always **Reset changes** instead of a letter.
- The script validates that `CONSUMER_APP_DIR` and its `Apps/` folder exist and that `CONSUMER_APP_DIR` is writable.

**What applying an app does:**
1. Copies `Apps/{app}/config.xcconfig` to `Configuration.xcconfig` at the iOS repo root
2. Copies `Apps/{app}/GoogleService-Info.plist` (or `Apps/_default/GoogleService-Info.plist` if the app has none) to `Consumer/GoogleService-Info.plist`
3. Replaces `Consumer/Assets/Assets.xcassets/_Configuration` with the app variant's `Assets/` folder

**Output Example:**
```
🚀 Applying configuration for: ZopStore
✅ Config applied
✅ GoogleService-Info applied
✅ Assets replaced

🎉 Done. ZopStore is now active — re-open Xcode (or close/reopen the project) to pick it up.
```

**Reset changes:** choosing the last menu entry restores `Configuration.xcconfig`,
`Consumer/GoogleService-Info.plist`, and `Consumer/Assets/Assets.xcassets/_Configuration`
to their last committed state via `git checkout`/`git clean`, after a Y/N confirmation.
Nothing else in `ios-consumer-app` is touched.

⚠️ **Warning**: Reset discards any uncommitted changes to those specific paths. Use with caution.

---

## **Troubleshooting**

- If `apply.sh` exits with a missing-file error, verify the selected app folder under `Apps/` contains `config.xcconfig` and `Assets/` (`GoogleService-Info.plist` is optional — it falls back to `Apps/_default`).

- If **Reset changes** fails, confirm `CONSUMER_APP_DIR` is a git repository and that `Configuration.xcconfig`, `Consumer/GoogleService-Info.plist`, and `Consumer/Assets/Assets.xcassets/_Configuration` all exist in its last commit.

---

## **Contributing**

Maintain the principle of clarity and safety in all changes. Please run linters (`shellcheck`) locally before submitting PRs.

Branch naming convention:
- `bugFix/ISSUE_NUMBER/shortDescription` or `feat/ISSUE_NUMBER/shortDescription`

---

**Note:** Several quality improvements (atomic swaps, dry-run mode, backups, CI checks) are suggested for the future; they are intentionally left as feature work to be added incrementally.

