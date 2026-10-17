# Terminal-IPHONE

A **native terminal emulator for jailbroken iPhone** — real PTY shell sessions
(bash/zsh) with a VT100/xterm-style emulator — plus a one-shot **Linux
environment bootstrap** (Node.js via nvm, git, python3, AI CLIs) and a browser
PWA playground. The Debian package is built **entirely on Linux** with
[Theos](https://theos.dev) (`roothide/theos`) in GitHub Actions and lands in
the **`Packages/`** folder.

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

1. Get the artifact: GitHub Actions → latest run → *terminal-iphone-roothide-deb*
   artifact, or build it locally (below). The file is always:

   ```
   Packages/terminal-iphone-app-roothide_<version>_iphoneos-arm64e.deb
   ```

2. Transfer it to the device (AirDrop, SSH, or through your own Sileo repo) and open it in
   Sileo → Install, or from a shell:

   ```sh
   dpkg -i terminal-iphone-app-roothide_2.0.0_iphoneos-arm64e.deb
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

## Build the .deb (Linux)

### On GitHub Actions (default)

Push to `main` (or run the workflow manually): `Build RootHide deb (Linux)`
clones `roothide/theos`, installs the iOS toolchain + SDK on `ubuntu-latest`,
runs the test suite and uploads `Packages/*.deb` as an artifact.

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
with `dpkg-deb`, and writes the artifact into `Packages/`. See
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
- `tests/` — test suite; `Packages/` — build output (`*.deb` ignored in git)
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