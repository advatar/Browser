#!/bin/bash
set -euo pipefail

# Build and export the macOS DMG produced by Tauri bundler.
# Output: dist/decentralized-browser-v<version>-<arch>.dmg
#
# Signing inputs:
# - MACOS_SIGNING_IDENTITY or APPLE_SIGNING_IDENTITY selects the codesigning identity.
# - STRICT_SIGNING=1 requires a non-ad-hoc app signature.
# - SIGN_DMG=1 signs the exported DMG.
#
# Production checks:
# - Set PROD_RELEASE=1 to require signature + notarization validation.
# - Or set STRICT_SIGNING=1 / STRICT_NOTARIZATION=1 individually.

fail() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "$1 is required"
  fi
}

find_identity() {
  local pattern="$1"
  security find-identity -v -p codesigning | awk -v pattern="$pattern" '
    index($0, pattern) {
      if (match($0, /"[^"]+"/)) {
        print substr($0, RSTART + 1, RLENGTH - 2)
        exit
      }
    }
  '
}

identity_record() {
  local identity="$1"
  security find-identity -v -p codesigning | awk -v identity="$identity" '
    index($0, identity) {
      print
      exit
    }
  '
}

has_notary_credentials() {
  [[ -n "${NOTARYTOOL_PROFILE:-${APPLE_NOTARY_PROFILE:-}}" ]] && return 0
  [[ -n "${APPLE_ID:-}" && -n "${APPLE_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]] && return 0
  [[ -n "${APPLE_API_KEY_PATH:-${APPLE_API_KEY:-}}" && -n "${APPLE_API_KEY_ID:-${APPLE_KEY_ID:-}}" ]] && return 0
  return 1
}

notary_auth_args() {
  local profile="${NOTARYTOOL_PROFILE:-${APPLE_NOTARY_PROFILE:-}}"
  local api_key="${APPLE_API_KEY_PATH:-${APPLE_API_KEY:-}}"
  local api_key_id="${APPLE_API_KEY_ID:-${APPLE_KEY_ID:-}}"
  local api_issuer="${APPLE_API_ISSUER:-${APPLE_ISSUER_ID:-}}"

  if [[ -n "${profile}" ]]; then
    printf '%s\0%s\0' "--keychain-profile" "${profile}"
  elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
    printf '%s\0%s\0%s\0%s\0%s\0%s\0' "--apple-id" "${APPLE_ID}" "--password" "${APPLE_PASSWORD}" "--team-id" "${APPLE_TEAM_ID}"
  elif [[ -n "${api_key}" && -n "${api_key_id}" ]]; then
    printf '%s\0%s\0%s\0%s\0' "--key" "${api_key}" "--key-id" "${api_key_id}"
    if [[ -n "${api_issuer}" ]]; then
      printf '%s\0%s\0' "--issuer" "${api_issuer}"
    fi
  fi
}

if [[ "${OSTYPE:-}" != darwin* ]]; then
  fail "macOS DMG packaging must run on macOS (OSTYPE=${OSTYPE:-unknown})"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="$(node -e "const fs=require('fs');const p='crates/gui/tauri.conf.json';const j=JSON.parse(fs.readFileSync(p,'utf8'));process.stdout.write(j.version);")"
mkdir -p dist

STRICT_SIGNING="${STRICT_SIGNING:-0}"
STRICT_NOTARIZATION="${STRICT_NOTARIZATION:-0}"
SIGN_DMG="${SIGN_DMG:-auto}"
SIGNING_IDENTITY="${MACOS_SIGNING_IDENTITY:-${APPLE_SIGNING_IDENTITY:-}}"
if [[ "${PROD_RELEASE:-0}" == "1" ]]; then
  STRICT_SIGNING=1
  STRICT_NOTARIZATION=1
  SIGN_DMG=1
fi

if [[ "${STRICT_SIGNING}" == "1" && -z "${SIGNING_IDENTITY}" ]]; then
  SIGNING_IDENTITY="$(find_identity "Developer ID Application:")"
  if [[ -z "${SIGNING_IDENTITY}" && "${PROD_RELEASE:-0}" != "1" ]]; then
    SIGNING_IDENTITY="$(find_identity "Apple Development:")"
  fi
fi

if [[ "${SIGN_DMG}" == "auto" ]]; then
  if [[ -n "${SIGNING_IDENTITY}" ]]; then
    SIGN_DMG=1
  else
    SIGN_DMG=0
  fi
fi

if [[ "${SIGN_DMG}" == "1" && -z "${SIGNING_IDENTITY}" ]]; then
  SIGNING_IDENTITY="$(find_identity "Developer ID Application:")"
  if [[ -z "${SIGNING_IDENTITY}" && "${PROD_RELEASE:-0}" != "1" ]]; then
    SIGNING_IDENTITY="$(find_identity "Apple Development:")"
  fi
fi

if [[ "${PROD_RELEASE:-0}" == "1" && -z "${SIGNING_IDENTITY}" ]]; then
  fail "PROD_RELEASE=1 requires MACOS_SIGNING_IDENTITY/APPLE_SIGNING_IDENTITY or an installed Developer ID Application identity"
fi

IDENTITY_RECORD=""
if [[ -n "${SIGNING_IDENTITY}" ]]; then
  require_command security
  require_command codesign
  IDENTITY_RECORD="$(identity_record "${SIGNING_IDENTITY}")"
  if [[ -z "${IDENTITY_RECORD}" ]]; then
    fail "codesigning identity not found: ${SIGNING_IDENTITY}"
  fi
  echo "Using signing identity: ${SIGNING_IDENTITY}"

  if [[ "${PROD_RELEASE:-0}" == "1" && "${IDENTITY_RECORD}" != *"Developer ID Application:"* ]]; then
    fail "PROD_RELEASE=1 requires a Developer ID Application identity, but found: ${SIGNING_IDENTITY}"
  fi
fi

if [[ "${STRICT_SIGNING}" == "1" && -z "${SIGNING_IDENTITY}" ]]; then
  fail "STRICT_SIGNING=1 requires MACOS_SIGNING_IDENTITY/APPLE_SIGNING_IDENTITY or an installed codesigning identity"
fi

TAURI_BIN="${ROOT_DIR}/crates/gui/node_modules/.bin/tauri"
if [[ ! -x "${TAURI_BIN}" ]]; then
  fail "Tauri CLI not found at ${TAURI_BIN}; run 'make deps' first"
fi

TMP_CONFIG=""
MOUNT_DIR=""
CONFIG_ARGS=()
cleanup() {
  if [[ -n "${MOUNT_DIR}" && -d "${MOUNT_DIR}" ]]; then
    hdiutil detach "${MOUNT_DIR}" >/dev/null 2>&1 || true
    rmdir "${MOUNT_DIR}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${TMP_CONFIG}" && -f "${TMP_CONFIG}" ]]; then
    rm -f "${TMP_CONFIG}"
  fi
}
trap cleanup EXIT

if [[ -n "${SIGNING_IDENTITY}" ]]; then
  TMP_CONFIG="$(mktemp "${TMPDIR:-/tmp}/tauri-macos-signing.XXXXXX")"
  mv "${TMP_CONFIG}" "${TMP_CONFIG}.json"
  TMP_CONFIG="${TMP_CONFIG}.json"
  node -e 'const fs=require("fs"); const [path, identity, entitlements, providerShortName]=process.argv.slice(1); const mac={ signingIdentity: identity, hardenedRuntime: true }; if (entitlements) mac.entitlements=entitlements; if (providerShortName) mac.providerShortName=providerShortName; fs.writeFileSync(path, JSON.stringify({ bundle: { macOS: mac } }));' \
    "${TMP_CONFIG}" \
    "${SIGNING_IDENTITY}" \
    "${MACOS_ENTITLEMENTS:-}" \
    "${APPLE_PROVIDER_SHORT_NAME:-}"
  CONFIG_ARGS=(--config "${TMP_CONFIG}")
fi

echo "Building Tauri DMG (version=${VERSION})..."
(cd crates/gui && "${TAURI_BIN}" build --bundles dmg --ci "${CONFIG_ARGS[@]}")

DMG_DIR="target/release/bundle/dmg"
APP_DIR="target/release/bundle/macos"
DMG_PATH="$(ls -1 "${DMG_DIR}"/*.dmg 2>/dev/null | head -n 1 || true)"
APP_PATH="$(ls -1d "${APP_DIR}"/*.app 2>/dev/null | head -n 1 || true)"

if [[ -z "${DMG_PATH}" ]]; then
  fail "no DMG found in ${DMG_DIR}"
fi

if [[ -z "${APP_PATH}" && ( "${STRICT_SIGNING}" == "1" || "${PROD_RELEASE:-0}" == "1" ) ]]; then
  require_command hdiutil
  MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dmg-app-verify.XXXXXX")"
  hdiutil attach "${DMG_PATH}" -mountpoint "${MOUNT_DIR}" -nobrowse -readonly >/dev/null
  APP_PATH="$(find "${MOUNT_DIR}" -maxdepth 1 -type d -name "*.app" -print -quit)"
fi

if [[ -z "${APP_PATH}" && ( "${STRICT_SIGNING}" == "1" || "${PROD_RELEASE:-0}" == "1" ) ]]; then
  fail "no .app bundle found in ${APP_DIR} or inside ${DMG_PATH}"
fi

if [[ "${STRICT_SIGNING}" == "1" ]]; then
  echo "Verifying app signature..."
  codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
  if codesign -dv "${APP_PATH}" 2>&1 | grep -q "Signature=adhoc"; then
    fail "app is only ad-hoc signed"
  fi
fi

if [[ "${PROD_RELEASE:-0}" == "1" ]]; then
  require_command spctl
  echo "Assessing app for Developer ID distribution..."
  spctl --assess --type execute --verbose=4 "${APP_PATH}"
fi

DMG_BASENAME="$(basename "${DMG_PATH}")"
ARCH="$(echo "${DMG_BASENAME}" | sed -E "s/.*_${VERSION}_([A-Za-z0-9_]+)\.dmg/\1/")"
if [[ -z "${ARCH}" || "${ARCH}" == "${DMG_BASENAME}" ]]; then
  ARCH="unknown"
fi

OUT_PATH="dist/decentralized-browser-v${VERSION}-${ARCH}.dmg"
cp -f "${DMG_PATH}" "${OUT_PATH}"

echo "Wrote ${OUT_PATH}"

if [[ "${SIGN_DMG}" == "1" ]]; then
  if [[ -z "${SIGNING_IDENTITY}" ]]; then
    fail "SIGN_DMG=1 requires a codesigning identity"
  fi

  echo "Signing DMG..."
  if [[ "${IDENTITY_RECORD}" == *"Developer ID Application:"* ]]; then
    codesign --force --timestamp --sign "${SIGNING_IDENTITY}" "${OUT_PATH}"
  else
    codesign --force --sign "${SIGNING_IDENTITY}" "${OUT_PATH}"
  fi
  codesign --verify --verbose=2 "${OUT_PATH}"
fi

if [[ "${STRICT_NOTARIZATION}" == "1" ]]; then
  require_command xcrun
  if ! has_notary_credentials; then
    fail "STRICT_NOTARIZATION=1 requires NOTARYTOOL_PROFILE/APPLE_NOTARY_PROFILE, APPLE_ID+APPLE_PASSWORD+APPLE_TEAM_ID, or APPLE_API_KEY_PATH+APPLE_API_KEY_ID credentials"
  fi

  NOTARY_ARGS=()
  while IFS= read -r -d '' arg; do
    NOTARY_ARGS+=("${arg}")
  done < <(notary_auth_args)

  echo "Submitting DMG for notarization..."
  xcrun notarytool submit "${OUT_PATH}" --wait --timeout "${NOTARY_TIMEOUT:-30m}" "${NOTARY_ARGS[@]}"
  echo "Stapling notarization ticket..."
  xcrun stapler staple "${OUT_PATH}"
  echo "Validating DMG notarization ticket..."
  xcrun stapler validate "${OUT_PATH}"
  spctl --assess --type open --context context:primary-signature --verbose=4 "${OUT_PATH}"
fi

if command -v shasum >/dev/null 2>&1; then
  (cd dist && shasum -a 256 "$(basename "${OUT_PATH}")" > "SHA256SUMS.macos.txt")
  echo "Wrote dist/SHA256SUMS.macos.txt"
fi
