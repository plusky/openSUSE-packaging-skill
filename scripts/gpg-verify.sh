#!/bin/bash
# Verify a signed source tarball against a package keyring.
# Avoids the gpgv trap: gpgv --keyring FAILS on an ASCII-armored keyring
# ("invalid packet (ctb=2d)"), so import into a throwaway homedir and gpg --verify.
#
# Usage: gpg-verify.sh <tarball> <keyring> [signature]
#   signature defaults to <tarball>.asc, then <tarball>.sig
set -euo pipefail
[ $# -ge 2 ] || { sed -n '2,8p' "$0"; exit 2; }
tarball="$1" ; keyring="$2"
sig="${3:-}"
if [ -z "$sig" ]; then
  for c in "$tarball.asc" "$tarball.sig"; do [ -f "$c" ] && { sig="$c"; break; }; done
fi
[ -f "$sig" ] || { echo "no signature found for $tarball" >&2; exit 2; }

export GNUPGHOME="$(mktemp -d)"
trap 'rm -rf "$GNUPGHOME"' EXIT
gpg --import "$keyring" >/dev/null 2>&1
if gpg --verify "$sig" "$tarball" 2>&1 | grep -q "Good signature"; then
  gpg --verify "$sig" "$tarball" 2>&1 | grep -iE "Good signature|using"
  echo "OK"
else
  echo "BAD or UNVERIFIABLE signature — upstream may have rotated keys; update the keyring." >&2
  gpg --verify "$sig" "$tarball" 2>&1 | tail -3 >&2
  exit 1
fi
