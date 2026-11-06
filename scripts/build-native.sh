#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
target_dir=${CARGO_TARGET_DIR:-"$root/native/pace-core/target"}
case "$target_dir" in
    /*) ;;
    *) target_dir="$root/$target_dir" ;;
esac
cargo build --release --locked --manifest-path "$root/native/pace-core/Cargo.toml" --target-dir "$target_dir"
archive="$target_dir/release/libpace_core.a"
destination="$root/macos/Native/lib"
mkdir -p "$destination"
if [ -f "$destination/libpace_core.a" ] && cmp -s "$archive" "$destination/libpace_core.a"; then
    exit 0
fi
temporary=$(mktemp "$destination/.libpace_core.XXXXXX")
trap 'rm -f "$temporary"' EXIT HUP INT TERM
cp "$archive" "$temporary"
mv "$temporary" "$destination/libpace_core.a"
