# Linux Environment on Jailbroken iPhone

This document describes how to build a **self-contained Linux environment** directly on a
jailbroken iPhone, without relying on fixing APT repositories just to obtain Node.js.

## Goals

- Install and run AI CLIs (Claude Code, OpenCode, Aider, Codex, Gemini).
- Manage source code with Git.
- Edit files with nano/vim.
- Program directly on the device (Node.js, Python, C/C++, Rust, Go).

## Recommended bootstrap: Procursus (no APT repo fixing)

1. Install the Procursus bootstrap (Sileo/Procursus) on your jailbroken device.
2. Use the pre-configured mirror list shipped in this project (`/etc/apt/sources.list`).
3. Run the bootstrap script — the `.deb` ships it as a path-safe launcher:

   ```sh
   terminal-iphone          # resolves its own jailbreak root (rootful/
                            # rootless / RootHide) and runs the bootstrap
   # or copy scripts/bootstrap-iphone.sh to the device and run it with sh
   ```

   Installing the package already starts it in the background; follow along with:

   ```sh
   tail -f /var/mobile/terminal-iphone/bootstrap.log
   ```

The script installs a known-good Node.js (via nvm, independent of APT), Git, Python,
build tools and the AI CLIs — so you never have to repair APT repos to find Node.js.

## Node.js without APT

```sh
# Install nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.bashrc
# Install latest LTS Node
nvm install --lts
nvm use --lts
node --version
```

## AI CLIs

```sh
npm install -g @anthropic-ai/claude-code
npm install -g opencode
pip install aider-chat
npm install -g @openai/codex
```## In-app terminal

The native app opens a **real PTY session** using the shells above, so
`node`, `npm`, `git`, `python3`, editors and the AI CLIs run for real once the
bootstrap finishes. The browser PWA (`src/terminal-core.js`, see the README)
mirrors the same commands as a safe rehearsal space: type `bootstrap` or
`linux` for a summary, `help` for all commands.