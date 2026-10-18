# Terminal-IPHONE

A **native terminal emulator for jailbroken iPhone** — real PTY shell sessions
(bash/zsh) with a VT100/xterm-style emulator — plus a **self-contained AI
environment**: Node.js 18.20.4 (arm64 iOS) + npm 10 inside the same .deb, an
`aienv` manager, `claude-auth` and Claude Code (installed on-device through
npm with the community-verified V8/iOS flags). Built **entirely on Linux**
with [Theos](https://theos.dev) (`roothide/theos`) in GitHub Actions incl.
the iOS toolchain, and the artifact always lands in **`dist/`**.

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

## The embedded AI environment (v3.0.0)

Unlike NewTerm (and unlike everything you get by repairing APT repos on
Sileo), this package ships its own runtime, verified per-artifact at build
time:

| Piece | Version | Where |
|---|---|---|
| Node.js binary (arm64 iOS, JIT-entitled, community recipe) | 18.20.4 | `<root>/usr/local/lib/nodejs/node` |
| UI V8 flags + Intl.Segmenter shim | — | wrapper `<root>/usr/local/bin/node` + `<root>/usr/local/share/aienv/segmenter-shim.js` |
| npm | 10.8.2 | `<root>/usr/local/lib/node_modules/npm` |
| `aienv` manager | 3.0 | `<root>/usr/local/bin/aienv` |
| `claude-auth` | 3.0 | `<root>/usr/local/bin/claude-auth` |
| Claude Code | pinned JS release (2.1.19 default) | installed on-device by `aienv install-claude` |

After install, inside the app simply:

```
aienv doctor
claude-auth      # API key, or Max/Pro OAuth (opens Safari, callback 127.0.0.1:19283)
claude
```

Roadmap notes: Gemini CLI needs Node ≥ 20 and OpenCode/Codex ship native bun/rust
binaries (no iOS build), so they are not installable with Node 18 today. The
`aienv` doctor explains this; work is tracked in `docs/AI_ENVIRONMENT.md`.

## Install via Sileo (jailbroken iPhone)

1. Download the deb straight from this repository — open
   `dist/terminal-iphone-app-roothide_<version>_iphoneos-arm64e.deb` and press
   *Download raw file*. The same file is also attached to every build under
   GitHub Actions → latest run → artifact, and it can be rebuilt locally
   (below).

2. Transfer it to the device (AirDrop, SSH, or through your own Sileo repo) and open it in
   Sileo → Install, or from a shell:

   ```sh
   dpkg -i terminal-iphone-app-roothide_3.0.0_iphoneos-arm64e.deb
   ```

3. `postinst` registers the icon via `uicache`, re-signs the Node binary with
   the JIT entitlements (needs `ldid`, which the RootHide/Procursus bootstrap
   already provides) and starts the background bootstrap — follow it with:

   ```sh
   tail -f /var/mobile/terminal-iphone/aienv.log     # bootstrap log
   # later, in the Terminal app:
   aienv doctor                                      # full health panel
   ```

## Troubleshooting: app closes right after tapping the icon

2.0.3 replaced the hidden `UITextField` with a `UIView <UIKeyInput>` responder.
2.0.2 pinned the terminal view to the bottom while you have not scrolled up.
2.0.1 builds the app for **arm64** with the documented RootHide entitlements
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

## Node.js crashes (v3)

The wrapper applies the V8 flags the community proved stable (`--no-opt`,
`--no-sparkplug`, `--single-threaded`, …) so Claude Code runs in interpreter
mode + Liftoff WASM. If you ever see `Illegal instruction` / `Killed`:

```sh
aienv fix-node    # re-installs and re-signs <root>/usr/local/lib/nodejs/node
```

Performance note: with `--no-opt` expect roughly 2× slower for CPU-heavy
code; the agent loop (network + prompt handling) runs at normal speed.

## Build the .deb (Linux)

### On GitHub Actions (default)

Push to `main` (or run the workflow manually): `Build RootHide deb (Linux)`
clones `roothide/theos`, installs the iOS toolchain + SDK on `ubuntu-latest`,
runs the test suite and uploads the fresh `dist/*.deb` as an artifact — and
`scripts/fetch-runtime.mjs` fetches + verifies the Node/npm payloads
(SHA-256 + npm-registry sha512) before `make package` embeds them.

### NewTerm 3 AI (second app — macOS runner)

`newterm/` is an Xcode app built through Theos, so it needs a Mac:
`.github/workflows/newterm-ios.yml` runs on `macos-14`, but only when files
under `newterm/` change (or via *Run workflow*). It publishes
`newterm3-ai-rootless` (`iphoneos-arm64`) and `newterm3-ai-roothide`
(`iphoneos-arm64e`) artifacts.

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

`scripts/build.mjs` stages the runtime (`scripts/fetch-runtime.mjs`,
`SKIP_RUNTIME=1` to skip), then runs `make package FINALPACKAGE=1
THEOS_PACKAGE_SCHEME=roothide`, verifies `Package`/`Version`/`Architecture`
with `dpkg-deb`, and writes the artifact into `dist/`. See `docs/BUILDING.md`
for details (including the bundled `plistutil` shim).

## Test

```sh
npm test    # node:test — PWA shell + build-script + layout/runtime tests
```

## Project layout

- `native/` — Objective-C/UIKit app: `TIPTYSession` (PTY/fork/reap),
  `TITerminalBuffer` (cell grid + scrollback), `TITerminalParser` (VT
  state machine + UTF-8), `TITerminalView` (renderer),
  `TIKeyboardInput` (software keyboard + key bar), view controller glue
- `Makefile`, `control`, `Resources/` — Theos project, Debian control, app
  `Info.plist` + icons
- `layout/` — package payload: `DEBIAN/postinst` (uicache + re-sign +
  background bootstrap), `usr/local/bin/{node,npm,npx,aienv,claude-auth}`
  wrappers + `usr/local/share/aienv/segmenter-shim.js`, and the legacy
  `usr/bin/terminal-iphone` launcher
- `scripts/` — `build.mjs` (build + verify), `fetch-runtime.mjs` (Node.js +
  npm payload fetcher/integrator), `bootstrap-iphone.sh` (thin device-side
  bootstrap), `plistutil` (Python shim)
- `src/terminal-core.js`, `app.js`, … — PWA playground (browser terminal)
- `tests/` — test suite; `dist/` — built `.deb` packages (committed, so they
  can be downloaded straight from the repo)
- `newterm/` — **NewTerm 3 AI**: NewTerm 3 (hbang/NewTerm) integrated into
  this repo as a full iOS app with the same embedded AI environment — Node.js
  18 + npm in the .deb, `aienv`/`claude-auth`, PATH symlinks, postinst
  bootstrap and a new *Settings → AI CLI* screen. Built by
  `.github/workflows/newterm-ios.yml` on macOS runners (Xcode/Theos). See
  `newterm/README-AI.md`.
- `ios/` — legacy Swift/WebView wrapper from the old macOS/Xcode flow; kept
  for reference, not part of the Linux pipeline and not built by CI
- `docs/` — `BUILDING.md` (compile details) and `AI_ENVIRONMENT.md`
  (runtime architecture + roadmap)

## PWA playground

The browser build is a virtual in-memory shell (`ls`, pipes, redirection,
tab completion…) useful for rehearsing workflows:

```sh
npm install
npx http-server . -p 8080    # then open http://localhost:8080
```
