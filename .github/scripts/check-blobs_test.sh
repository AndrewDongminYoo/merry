#!/usr/bin/env bash
set -euo pipefail

repo="$(mktemp -d)"
trap 'rm -rf "$repo"' EXIT

mkdir -p "$repo/.github/scripts" "$repo/native/src" "$repo/lib/src/blobs"
cp "$(dirname "$0")/check-blobs.sh" "$repo/.github/scripts/"
printf '%s\n' 'pub fn run() {}' >"$repo/native/src/lib.rs"
printf '%s\n' '[package]' 'name = "fixture"' >"$repo/native/Cargo.toml"
printf '%s\n' '# fixture lockfile' >"$repo/native/Cargo.lock"

expect_stale() {
  if output=$("$repo/.github/scripts/check-blobs.sh" 2>&1); then
    echo "expected $1 to invalidate the native blob stamp"
    echo "$output"
    exit 1
  fi
}

"$repo/.github/scripts/check-blobs.sh" write >/dev/null
printf '%s\n' 'fn main() {}' >"$repo/native/build.rs"
expect_stale "build.rs"

"$repo/.github/scripts/check-blobs.sh" write >/dev/null
mkdir -p "$repo/.cargo"
printf '%s\n' '[build]' 'rustflags = ["-C", "target-cpu=native"]' >"$repo/.cargo/config.toml"
expect_stale "repository Cargo configuration"

printf 'BEFOREnative/src/data2\0AFTER' >"$repo/native/src/data1"
"$repo/.github/scripts/check-blobs.sh" write >/dev/null
printf 'BEFORE' >"$repo/native/src/data1"
printf 'AFTER' >"$repo/native/src/data2"
expect_stale "a path/content boundary change"

echo "all Cargo input changes invalidate the native blob stamp"
