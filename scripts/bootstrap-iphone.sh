#!/usr/bin/env sh
# Bootstrap a self-contained Linux environment on a jailbroken iPhone.
# Avoids fixing APT repositories just to obtain Node.js by using nvm.

set -e

echo "[*] Terminal iPhone Linux bootstrap"

# 1. Ensure Procursus-style directories
mkdir -p /opt /usr/local/bin /var/lib/dpkg 2>/dev/null || true

# 2. Refresh package lists using a known-good mirror (no repo fixing needed)
if command -v apt-get >/dev/null 2>&1; then
  cat > /etc/apt/sources.list <<'EOF'
deb http://ports.ubuntu.com/ubuntu-ports jammy main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports jammy-updates main restricted universe multiverse
EOF
  apt-get update || true
  apt-get install -y --no-install-recommends \
    git curl wget build-essential python3 python3-pip ca-certificates tar unzip || true
fi

# 3. Install Node.js via nvm (independent of APT)
if ! command -v node >/dev/null 2>&1; then
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ ! -d "$NVM_DIR" ]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  fi
  . "$NVM_DIR/nvm.sh"
  nvm install --lts
  nvm use --lts
  nvm alias default lts/*
fi

# 4. Install AI CLIs
if command -v npm >/dev/null 2>&1; then
  npm install -g @anthropic-ai/claude-code 2>/dev/null || true
  npm install -g opencode 2>/dev/null || true
  npm install -g @openai/codex 2>/dev/null || true
fi
if command -v pip3 >/dev/null 2>&1; then
  pip3 install --user aider-chat 2>/dev/null || true
fi

echo "[*] Done. Run: node --version && claude --version && git --version"