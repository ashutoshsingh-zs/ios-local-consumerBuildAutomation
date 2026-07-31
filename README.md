# **ios-local-consumerBuildAutomation**

A local-first build automation tool enabling app-specific configurations eliminating manual copy-paste and drag-and-drop operations. It separates automation logic from the ios-consumer-app.

---

## **System Architecture**

<img width="718" height="617" alt="Screenshot 2026-07-18 at 11 31 24 PM" src="https://github.com/user-attachments/assets/feda9da4-60a6-482d-b99d-0549b092869d" />

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

Leave `CONSUMER_APP_DIR` empty and the script falls back to a sibling checkout
(`../ios-consumer-app`), so cloning this repo next to `ios-consumer-app` works as-is.

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

`apply.sh` is the only executable. It switches apps, resets back, and — with
`--screenshots` — captures App Store screenshots.

```bash
./apply.sh
```

Running it with no flags lists the flags first, then drops into the usual menu:

```
  (no flags)        Interactive: pick a letter, then an app, or reset changes
  --app NAME        Apply that app's config without prompting
  --list-apps       Print the available app names, one per line
  --reset           Reset the config paths without the Y/N prompt
  --screenshots     Capture App Store screenshots for one app
```

Notes:
- `apply.sh` is **interactive** by default: pick a letter, then an app under that letter, and the config is applied.
- For scripting, it also takes `--app <AppName>` (apply without prompting), `--list-apps` and `--reset`.
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

## **Screenshots**

```bash
./apply.sh --screenshots --check    # first run: reports what's missing and how to install it
./apply.sh --screenshots
```

**No manual steps.** An XCUITest drives the app: it sets the delivery address from the
org's pincode, then walks home → category → product → cart (adding items on the way),
capturing each screen. You start it and come back to a folder of PNGs.

Nothing beyond a clone is needed. `--check` reports your Xcode, the `ios-consumer-app`
checkout, how many apps it can see, and whether both simulators are available:

```
   Simulators:
     ✅ 6.5-inch  iPhone 14 Plus
     ⚠️  13-inch  iPad Pro 13-inch (M5) — not created yet; the run creates it automatically
```

If a simulator doesn't exist but your Xcode has the device type, the run creates it
(`xcrun simctl create`) and it stays for later runs. If your Xcode has no such device
type, the log names the fix — `xcodebuild -downloadPlatform iOS`, or
Xcode ▸ Settings ▸ Components — and lists the newest devices you *do* have so you can
point `SCREENSHOT_IPHONE_DEVICE` / `SCREENSHOT_IPAD_DEVICE` at one of them.

Produces `~/Desktop/<AppName>_Screenshots/` with the four App Store shots per screen size:

```
ZopStore_Screenshots/
├── 6.5-inch/        # iPhone 14 Plus — 1284x2778
│   ├── 01_home.png
│   ├── 02_category.png
│   ├── 03_product.png
│   └── 04_cart.png
└── 13-inch/         # iPad Pro 13-inch (M5) — 2064x2752
    └── … same four
```

**What the run does:**
1. Verifies the `ios-consumer-app` tree is clean, checks out `development`, pulls latest
2. Comments out the DEBUG-only `localThemeSelectorIcon` block in `CustomToolbarView.swift`
3. Applies the selected app's config (same code path as a normal apply)
4. Reads `DOMAIN_NAME` from the app's `config.xcconfig`, fetches `/api/organization`, and pulls
   the pincode out of the org's default address
5. Rejects any non-consumer scheme — Scarlet/GetzPH/GetzHK are separate apps
6. Resolves both simulators (creating them if needed), boots each, freezes the status bar at
   9:41, and **uninstalls the app** so every run starts from a clean install — otherwise the
   previous run's cart and delivery address carry over into the screenshots
7. Generates an XCUITest with the pincode baked in, type-checks it, and runs it through
   `xcodebuild test`. The test clears the preset address, types the pincode, picks the
   matching suggestion, acknowledges the confirmation popup, and verifies the toolbar now
   shows that pincode. Then it walks home → category → product → cart, adding
   `SCREENSHOT_CART_ITEMS` (default 3) products. Each screen is captured only once it has
   stopped loading, and "Something went wrong" gets a Retry rather than a screenshot
8. Pulls the screenshots out of the `.xcresult` and files them by slug and screen size
9. Verifies each PNG against the dimensions App Store Connect expects
10. Puts everything back on every exit path — success, failure or Ctrl-C: config reset,
    `CustomToolbarView.swift` and `ConsumerUITests.swift` reverted, simulators shut down

**The generated test replaces `ConsumerUITests/ConsumerUITests.swift` for the duration of the
run** (that target already exists in the scheme, so no project-file surgery is needed) and is
restored afterwards.

**The run streams live, one line per step.** Compile progress collapses to dots, then the test
narrates itself with the elapsed time inside the test:

```
   │   4.00s  app launching
   │  13.64s  launch loaded in 9s
   │  16.24s  setting the delivery address to 400050
   │  55.59s  address set
   │  73.26s  captured 01_home
   │ 109.90s  category loaded in 5s
   │ SCREENSHOT_NOTES:no product page reached
```

That is enough to see what is happening and which step failed. For every tap and keystroke,
set `SCREENSHOT_VERBOSE=true` in `config.env`. The complete `xcodebuild` log is always written
to `$TMPDIR/consumer-screenshots-<slot>.log` — one per device, so the iPhone log survives the
iPad leg — and the path is printed.

The test runs under a hard `SCREENSHOT_TEST_TIMEOUT` (default 1500s), so a screen it can't reach
can never hang the run: XCTest kills the test and the screenshots taken so far are still
collected.

Because the app carries no accessibility identifiers, the test works from what the app does
expose, and a few app-specific facts are load-bearing:

| Signal | Used for |
|---|---|
| `placeholder_<theme>` image count | "assets loaded" — counted for *stability*, not zero, since products without an image keep a placeholder forever |
| `"Add To Cart"` text present | a product page; listings render the same control icon-only (`addToCartText: nil`) |
| `increaseQuantity_<theme>` | the add control on a simple product's card |
| `"N options"` | a variant product — no add control on the card, so it's added from its product page instead |
| `"Something went wrong…"` / `Retry` | `NoHomeScreenView`; retried up to 3× instead of being captured |
| `"Use my current location"` | the address sheet is open (matching *any* text field caught the Search box instead) |
| `app.state != .runningForeground` | a banner deep-linked out to Safari — go back to the app and try a different tile |

**Tabs are not consistent, and that matters more than it sounds.** The categories tab is called
whatever the org calls it — `Shop` in one app, `Categories` in another — so a list of names is
matched (`categor`, `shop`, `explore`, `browse`, `collection`, `catalog`). More subtly,
**iPhone renders a real bottom `UITabBar` while iPad renders the same tabs as a pill along the
top**, where `app.tabBars` is empty. Matching only inside `app.tabBars` worked on iPhone and
silently failed on iPad: the fallback tapped a promo banner, that banner opened **Safari**, and
a Safari start page was filed as `02_category.png`. Tabs are now matched inside the tab bar *or*
anywhere in the top/bottom strip (the strip check keeps a "SHOP NOW" banner from beating the
"Shop" tab), and nothing outside the app is ever captured.

Content tiles carry no label at all, so they're found structurally: something card-sized, in the
content area, that isn't tab-bar or toolbar furniture. A category tile only ever leads to a
listing, so reaching a product page is a two-level drill — grid → listing → card.

The app is also relaunched from the home screen before the run: launching straight from the test
runner leaves a `◀ Safari`-style breadcrumb in the status bar, which is very visible on iPad and
has no place in an App Store screenshot.

⚠️ `SCREENSHOT_CART_ITEMS` is a **target, not a guarantee**. Simple products can be added from
the card; variant products ("N options") have no add control and go through their product page,
and a listing that is all variants yields fewer. The hunt also stops starting new attempts after
180s so it can't crowd out the cart screenshot itself (an attempt already in flight finishes, so
the phase can run ~30s past that). The run always reports what actually happened —
`added 2 product(s)`, or `stopped adding after 180s with 1 of 3` — so the number in the shot is
never a mystery.

If a screen can't be reached, the run says which one and points at the `xcodebuild` log rather
than silently returning three of four shots.

**Options:**

```bash
./apply.sh --screenshots --check                 # report the environment, change nothing
./apply.sh --screenshots --app ZopStore          # skip the app menu
./apply.sh --screenshots --device ipad           # iphone | ipad | both (default)
./apply.sh --screenshots --skip-git              # leave branches alone
./apply.sh --screenshots --out ~/Documents       # parent folder for the output

SCREENSHOT_VERBOSE=true ./apply.sh --screenshots # stream every tap, for debugging
```

Devices, branch, output folder and status-bar cleanup are all overridable in `config.env`.

Your original branch is *not* restored automatically; the script prints which branch it
left, so switch back yourself.

### If a run doesn't finish

Everything is reverted on exit — success, failure, Ctrl-C, `kill`, or a closed terminal (`INT`,
`TERM` and `HUP` are all trapped so the cleanup still runs). A `SIGKILL` or a power cut can't be
trapped by anything, so the **next run repairs the checkout before it starts**: it restores the
generated `ConsumerUITests.swift`, reverts the commented-out theme icon, and resets a config
left applied, then carries on from a clean slate:

```
🔧 Cleaned up leftovers from an interrupted run
```

It is deliberately conservative — if `CustomToolbarView.swift` has edits that aren't the
commented-out block, it says so and leaves the file alone rather than discarding your work.

Two runs can't overlap: a PID lock in `$TMPDIR` makes the second one exit with a clear message
instead of reverting the first one's patches mid-build. A lock from a killed run is detected as
stale and cleared automatically.

Each device's output folder is also emptied before its leg, so a shot that fails this time can
never leave last run's file sitting there looking current.

⚠️ With `--skip-git` the closing reset still restores `Configuration.xcconfig`,
`Consumer/GoogleService-Info.plist` and `_Configuration` from HEAD. If you have
uncommitted work in exactly those paths, the script warns and asks before starting.

---

## **Troubleshooting**

- If `apply.sh` exits with a missing-file error, verify the selected app folder under `Apps/` contains `config.xcconfig` and `Assets/` (`GoogleService-Info.plist` is optional — it falls back to `Apps/_default`).

- If **Reset changes** fails, confirm `CONSUMER_APP_DIR` is a git repository and that `Configuration.xcconfig`, `Consumer/GoogleService-Info.plist`, and `Consumer/Assets/Assets.xcassets/_Configuration` all exist in its last commit.

- If the screenshot run says the working tree must be clean, commit or stash your `ios-consumer-app` changes first — or pass `--skip-git` to run against the checkout exactly as it is.

- If the build fails, the compile errors are shown inline and the full `xcodebuild` log path is printed. Builds are incremental across runs (`SCREENSHOT_DERIVED_DATA`), so a re-run is much faster than the first.

- If a simulator isn't found, the run creates it when your Xcode has the device type; otherwise point `SCREENSHOT_IPHONE_DEVICE` / `SCREENSHOT_IPAD_DEVICE` at ones you do have.

- If it says **another screenshot run is already going**, one is — wait for it, or stop it. A lock left behind by a killed run is detected as stale and cleared on the next attempt.

- If a step looks wrong, re-run with `SCREENSHOT_VERBOSE=true` to see every tap, or open `$TMPDIR/consumer-screenshots-<slot>.log` for the untouched `xcodebuild` output.

- If the script can't find the `localThemeSelectorIcon` block, it has moved — comment it out by hand and re-run, or update the `BLOCK` pattern in `apply.sh`.

- If a screen comes back missing, the run names it (`missing 02_category`) plus what the test reported. The navigation heuristics live in the `UITestTemplate.swift` heredoc inside `apply.sh` — adjust the label lists there for a stubborn theme.

---

## **Contributing**

Maintain the principle of clarity and safety in all changes. Please run linters (`shellcheck`) locally before submitting PRs.

Branch naming convention:
- `bugFix/ISSUE_NUMBER/shortDescription` or `feat/ISSUE_NUMBER/shortDescription`

---

**Note:** Several quality improvements (atomic swaps, dry-run mode, backups, CI checks) are suggested for the future; they are intentionally left as feature work to be added incrementally.

