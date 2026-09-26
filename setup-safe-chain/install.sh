#!/usr/bin/env bash
# Installs Aikido Safe Chain SAFE_CHAIN_VERSION with the installer attached to
# that release. The attached installer embeds the SHA256 of each binary; the
# one on the main branch does not, and skips the check.
set -euo pipefail

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
gh release download "$SAFE_CHAIN_VERSION" --repo AikidoSec/safe-chain \
  --pattern install-safe-chain.sh --dir "$dir"
sh "$dir/install-safe-chain.sh" --ci
