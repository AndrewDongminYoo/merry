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

# A crate that exists only in the working tree is not in the tracked manifest
# list, so its directory has to be discovered from untracked manifests too —
# otherwise nothing about it is reported until staging invalidates the stamp.
# Runs before the workspace fixture below, which puts a Cargo.toml at the root
# and from then on widens the pathspec to everything, hiding this distinction.
"${repo}/.github/scripts/check-blobs.sh" write >/dev/null
mkdir -p "${repo}/crates/fresh/src"
printf '%s\n' '[package]' 'name = "fresh"' >"${repo}/crates/fresh/Cargo.toml"
printf '%s\n' 'fn main() {}' >"${repo}/crates/fresh/src/main.rs"
if ! output=$("${repo}/.github/scripts/check-blobs.sh" 2>&1); then
	echo "expected an untracked crate to still verify against the index"
	echo "${output}"
	exit 1
fi
case "${output}" in
*"crates/fresh/Cargo.toml"*"crates/fresh/src/main.rs"*) ;;
*)
	echo "expected an untracked crate to be reported"
	echo "${output}"
	exit 1
	;;
esac
rm -r "${repo}/crates/fresh"

mkdir -p "${repo}/crates/helper"
printf '%s\n' '[workspace]' 'members = ["native", "crates/helper"]' >"${repo}/Cargo.toml"
printf '%s\n' '[package]' 'name = "helper"' >"${repo}/crates/helper/Cargo.toml"
printf 'before' >"${repo}/crates/helper/input"
git -C "${repo}" add Cargo.toml crates/helper
"${repo}/.github/scripts/check-blobs.sh" write >/dev/null
printf 'after' >"${repo}/crates/helper/input"
git -C "${repo}" add crates/helper/input
expect_stale "an ancestor workspace input"

# The stamp is computed from the index, so an unstaged edit cannot change it —
# the check still passes, and has to say that its answer does not cover it.
"${repo}/.github/scripts/check-blobs.sh" write >/dev/null
printf '%s\n' '// unstaged edit' >>"${repo}/native/src/lib.rs"
if ! output=$("${repo}/.github/scripts/check-blobs.sh" 2>&1); then
	echo "expected an unstaged edit to still verify against the index"
	echo "${output}"
	exit 1
fi
case "${output}" in
*"not covered by this check"*"native/src/lib.rs"*) ;;
*)
	echo "expected the unstaged edit to be reported"
	echo "${output}"
	exit 1
	;;
esac
git -C "${repo}" checkout -- native/src/lib.rs

# A file that is new rather than modified is absent from `git diff` entirely,
# so it needs the untracked listing to be reported at all.
printf '%s\n' 'fn helper() {}' >"${repo}/native/src/added.rs"
if ! output=$("${repo}/.github/scripts/check-blobs.sh" 2>&1); then
	echo "expected an untracked file to still verify against the index"
	echo "${output}"
	exit 1
fi
case "${output}" in
*"not covered by this check"*"native/src/added.rs"*) ;;
*)
	echo "expected the untracked file to be reported"
	echo "${output}"
	exit 1
	;;
esac
rm "${repo}/native/src/added.rs"

# Build output is ignored, so it must not be reported as pending work. Matched
# by path rather than by the warning line: the workspace fixture above put a
# Cargo.toml at the root, which widens the pathspec to the whole repo, so other
# untracked fixture files legitimately appear in that list.
mkdir -p "${repo}/native/target"
printf '%s\n' 'target' >"${repo}/native/.gitignore"
git -C "${repo}" add native/.gitignore
"${repo}/.github/scripts/check-blobs.sh" write >/dev/null
printf '%s\n' 'binary' >"${repo}/native/target/artifact"
output=$("${repo}/.github/scripts/check-blobs.sh" 2>&1)
case "${output}" in
*"native/target/artifact"*)
	echo "expected ignored build output to stay quiet"
	echo "${output}"
	exit 1
	;;
*) ;;
esac

echo "all Cargo input changes invalidate the native blob stamp"
echo "unstaged and untracked changes are reported rather than silently excluded"
