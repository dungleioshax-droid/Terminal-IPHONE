# Terminal-IPHONE

A **native terminal emulator for jailbroken iPhone** — real PTY shell sessions
(bash/zsh) with a VT100/xterm-style emulator — plus a one-shot **Linux
environment bootstrap** (Node.js via nvm, git, python3, AI CLIs) and a browser
PWA playground. The Debian package is built **entirely on Linux** with
[Theos](https://theos.dev) (`roothide/theos`) in GitHub Actions and lands in
the **`dist/`** folder.

## App features

- Real shell sessions on a pseudo terminal (fork/`TIOCSCTTY`, `-l` style argv,
  `-J` style environment: `PATH`, `HOME`, `TERM=xterm-256color`, …)
- VT100/xterm emulator: 256 colors + true color, bold/italic/underline/inverse,
  scroll region, alternate screen (`vim`, `htop`), tab stops, DECALN, DSR/DA
  responses, soft wrap, combining marks (Unicode incl. tiếng Việt)
- 2000-line scrollback rendered with CoreGraphics, pan to scroll
- Accessory key bar: `esc`, `ctrl` (latched), `tab`, arrows, `- | / ~`;
  arrows also work from a hardware keyboard (incl. `ctrl`-modified → `ESC[1;5x`)
- Shell discovery that understands rootful, rootless (`/var/jb`) and
  **RootHide randomized roots** (derived from the app's own path)
- `terminal-iphone` CLI runs (or re-runs) the Linux/Node.js bootstrap

## Install via Sileo (jailbroken iPhone)

1. Download the deb straight from this repository — open
   `dist/terminal-iphone-app-roothide_2.0.0_iphoneos-arm64e.deb` and press
   *Download raw file*. The same file is also attached to every build under
   GitHub Actions → latest run → *terminal-iphone-roothide-deb* artifact, and it
   can be rebuilt locally (below). It is always named:

   ```
   dist/terminal-iphone-app-roothide_<version>_iphoneos-arm64e.deb
   ```

   > `dist/` still holds the superseded `1.0.0` packages for historical reasons.
   > Install **`2.0.0`** — the `1.0.0` builds are the old WebView wrapper and run
   > no shell on the device.

2. Transfer it to the device (AirDrop, SSH, or through your own Sileo repo) and open it in
   Sileo → Install, or from a shell:

   ```sh
   dpkg -i terminal-iphone-app-roothide_2.0.3_iphoneos-arm64e.deb
   ```

3. `postinst` registers the icon via `uicache` and starts the background
   bootstrap — follow it with:

   ```sh
   tail -f /var/mobile/terminal-iphone/bootstrap.log
   ```

   The bootstrap installs Node.js (nvm, independent of APT), git, python3 and
   the AI CLIs, so you never have to repair APT repositories just to find
   Node.js. Architecture is `iphoneos-arm64e` (RootHide/Sileo), payload paths
   are rootful-style so RootHide's dpkg relocates them into its randomized
   jailbreak root.

## Troubleshooting: app closes right after tapping the icon

2.0.3 replaces the hidden `UITextField` with a `UIView <UIKeyInput>` responder.
UIKit sends keystrokes straight to `insertText:` for a `UIKeyInput` responder,
but a `UITextField` keeps its own text machinery (and marked text, which
Vietnamese input uses), so keys could be swallowed before reaching the shell.
The navigation title now also shows `k<n>` (keys received) next to the session
state, which distinguishes "keys never arrive" from "keys arrive but the shell is
silent" without needing a log file.

2.0.2 pins the terminal view to the bottom while you have not scrolled up (before
this, output was appended below the fold and the screen looked empty), and shows a
`Terminal 2.0.3` breadcrumb plus a launch log.

2.0.1 builds the app for **arm64** and uses RootHide's documented entitlements
(`platform-application`, `no-sandbox`, `storage.AppBundles`,
`storage.AppDataContainers`); 2.0.0 was arm64e with the old ABI v1 plus a
`no-container` entitlement, which iOS 17 / RootHide kills on launch.

If it still exits, the app writes milestones to a log on disk:

```sh
cat /var/mobile/Library/Logs/terminal-iphone/launch.log
# fallback if /var/mobile is not writable: /tmp/terminal-iphone-launch.log
```

- No file at all → the process died before `main()` (loader/signature problem)
- `main()` logged, nothing after → crash inside UIKit setup
- `UNCAUGHT EXCEPTION` / `FATAL SIGNAL` lines → the exact reason

## Build the .deb (Linux)

### On GitHub Actions (default)

Push to `main` (or run the workflow manually): `Build RootHide deb (Linux)`
clones `roothide/theos`, installs the iOS toolchain + SDK on `ubuntu-latest`,
runs the test suite and uploads the fresh `dist/*.deb` as an artifact.

### Locally on any Linux box

```sh
# one-time: Theos + toolchain + SDK (see https://theos.dev/docs/installation-linux,
# or https://github.com/roothide/theos for the roothide fork)
git clone --recursive https://github.com/roothide/theos ~/theos
curl -fsSL https://github.com/L1ghtmann/llvm-project/releases/latest/download/iOSToolchain-$(uname -m).tar.xz \
  | tar -xJf - -C ~/theos/toolchain/
THEOS=~/theos ~/theos/bin/install-sdk latest

# every build (fresh or not):
THEOS=~/theos npm run build:deb      # = node scripts/build.mjs
```

`scripts/build.mjs` always runs `make package FINALPACKAGE=1
THEOS_PACKAGE_SCHEME=roothide`, verifies `Package`/`Version`/`Architecture`
with `dpkg-deb`, and writes the artifact into `dist/`. See
`docs/BUILDING.md` for details (including the bundled `plistutil` shim).

## Test

```sh
npm test    # node:test — PWA shell + build-script unit tests
```

## Project layout

- `native/` — Objective-C/UIKit app: `TIPTYSession` (PTY/fork/reap),
  `TITerminalBuffer` (cell grid + scrollback), `TITerminalParser` (VT
  state machine + UTF-8), `TITerminalView` (renderer),
  `TIKeyboardInput` (software keyboard + key bar), view controller glue
- `Makefile`, `control`, `Resources/` — Theos project, Debian control, app
  `Info.plist` + icons
- `layout/` — package payload: `DEBIAN/postinst` (uicache + background
  bootstrap) and `usr/bin/terminal-iphone` launcher
- `scripts/` — `build.mjs` (build + verify), `bootstrap-iphone.sh`
  (device-side Linux env), `plistutil` (Python shim)
- `src/terminal-core.js`, `app.js`, … — PWA playground (browser terminal)
- `tests/` — test suite; `dist/` — built `.deb` packages (committed, so they can
  be downloaded straight from the repo)
- `ios/` — legacy Swift/WebView wrapper from the old macOS/Xcode flow; kept for
  reference, not part of the Linux pipeline and not built by CI

## PWA playground

The browser build is a virtual in-memory shell (`ls`, pipes, redirection,
tab completion…) useful for rehearsing workflows:

```sh
npm install
npx http-server . -p 8080    # then open http://localhost:8080
```

See `docs/LINUX_IPHONE.md` for the device-side Linux environment.