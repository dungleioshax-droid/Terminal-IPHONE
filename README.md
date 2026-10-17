# Terminal-IPHONE

A terminal emulator for iPhone (PWA) plus a self-contained Linux environment for
jailbroken iPhone, installable as a `.deb` via Sileo — no more fixing APT repos
to find Node.js.

## Install via Sileo (jailbroken iPhone)

1. Transfer the `.deb` to the device (AirDrop, SSH, or Sileo's "Get" from a repo).
2. Open the file in Sileo/Filza and tap Install, or run:
   ```sh
   dpkg -i terminal-iphone_1.0.0_iphoneos-arm.deb   # or iphoneos-arm64
   ```
3. The package installs `/opt/terminal-iphone`, configures a known-good APT mirror,
   and runs the bootstrap in the background (Node.js via nvm, Git, Python, editors,
   AI CLIs).

Prebuilt package (GitHub Actions, native app):
- `dist/terminal-iphone-app-roothide_1.0.0_iphoneos-arm64e.deb` — native iOS app bundle + environment (Roothide, `/var/jb`).

See `docs/LINUX_IPHONE.md` and `scripts/bootstrap-iphone.sh`.

A terminal emulator for iPhone, delivered as an installable Progressive Web App (PWA).

## Features

- Unix-like shell with a virtual in-memory filesystem
- Commands: `ls`, `cd`, `pwd`, `mkdir`, `touch`, `cat`, `rm`, `cp`, `mv`, `echo`, `grep`, `find`, `tree`, `head`, `tail`, `wc`, `clear`, `history`, `env`, `export`, `neofetch`, ...
- Redirection (`>`, `>>`), pipes (`|`), chaining (`;`, `&&`, `||`)
- Tab completion, command history (↑/↓)
- Mobile-friendly toolbar (Tab, Ctrl, arrows, Esc, Enter)
- Installable to the iPhone home screen (Add to Home Screen)
- Offline support via a service worker

## Run

```sh
npm install
npx http-server . -p 8080
```

Then open `http://localhost:8080` on your iPhone (or any browser).

## Test

```sh
npm test
```

## Project layout

- `src/terminal-core.js` — shell + virtual filesystem (shared, testable)
- `app.js` — browser UI
- `index.html`, `styles.css` — UI markup/styles
- `manifest.webmanifest`, `sw.js` — PWA metadata + offline cache
- `tests/` — node:test suite
