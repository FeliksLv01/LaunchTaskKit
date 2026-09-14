#!/bin/sh

set -e

cd "$(dirname "$0")"

macro_name="LaunchTaskKitMacros"
swift build -c release --target "${macro_name}Tests" -Xswiftc -Osize
bin_path_root=$(swift build -c release --target "${macro_name}Tests" --show-bin-path)
binary=$(find "${bin_path_root}" -name "${macro_name}-tool" -type f -not -path "*.dSYM*" | head -n 1)

if [ -z "${binary}" ]; then
    binary=$(find "${bin_path_root}" -name "${macro_name}" -type f -not -path "*.dSYM*" | head -n 1)
fi

if [ -z "${binary}" ]; then
    echo "Error: ${macro_name} executable not found in ${bin_path_root}"
    exit 1
fi

mkdir -p Prebuilt
cp "${binary}" "Prebuilt/${macro_name}"
chmod u+x "Prebuilt/${macro_name}"
strip -x "Prebuilt/${macro_name}"

echo "Built Prebuilt/${macro_name}"
