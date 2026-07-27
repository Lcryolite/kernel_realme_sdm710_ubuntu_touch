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
	depmod:-b)
		printf 'test.ko:\n' >"$2/lib/modules/$3/modules.dep"
		;;
esac
EOF
chmod +x "$fake_bin/fake-tool"

for tool in \
	clang ld.lld llvm-ar llvm-nm llvm-objcopy llvm-objdump \
	llvm-readelf llvm-size llvm-strip aarch64-linux-gnu-elfedit \
	arm-linux-gnueabi-ld depmod; do
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
		mkdir -p "$output/arch/arm64/boot/dts/18621" \
			"$output/arch/arm64/boot/dts/19651" \
			"$output/arch/arm64/boot/dts/18097" \
			"$output/arch/arm64/boot/dts/19601" \
			"$output/arch/arm64/boot/dts/qcom"
		printf 'gzip-kernel-payload' >"$output/arch/arm64/boot/Image.gz-dtb"
		for dtb in \
			18621/sdm710.dtb 19651/sdm710.dtb 18097/sdm710.dtb \
			18097/sdm670.dtb 19601/sdm710.dtb qcom/sdm710.dtb; do
			printf '\320\015\376\355\000\000\000\010' >"$output/arch/arm64/boot/dts/$dtb"
			cat "$output/arch/arm64/boot/dts/$dtb" >>"$output/arch/arm64/boot/Image.gz-dtb"
		done
		printf 'clang version 22.0.0\n' >"$output/vmlinux"
		;;
	*' modules_install '*)
		staging=''
		for arg in "$@"; do
			case "$arg" in INSTALL_MOD_PATH=*) staging="${arg#INSTALL_MOD_PATH=}" ;; esac
		done
		release='4.9.337+67-RMX1901-Halium-test'
		mkdir -p "$staging/lib/modules/$release"
		for module in br_netfilter rdbg mpq-adapter mpq-dmx-hw-plugin lcd llcc_perfmon; do
			: >"$staging/lib/modules/$release/$module.ko"
		done
		: >"$staging/lib/modules/$release/modules.dep"
		;;
	*' kernelrelease '*)
		echo '4.9.337+67-RMX1901-Halium-test'
		;;
esac
EOF
chmod +x "$fake_bin/make"

test "$(grep -Fxc 'CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE=y' "$defconfig")" -eq 1
test "$(grep -Fxc '# CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE is not set' "$defconfig")" -eq 0
test "$(grep -Fxc 'CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE_NAMES="18621/sdm710 19651/sdm710 18097/sdm710 18097/sdm670 19601/sdm710 qcom/sdm710"' "$defconfig")" -eq 1
test "$(grep -Fxc 'CONFIG_LOCALVERSION="-RMX1901-Halium"' "$defconfig")" -eq 1
test "$(grep -Fxc 'CONFIG_BRIDGE_NETFILTER=m' "$defconfig")" -eq 1
test "$(grep -Fxc 'CONFIG_USB_CONFIGFS_RNDIS=y' "$defconfig")" -eq 1
test "$(grep -Fxc 'CONFIG_SERIAL_MSM_GENI_CONSOLE=y' "$defconfig")" -eq 1

# Ubuntu 24.04 systemd 255 baseline and Halium/LXC container primitives.
for required_config in \
	CONFIG_FHANDLE=y \
	CONFIG_SYSVIPC=y \
	CONFIG_POSIX_MQUEUE=y \
	CONFIG_IPC_NS=y \
	CONFIG_PID_NS=y \
	CONFIG_CGROUP_PIDS=y \
	CONFIG_CGROUP_DEVICE=y \
	CONFIG_DEVTMPFS_MOUNT=y \
	CONFIG_AUTOFS4_FS=y \
	CONFIG_FANOTIFY=y; do
	test "$(grep -Fxc "$required_config" "$defconfig")" -eq 1 || {
		echo "missing Ubuntu Touch kernel capability: $required_config" >&2
		exit 1
	}
done

PATH="$fake_bin:$PATH" \
	OUT_DIR="$build_output" \
	MAKE_LOG="$make_log" \
	FAKE_DEFCONFIG="$defconfig" \
	"$repo_root/build-clang22.sh"

test -s "$build_output/arch/arm64/boot/Image.gz-dtb"
grep -Fq ' Image.gz-dtb' "$make_log"
grep -Fq ' Image.gz-dtb modules' "$make_log"
grep -Fq ' modules_install' "$make_log"
if grep -Eq '(^| )Image\.gz($| )' "$make_log"; then
	echo 'build helper requested plain Image.gz instead of Image.gz-dtb' >&2
	exit 1
fi

if git -C "$repo_root" grep -niE 'resukisu|sukisu|kernelsu|magisk' -- ':!tests/test-ubuntu-touch-defconfig.sh'; then
  echo 'forbidden root framework marker in Ubuntu Touch kernel tree' >&2
  exit 1
fi

echo 'Ubuntu Touch RMX1901 kernel config tests passed'
