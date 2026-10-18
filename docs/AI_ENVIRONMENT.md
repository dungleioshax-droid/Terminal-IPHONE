# AI Environment on jailbroken iOS (v3.0.0 architecture)

How the Node.js/npm/AI-CLI stack in Terminal-IPHONE works, why it is reliable
where NewTerm-based setups are not, and what is currently limited.

## Why NewTerm cannot install Node.js

NewTerm is only a terminal UI — the runtime must come from APT (`apt-get
install nodejs`), but the procursus/roothide repositories do not ship a
Node.js package, so every attempt ends in `E: Unable to locate package
nodejs`. Historic "Linux userland" guides (Ubuntu `ubuntu-ports`, LXC, proot)
cannot work on iOS either: those are glibc/ELF binaries from a different
kernel ABI, and iOS is Darwin.

## What this package does instead

Everything is embedded in the Terminal-IPHONE deb itself.

```
<jbroot>/usr/local
├── bin/
│   ├── node           # wrapper: jb-root-relative, iOS V8 flags + shim preload
│   ├── npm            # wrapper -> <root>/usr/local/lib/node_modules/npm
│   ├── npx            # wrapper -> npx-cli.js
│   ├── aienv          # manager: doctor / fix-node / install-claude / python
│   ├── claude-auth    # API key + Max/Pro OAuth (PKCE, callback 127.0.0.1:19283)
│   └── claude         # (created by npm install on-device)
├── lib/
│   ├── nodejs/
│   │   ├── node               # Node.js 18.20.4 arm64 iOS binary (MJIT-entitled)
│   │   └── entitlements.xml   # dynamic-codesigning + allow-jit + no-sandbox …
│   └── node_modules/npm/...   # npm 10.8.2 (pure JS, Node ≥18)
└── share/aienv/segmenter-shim.js   # Intl.Segmenter polyfill for iOS ICU
```

- The binary is the community-proven arm64 iOS Node build (recipe from
  `imcynic/nodejs-ios`; Node.js itself is MIT + licensed fine to embed).
- Build-time (`scripts/fetch-runtime.mjs`) fetches that deb and the npm
  tarball, verifies the SHA-256 / registry sha512, and stages both into
  `build/runtime/`; the Makefile then embeds them in the final artifact.
- The device-side install is fully offline: no curl, no repo fixing, no nvm.
- Claude Code installs through npm on-device (`aienv install-claude`,
  default pinned to **2.1.19** — the newest evergreen JS release that keeps
  `engines: node>=18`; ≥2.1.113 natively re-routed to prebuilt binaries that
  cannot run on iOS).
- `claude-auth` supports both: direct `ANTHROPIC_API_KEY`, and a full
  Max/Pro OAuth flow executed inside node with a local loopback callback, so
  Safari on the same phone completes the login.

Every piece is jb-root-relative (rootless/RootHide-safe) because the
wrappers resolve `<root>` from their own location; the app also injects
`$(ROOT)/usr/local/bin` first in PATH when spawning the shell.

## Commands

```
aienv doctor              # health panel (node, npm, network, claude, auth)
aienv fix-node            # (re)install/re-sign the runtime from the deb
aienv install-claude      # pin-install claude-code (override: CLAUDE_VERSION=x.y.z)
aienv python              # best-effort python3 + pip via the jb apt repo
claude                    # run Claude Code (authenticated via claude-auth)
git, vim, less …          # from the jailbreak bootstrap (not shipped here)
```

## Performance and limits

- `--no-opt --no-sparkplug --single-threaded` puts V8 in
  interpreter + Liftoff: CPU-heavy JS ~2× slower, but agent/network work is
  full speed and stability is dramatically better.
- The `Intl.Segmenter` shim fixes V8-on-iOS ICU crashes found by the
  community (used internally by claude-code's tokenizer).
- **Not yet runnable**: Gemini CLI (needs Node ≥ 20), OpenCode/Codex CLI
  (bun/rust native binaries with no iOS target). The doctor explains; the
  practical path is either building Node 20/22 for iOS from the
  nodejs-mobile patch chain, or the experimental macOS-binary header patch —
  both tracked as roadmap work, not guaranteed today.
