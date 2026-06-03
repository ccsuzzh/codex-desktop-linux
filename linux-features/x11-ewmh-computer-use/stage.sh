#!/bin/bash
set -Eeuo pipefail

PLUGIN_NAME="codex-computer-use-x11"
DEFAULT_RELEASE_URL="https://github.com/AlekseiSeleznev/codex-computer-use-x11/releases/download/v0.1.3/codex-computer-use-x11-v0.1.3-x86_64-unknown-linux-gnu.tar.gz"
DEFAULT_RELEASE_SHA256="067244a16f9e812eb369af42149658c8cf138b13057445bb9d10318f29b0c26b"
FEATURE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:?INSTALL_DIR is required}"
WORK_DIR="${WORK_DIR:-$(mktemp -d)}"
TARGET_PLUGIN="$INSTALL_DIR/resources/plugins/openai-bundled/plugins/$PLUGIN_NAME"
TARGET_MARKETPLACE="$INSTALL_DIR/resources/plugins/openai-bundled/.agents/plugins/marketplace.json"

find_cargo() {
    if command -v cargo >/dev/null 2>&1; then command -v cargo; return 0; fi
    if [ -x "$HOME/.cargo/bin/cargo" ]; then echo "$HOME/.cargo/bin/cargo"; return 0; fi
    return 1
}

expected_sha_value() {
    local value="${CODEX_X11_COMPUTER_USE_RELEASE_SHA256:-$DEFAULT_RELEASE_SHA256}"
    [ -n "$value" ] || return 1
    if [ -f "$value" ]; then
        awk '{print $1; exit}' "$value"
    else
        printf '%s\n' "$value"
    fi
}

verify_sha256() {
    local file="$1"
    local expected
    expected="$(expected_sha_value)" || {
        echo "CODEX_X11_COMPUTER_USE_RELEASE_SHA256 is required for tarball/download mode" >&2
        return 1
    }
    local actual
    actual="$(sha256sum "$file" | awk '{print $1}')"
    if [ "$actual" != "$expected" ]; then
        echo "sha256 mismatch for $file: expected $expected got $actual" >&2
        return 1
    fi
}

write_plugin_from_binary() {
    local binary="$1"
    local dest="$2"
    [ -x "$binary" ] || { echo "codex-computer-use-x11 binary is not executable: $binary" >&2; return 1; }
    rm -rf "$dest"
    mkdir -p "$dest/.codex-plugin" "$dest/bin" "$dest/assets"
    cp "$binary" "$dest/bin/codex-computer-use-x11"
    chmod 0755 "$dest/bin/codex-computer-use-x11"
    if [ -f "$FEATURE_DIR/assets/app-icon.png" ]; then
        cp "$FEATURE_DIR/assets/app-icon.png" "$dest/assets/app-icon.png"
    else
        : > "$dest/assets/app-icon.png"
    fi
    cat > "$dest/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "codex-computer-use-x11": {
      "command": "./bin/codex-computer-use-x11",
      "args": ["mcp"],
      "cwd": "."
    }
  }
}
JSON
    cat > "$dest/.codex-plugin/plugin.json" <<'JSON'
{
  "name": "codex-computer-use-x11",
  "version": "0.0.0-adapter",
  "description": "Standalone X11/EWMH Computer Use MCP tools for Codex.",
  "author": { "name": "AlekseiSeleznev", "url": "https://github.com/AlekseiSeleznev" },
  "homepage": "https://github.com/AlekseiSeleznev/codex-computer-use-x11",
  "license": "MIT",
  "keywords": ["computer-use", "linux", "x11", "ewmh", "mcp"],
  "mcpServers": "./.mcp.json",
  "interface": {
    "displayName": "X11 Computer Use",
    "shortDescription": "Standalone x11_* tools for Linux X11/EWMH",
    "longDescription": "Provides standalone x11_* readiness diagnostics, window listing/focus, keyboard input, pointer actions, accessibility tree, app state, and target-window context tools without replacing the bundled Computer Use plugin.",
    "developerName": "AlekseiSeleznev",
    "category": "Productivity",
    "websiteURL": "https://github.com/AlekseiSeleznev/codex-computer-use-x11",
    "logo": "./assets/app-icon.png",
    "defaultPrompt": ["Check whether standalone X11 Computer Use is ready with x11_doctor"],
    "brandColor": "#1E293B",
    "screenshots": []
  }
}
JSON
}

stage_from_tarball() {
    local tarball="$1"
    verify_sha256 "$tarball"
    local extract_dir="$WORK_DIR/x11-computer-use-extract"
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"
    tar -xzf "$tarball" -C "$extract_dir"
    [ -f "$extract_dir/$PLUGIN_NAME/.mcp.json" ] || { echo "tarball does not contain $PLUGIN_NAME/.mcp.json" >&2; return 1; }
    rm -rf "$TARGET_PLUGIN"
    mkdir -p "$(dirname "$TARGET_PLUGIN")"
    cp -R "$extract_dir/$PLUGIN_NAME" "$TARGET_PLUGIN"
    chmod 0755 "$TARGET_PLUGIN/bin/codex-computer-use-x11"
}

stage_from_source() {
    local source="$1"
    [ -f "$source/Cargo.toml" ] || { echo "CODEX_X11_COMPUTER_USE_SOURCE lacks Cargo.toml: $source" >&2; return 1; }
    local cargo_cmd
    cargo_cmd="$(find_cargo)" || { echo "cargo not found for CODEX_X11_COMPUTER_USE_SOURCE build" >&2; return 1; }
    (cd "$source" && "$cargo_cmd" build --release >&2)
    write_plugin_from_binary "$source/target/release/codex-computer-use-x11" "$TARGET_PLUGIN"
}

stage_from_download() {
    local url="$1"
    local tarball="$WORK_DIR/codex-computer-use-x11-download.tar.gz"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$tarball"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$tarball" "$url"
    else
        echo "curl or wget is required for CODEX_X11_COMPUTER_USE_DOWNLOAD_URL" >&2
        return 1
    fi
    stage_from_tarball "$tarball"
}

write_marketplace_entry() {
    local marketplace="$1"
    node - "$marketplace" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");
const marketplacePath = process.argv[2];
let marketplace = { plugins: [] };
try { marketplace = JSON.parse(fs.readFileSync(marketplacePath, "utf8")); } catch (_error) { marketplace = { plugins: [] }; }
if (!Array.isArray(marketplace.plugins)) marketplace.plugins = [];
marketplace.plugins = marketplace.plugins.filter((plugin) => plugin?.name !== "codex-computer-use-x11");
marketplace.plugins.push({
  name: "codex-computer-use-x11",
  source: { source: "local", path: "./plugins/codex-computer-use-x11" },
  policy: { installation: "AVAILABLE", authentication: "ON_INSTALL" },
  category: "Productivity",
});
fs.mkdirSync(path.dirname(marketplacePath), { recursive: true });
fs.writeFileSync(marketplacePath, `${JSON.stringify(marketplace, null, 2)}\n`);
NODE
}

mkdir -p "$WORK_DIR"
if [ -n "${CODEX_X11_COMPUTER_USE_RELEASE_TARBALL:-}" ]; then
    stage_from_tarball "$CODEX_X11_COMPUTER_USE_RELEASE_TARBALL"
elif [ -n "${CODEX_X11_COMPUTER_USE_BINARY:-}" ]; then
    write_plugin_from_binary "$CODEX_X11_COMPUTER_USE_BINARY" "$TARGET_PLUGIN"
elif [ -n "${CODEX_X11_COMPUTER_USE_SOURCE:-}" ]; then
    stage_from_source "$CODEX_X11_COMPUTER_USE_SOURCE"
elif [ -n "${CODEX_X11_COMPUTER_USE_DOWNLOAD_URL:-}" ]; then
    stage_from_download "$CODEX_X11_COMPUTER_USE_DOWNLOAD_URL"
else
    stage_from_download "$DEFAULT_RELEASE_URL"
fi

write_marketplace_entry "$TARGET_MARKETPLACE"
echo "X11/EWMH Computer Use plugin staged" >&2
