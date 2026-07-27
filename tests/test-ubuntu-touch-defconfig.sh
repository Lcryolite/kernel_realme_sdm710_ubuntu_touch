#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
defconfig="$repo_root/arch/arm64/configs/sdm670-perf_defconfig"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
fake_bin="$tmp_dir/bin"
build_output="$tmp_dir/out"
make_log="$tmp_dir/make.log"
mkdir -p "$fake_bin"

cat >"$fake_bin/fake-tool" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$(basename "$0"):${1:-}" in
	clang:-dumpversion)
		echo '22.0.0'
		;;
	clang:--version)
		echo 'clang version 22.0.0 (test double)'
		;;
esac
EOF
chmod +x "$fake_bin/fake-tool"

for tool in \
	clang ld.lld llvm-ar llvm-nm llvm-objcopy llvm-objdump \
	llvm-readelf llvm-size llvm-strip aarch64-linux-gnu-elfedit \
	arm-linux-gnueabi-ld; do
	ln -s fake-tool "$fake_bin/$tool"
done

cat >"$fake_bin/make" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$MAKE_LOG"
output=''
for arg in "$@"; do
	case "$arg" in
		O=*) output="${arg#O=}" ;;
	esac
done

case " $* " in
	*' sdm670-perf_defconfig '*)
		mkdir -p "$output"
		cp "$FAKE_DEFCONFIG" "$output/.config"
		;;
	*' Image.gz-dtb '*)
		mkdir -p "$output/arch/arm64/boot"
		printf 'test Image.gz-dtb\n' >"$output/arch/arm64/boot/Image.gz-dtb"
		printf 'clang version 22.0.0\n' >"$output/vmlinux"
		;;
	*' kernelrelease '*)
		echo '4.14.0-RMX1901-Halium-test'
		;;
esac
EOF
chmod +x "$fake_bin/make"

test "$(grep -Fxc 'CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE=y' "$defconfig")" -eq 1
test "$(grep -Fxc '# CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE is not set' "$defconfig")" -eq 0
test "$(grep -Fxc 'CONFIG_LOCALVERSION="-RMX1901-Halium"' "$defconfig")" -eq 1
test "$(grep -Fxc 'CONFIG_USB_CONFIGFS_RNDIS=y' "$defconfig")" -eq 1

PATH="$fake_bin:$PATH" \
	OUT_DIR="$build_output" \
	MAKE_LOG="$make_log" \
	FAKE_DEFCONFIG="$defconfig" \
	"$repo_root/build-clang22.sh"

test -s "$build_output/arch/arm64/boot/Image.gz-dtb"
grep -Fq ' Image.gz-dtb' "$make_log"
if grep -Eq '(^| )Image\.gz($| )' "$make_log"; then
	echo 'build helper requested plain Image.gz instead of Image.gz-dtb' >&2
	exit 1
fi

if git -C "$repo_root" grep -niE 'resukisu|sukisu' -- ':!tests/test-ubuntu-touch-defconfig.sh'; then
  echo 'forbidden root framework marker in Ubuntu Touch kernel tree' >&2
  exit 1
fi

echo 'Ubuntu Touch RMX1901 kernel config tests passed'
