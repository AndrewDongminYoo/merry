#!/usr/bin/env bash
set -euo pipefail

repo="$(mktemp -d)"
trap 'rm -rf "$repo"' EXIT

mkdir -p "${repo}/.github/scripts" "${repo}/native/src" "${repo}/lib/src/blobs"
cp "$(dirname "$0")/check-blobs.sh" "${repo}/.github/scripts/"
printf '%s\n' 'pub fn run() {}' >"${repo}/native/src/lib.rs"
printf '%s\n' '[package]' 'name = "fixture"' >"${repo}/native/Cargo.toml"
printf '%s\n' '# fixture lockfile' >"${repo}/native/Cargo.lock"
git -C "${repo}" init -q
git -C "${repo}" add native

expect_stale() {
	if output=$("${repo}/.github/scripts/check-blobs.sh" 2>&1); then
		echo "expected $1 to invalidate the native blob stamp"
		echo "${output}"
		exit 1
	fi
}

"${repo}/.github/scripts/check-blobs.sh" write >/dev/null
printf '%s\n' 'fn main() {}' >"${repo}/native/build.rs"
git -C "${repo}" add native/build.rs
expect_stale "build.rs"

"${repo}/.github/scripts/check-blobs.sh" write >/dev/null
mkdir -p "${repo}/.cargo"
printf '%s\n' '[build]' 'rustflags = ["-C", "target-cpu=native"]' >"${repo}/.cargo/config.toml"
git -C "${repo}" add .cargo/config.toml
expect_stale "repository Cargo configuration"

printf 'BEFOREnative/src/data2\0AFTER' >"${repo}/native/src/data1"
git -C "${repo}" add native/src/data1
"${repo}/.github/scripts/check-blobs.sh" write >/dev/null
printf 'BEFORE' >"${repo}/native/src/data1"
printf 'AFTER' >"${repo}/native/src/data2"
git -C "${repo}" add native/src/data1 native/src/data2
expect_stale "a path/content boundary change"

printf 'first' >"${repo}/native/src/first"
printf 'second' >"${repo}/native/src/second"
ln -s first "${repo}/native/src/input"
git -C "${repo}" add native/src
"${repo}/.github/scripts/check-blobs.sh" write >/dev/null
ln -sfn second "${repo}/native/src/input"
git -C "${repo}" add native/src/input
expect_stale "a symlink target change"

mkdir -p "${repo}/native/target"
printf 'before' >"${repo}/native/target/tracked-input"
git -C "${repo}" add -f native/target/tracked-input
"${repo}/.github/scripts/check-blobs.sh" write >/dev/null
printf 'after' >"${repo}/native/target/tracked-input"
git -C "${repo}" add -f native/target/tracked-input
expect_stale "a tracked native/target input"

printf '#!/usr/bin/env bash\n' >"${repo}/native/helper"
git -C "${repo}" add native/helper
"${repo}/.github/scripts/check-blobs.sh" write >/dev/null
chmod +x "${repo}/native/helper"
git -C "${repo}" add native/helper
expect_stale "an executable-bit change"

mkdir -p "${repo}/crates/helper"
printf '%s\n' '[workspace]' 'members = ["native", "crates/helper"]' >"${repo}/Cargo.toml"
printf '%s\n' '[package]' 'name = "helper"' >"${repo}/crates/helper/Cargo.toml"
printf 'before' >"${repo}/crates/helper/input"
git -C "${repo}" add Cargo.toml crates/helper
"${repo}/.github/scripts/check-blobs.sh" write >/dev/null
printf 'after' >"${repo}/crates/helper/input"
git -C "${repo}" add crates/helper/input
expect_stale "an ancestor workspace input"

echo "all Cargo input changes invalidate the native blob stamp"
