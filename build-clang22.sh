#!/usr/bin/env bash

set -euo pipefail

kernel_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
build_output="${OUT_DIR:-out-clang22}"
if [[ "${build_output}" != /* ]]; then
	build_output="${kernel_root}/${build_output}"
fi
kernel_defconfig="${KERNEL_DEFCONFIG:-sdm670-perf_defconfig}"
modules_staging="${MODULES_STAGING_DIR:-${build_output}/modules-staging}"
cross_compile="${CROSS_COMPILE:-aarch64-linux-gnu-}"
cross_compile_arm32="${CROSS_COMPILE_ARM32:-arm-linux-gnueabi-}"

if ! command -v "${cross_compile_arm32}ld" >/dev/null 2>&1 && \
   command -v arm-none-eabi-ld >/dev/null 2>&1; then
	cross_compile_arm32="arm-none-eabi-"
fi

required_tools=(
	clang ld.lld llvm-ar llvm-nm llvm-objcopy llvm-objdump
	llvm-readelf llvm-size llvm-strip
	"${cross_compile}elfedit" "${cross_compile_arm32}ld" depmod
)

for required_tool in "${required_tools[@]}"; do
	if ! command -v "${required_tool}" >/dev/null 2>&1; then
		echo "Missing required tool: ${required_tool}" >&2
		exit 1
	fi
done

clang_version="$(clang -dumpversion)"
case "${clang_version}" in
	22.*) ;;
	*)
		echo "Clang 22 is required, found ${clang_version}" >&2
		exit 1
		;;
esac

compiler_command="clang"
if command -v ccache >/dev/null 2>&1; then
	compiler_command="ccache clang"
fi

make_args=(
	"O=${build_output}"
	ARCH=arm64
	LLVM=1
	LLVM_IAS=1
	"CC=${compiler_command}"
	"CROSS_COMPILE=${cross_compile}"
	"CROSS_COMPILE_ARM32=${cross_compile_arm32}"
)

echo "Building RMX1901 Halium kernel"
echo "Compiler: $(clang --version | head -n 1)"
echo "Output: ${build_output}"

make -C "${kernel_root}" "${make_args[@]}" "${kernel_defconfig}"

grep -q '^CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE=y$' \
	"${build_output}/.config"

required_module_configs=(
	CONFIG_BRIDGE_NETFILTER
	CONFIG_MSM_RDBG
	CONFIG_DVB_MPQ
	CONFIG_DVB_MPQ_DEMUX
	CONFIG_LCD_CLASS_DEVICE
	CONFIG_QCOM_LLCC_PERFMON
)
for config in "${required_module_configs[@]}"; do
	grep -qx "${config}=m" "${build_output}/.config" || {
		echo "Required RMX1901 module setting missing: ${config}=m" >&2
		exit 1
	}
done

make -C "${kernel_root}" -j"$(nproc)" "${make_args[@]}" Image.gz-dtb modules

kernel_image="${build_output}/arch/arm64/boot/Image.gz-dtb"
test -s "${kernel_image}"
grep -aFq "clang version ${clang_version}" "${build_output}/vmlinux"
kernel_release="$(make -s -C "${kernel_root}" "${make_args[@]}" kernelrelease)"

rm -rf "${modules_staging}"
make -C "${kernel_root}" "${make_args[@]}" \
	INSTALL_MOD_PATH="${modules_staging}" modules_install
depmod -b "${modules_staging}" "${kernel_release}"

required_modules=(
	br_netfilter.ko
	rdbg.ko
	mpq-adapter.ko
	mpq-dmx-hw-plugin.ko
	lcd.ko
	llcc_perfmon.ko
)
for module in "${required_modules[@]}"; do
	find "${modules_staging}/lib/modules/${kernel_release}" -type f -name "${module}" -print -quit | grep -q . || {
		echo "Required RMX1901 module was not installed: ${module}" >&2
		exit 1
	}
done
test -s "${modules_staging}/lib/modules/${kernel_release}/modules.dep"

"${kernel_root}/scripts/verify-rmx1901-dtb-chain.sh" \
	"${build_output}/arch/arm64/boot/Image.gz-dtb" \
	"${build_output}/arch/arm64/boot/dts"

echo "Built ${kernel_image}"
echo "Kernel release: ${kernel_release}"
echo "Installed modules: ${modules_staging}/lib/modules/${kernel_release}"
