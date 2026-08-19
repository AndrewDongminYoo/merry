#!/usr/bin/env bash
set -euo pipefail

readonly DART_INSTALL_DIR="${HOME}/dart-sdk"
: "${PUB_CACHE:=${HOME}/.pub-cache}"
readonly TRUNK_INSTALL_DIR="${HOME}/.local/bin"
readonly DART_ARCHIVE_URL="https://storage.googleapis.com/dart-archive"
readonly TRUNK_LAUNCHER_URL="https://trunk.io/releases/trunk"
: "${DEBUG:=0}"

if [[ ${DEBUG} == "1" ]]; then
	set -x
fi

die() {
	echo "ERROR: $*" >&2
	exit 1
}

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "'$1' command is required but not found."
}

download() {
	curl --fail --location --silent --show-error \
		--retry 3 --retry-delay 2 \
		--proto '=https' --tlsv1.2 \
		"$1" --output "$2"
}

verify_sha256() {
	local actual_sha
	actual_sha="$(sha256sum "$1" | awk '{print $1}')"
	[[ ${actual_sha} == "$2" ]] || die "SHA-256 mismatch for $1."
}

cleanup() {
	if [[ -n ${TMP_DIR:-} && -d ${TMP_DIR} ]]; then
		rm -rf -- "${TMP_DIR}"
	fi
}

for required_cmd in awk basename chmod curl dirname git grep mkdir mktemp mv python3 rm sha256sum touch uname unzip; do
	need_cmd "${required_cmd}"
done
[[ $(uname -s) == "Linux" ]] || die "This setup script supports Linux containers only."

case "$(uname -m)" in
x86_64 | amd64) DART_ARCH="x64" ;;
aarch64 | arm64) DART_ARCH="arm64" ;;
*) die "Unsupported Dart host architecture: $(uname -m)" ;;
esac

TMP_DIR="$(mktemp -d)"
readonly TMP_DIR
trap cleanup EXIT

DART_VERSION="$(
	python3 - "${DART_ARCHIVE_URL}" <<'PY'
import json
import sys
import urllib.request

url = f"{sys.argv[1]}/channels/stable/release/latest/VERSION"
with urllib.request.urlopen(url, timeout=30) as response:
    payload = json.load(response)

version = payload.get("version")
if not version:
    sys.exit("Latest stable Dart version was not found.")
print(version)
PY
)"
readonly DART_VERSION

DART_BIN="${DART_INSTALL_DIR}/bin/dart"
INSTALLED_VERSION=""
if [[ -x ${DART_BIN} ]]; then
	INSTALLED_VERSION="$("${DART_BIN}" --version 2>&1 | awk '{print $4}' || true)"
fi

if [[ ${INSTALLED_VERSION} == "${DART_VERSION}" ]]; then
	echo "Dart ${DART_VERSION} is already installed."
else
	ARCHIVE_NAME="dartsdk-linux-${DART_ARCH}-release.zip"
	ARCHIVE_URL="${DART_ARCHIVE_URL}/channels/stable/release/${DART_VERSION}/sdk/${ARCHIVE_NAME}"
	ARCHIVE_PATH="${TMP_DIR}/${ARCHIVE_NAME}"
	echo "Installing latest stable Dart ${DART_VERSION}..."
	download "${ARCHIVE_URL}" "${ARCHIVE_PATH}"
	download "${ARCHIVE_URL}.sha256sum" "${ARCHIVE_PATH}.sha256sum"
	EXPECTED_SHA="$(awk '{print $1}' "${ARCHIVE_PATH}.sha256sum")"
	[[ -n ${EXPECTED_SHA} ]] || die "Dart archive checksum is missing."
	verify_sha256 "${ARCHIVE_PATH}" "${EXPECTED_SHA}"
	unzip -q "${ARCHIVE_PATH}" -d "${TMP_DIR}"
	[[ -x ${TMP_DIR}/dart-sdk/bin/dart ]] || die "Extracted Dart binary is missing."
	mkdir -p "$(dirname "${DART_INSTALL_DIR}")"
	rm -rf -- "${DART_INSTALL_DIR}"
	mv "${TMP_DIR}/dart-sdk" "${DART_INSTALL_DIR}"
fi

DART_BIN="${DART_INSTALL_DIR}/bin/dart"
PROFILE_LINE="export PATH=\"${DART_INSTALL_DIR}/bin:${PUB_CACHE}/bin:${TRUNK_INSTALL_DIR}:\$PATH\""
touch "${HOME}/.bashrc"
grep -Fqx -- "${PROFILE_LINE}" "${HOME}/.bashrc" ||
	printf '\n%s\n' "${PROFILE_LINE}" >>"${HOME}/.bashrc"

export PUB_CACHE
export PATH="${DART_INSTALL_DIR}/bin:${PUB_CACHE}/bin:${TRUNK_INSTALL_DIR}:${PATH}"

"${DART_BIN}" --version
for package_name in melos merry flutterfire_cli; do
	echo "Activating latest compatible ${package_name}..."
	"${DART_BIN}" pub global activate "${package_name}"
done

echo "Installing the latest Trunk launcher..."
download "${TRUNK_LAUNCHER_URL}" "${TMP_DIR}/trunk"
chmod 0755 "${TMP_DIR}/trunk"
mkdir -p "${TRUNK_INSTALL_DIR}"
mv -f "${TMP_DIR}/trunk" "${TRUNK_INSTALL_DIR}/trunk"
"${TRUNK_INSTALL_DIR}/trunk" --version

if git ls-files --error-unmatch pubspec.lock >/dev/null 2>&1; then
	"${DART_BIN}" pub get --enforce-lockfile
else
	"${DART_BIN}" pub get
fi

echo "Cloud development environment setup is complete."
