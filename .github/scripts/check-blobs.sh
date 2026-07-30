#!/usr/bin/env bash
# Guards against publishing blobs that were not rebuilt for the current native/
# sources. The FFI loader opens the checked-in lib/src/blobs/* files and nothing
# in the release path compiles native/, so a native change that lands without a
# blob rebuild silently ships the old machine code.
#
#   check-blobs.sh          verify the recorded hash matches native/ (default)
#   check-blobs.sh write    record the current hash (used by the blob workflow)
set -euo pipefail

cd "$(dirname "$0")/../.."

STAMP="lib/src/blobs/native.sha256"

# Git stage entries bind tracked paths, contents, symlink targets, and file modes.
# Cargo package trees and repository-level configuration are included, while
# checked-in output blobs are excluded to avoid hashing the stamp itself.
hash_sources() {
	local trees=(native .cargo/config .cargo/config.toml)
	while IFS= read -r -d '' manifest; do
		trees+=("$(dirname "${manifest}")")
	done < <(git ls-files -z -- Cargo.toml ':(glob)**/Cargo.toml')

	git ls-files --stage -z -- "${trees[@]}" ':(exclude,glob)lib/src/blobs/**' |
		sort -z -u
}

sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum | cut -d ' ' -f 1
	else
		shasum -a 256 | cut -d ' ' -f 1
	fi
}

current="$(hash_sources | sha256)"

if [[ ${1:-verify} == "write" ]]; then
	printf '%s\n' "${current}" >"${STAMP}"
	echo "recorded ${STAMP} = ${current}"
	exit 0
fi

if [[ ! -f ${STAMP} ]]; then
	echo "::error::${STAMP} is missing — run the 'Compile blobs' workflow to create it."
	exit 1
fi

recorded="$(cat "${STAMP}")"

if [[ ${current} != "${recorded}" ]]; then
	echo "::error::The precompiled blobs are stale — they were not rebuilt for the current native/ sources."
	echo "  native/ sources hash to: ${current}"
	echo "  lib/src/blobs recorded : ${recorded}"
	echo ""
	echo "The FFI loader runs the checked-in blobs, so this would ship the old native code."
	echo "Run the 'Compile blobs' workflow (build.yml) against this branch, then merge the"
	echo "blob PR it opens into it."
	exit 1
fi

echo "blobs match native/ sources (${current})"
