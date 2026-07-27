#!/usr/bin/env bash

# Verify the exact DTB suffix expected by the RMX1901 Halium boot contract.
set -euo pipefail

if [[ $# -ne 2 ]]; then
	echo "usage: $0 IMAGE_GZ_DTB DTS_OUTPUT_DIR" >&2
	exit 2
fi

image="$1"
dts_output="$2"
test -s "$image"
test -d "$dts_output"

expected_dtbs=(
	18621/sdm710.dtb
	19651/sdm710.dtb
	18097/sdm710.dtb
	18097/sdm670.dtb
	19601/sdm710.dtb
	qcom/sdm710.dtb
)

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
expected_chain="$tmp_dir/rmx1901-dtb-chain"
: >"$expected_chain"

for relative_dtb in "${expected_dtbs[@]}"; do
	dtb="${dts_output}/${relative_dtb}"
	test -s "$dtb" || { echo "Missing expected DTB: ${relative_dtb}" >&2; exit 1; }
	magic="$(od -An -N4 -tx1 "$dtb" | tr -d '[:space:]')"
	[[ "$magic" == "d00dfeed" ]] || { echo "Invalid FDT magic in ${relative_dtb}: ${magic}" >&2; exit 1; }
	totalsize_hex="$(od -An -j4 -N4 -tx1 "$dtb" | tr -d '[:space:]')"
	totalsize=$((16#${totalsize_hex}))
	actual_size="$(stat -c %s "$dtb")"
	[[ "$totalsize" -eq "$actual_size" ]] || {
		echo "FDT totalsize mismatch in ${relative_dtb}: ${totalsize} != ${actual_size}" >&2
		exit 1
	}
	cat "$dtb" >>"$expected_chain"
done

image_size="$(stat -c %s "$image")"
chain_size="$(stat -c %s "$expected_chain")"
[[ "$image_size" -gt "$chain_size" ]] || { echo 'Image.gz-dtb has no kernel payload before the DTB chain' >&2; exit 1; }

# The complete suffix must be precisely the six declared FDT blobs.
tail -c "$chain_size" "$image" | cmp -s - "$expected_chain" || {
	echo 'Image.gz-dtb suffix does not match the required RMX1901 DTB chain' >&2
	exit 1
}

echo 'rmx1901_dtb_chain=pass'
