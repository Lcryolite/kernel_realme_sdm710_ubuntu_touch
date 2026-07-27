#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
defconfig="$repo_root/arch/arm64/configs/sdm670-perf_defconfig"

test "$(grep -Fxc 'CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE=y' "$defconfig")" -eq 1
test "$(grep -Fxc '# CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE is not set' "$defconfig")" -eq 0
test "$(grep -Fxc 'CONFIG_LOCALVERSION="-RMX1901-Halium"' "$defconfig")" -eq 1

if git -C "$repo_root" grep -niE 'resukisu|sukisu' -- ':!tests/test-ubuntu-touch-defconfig.sh'; then
  echo 'forbidden root framework marker in Ubuntu Touch kernel tree' >&2
  exit 1
fi

echo 'Ubuntu Touch RMX1901 kernel config tests passed'
