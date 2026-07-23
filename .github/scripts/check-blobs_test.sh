#!/usr/bin/env bash
set -euo pipefail

repo="$(mktemp -d)"
trap 'rm -rf "$repo"' EXIT

mkdir -p "$repo/.github/scripts" "$repo/native/src" "$repo/lib/src/blobs"
cp "$(dirname "$0")/check-blobs.sh" "$repo/.github/scripts/"
printf '%s\n' 'pub fn run() {}' >"$repo/native/src/lib.rs"
printf '%s\n' '[package]' 'name = "fixture"' >"$repo/native/Cargo.toml"
printf '%s\n' '# fixture lockfile' >"$repo/native/Cargo.lock"

"$repo/.github/scripts/check-blobs.sh" write >/dev/null
printf '%s\n' 'fn main() {}' >"$repo/native/build.rs"

if output=$("$repo/.github/scripts/check-blobs.sh" 2>&1); then
  echo "expected build.rs to invalidate the native blob stamp"
  echo "$output"
  exit 1
fi

echo "build.rs invalidates the native blob stamp"
