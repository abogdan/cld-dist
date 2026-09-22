#!/bin/sh
set -e

REPO="abogdan/cld-dist"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "unsupported architecture: $ARCH" >&2; exit 1 ;;
esac
case "$OS" in
  linux|darwin) ;;
  *) echo "unsupported OS: $OS (on Windows use install.ps1)" >&2; exit 1 ;;
esac
ASSET="cld-${OS}-${ARCH}"

# github.com's redirect instead of api.github.com, which rate-limits anonymous callers.
LATEST=$(curl -fsSI "https://github.com/${REPO}/releases/latest" \
  | tr -d '\r' \
  | awk 'tolower($1)=="location:"{print $2}' \
  | sed 's#.*/tag/##' \
  | head -1)
if [ -z "$LATEST" ]; then
  echo "could not determine latest release" >&2
  exit 1
fi

base="https://github.com/${REPO}/releases/download/${LATEST}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "downloading cld ${LATEST} (${OS}/${ARCH})…"
curl -fsSL "${base}/${ASSET}" -o "${tmp}/cld"
curl -fsSL "${base}/SHA256SUMS" -o "${tmp}/SHA256SUMS"
want=$(grep " ${ASSET}\$" "${tmp}/SHA256SUMS" | awk '{print $1}')
if command -v sha256sum >/dev/null 2>&1; then got=$(sha256sum "${tmp}/cld" | awk '{print $1}')
else got=$(shasum -a 256 "${tmp}/cld" | awk '{print $1}'); fi
if [ -z "$want" ] || [ "$want" != "$got" ]; then
  echo "checksum mismatch for ${ASSET}: expected '$want', got $got" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
chmod +x "${tmp}/cld"
mv "${tmp}/cld" "${INSTALL_DIR}/cld"
echo "installed cld to ${INSTALL_DIR}/cld"
echo
# MemPalace is cld's default memory (per account, private); CLD_NO_MEMPALACE=1 skips it.
if [ -z "${CLD_NO_MEMPALACE:-}" ] && ! command -v mempalace-mcp >/dev/null 2>&1; then
  echo "installing MemPalace (cld's default memory)…"
  # uv never edits startup files here; cld's shell integration handles PATH-free lookups.
  export UV_NO_MODIFY_PATH=1
  if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    PATH="$HOME/.local/bin:$PATH"
  fi
  if ! uv tool install mempalace; then
    echo "MemPalace could not be installed; cld retries from the dashboard (Memory)" >&2
  elif ! command -v mempalace-mcp >/dev/null 2>&1; then
    echo "add $(uv tool dir --bin 2>/dev/null || echo ~/.local/bin) to your PATH for MemPalace" >&2
  fi
fi
echo
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
  echo "add ${INSTALL_DIR} to your PATH"
fi
echo "then run: cld   (it sets up the shell integration for you: Settings → Shell integration)"
