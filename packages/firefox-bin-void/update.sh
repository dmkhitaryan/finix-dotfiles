#!/usr/bin/env nix-shell
#!nix-shell -i bash -p xbps nix jq gnused

set -euo pipefail

repo="https://repo-default.voidlinux.org/current/aarch64"
file="$(dirname "$0")/default.nix"

export XBPS_ARCH=aarch64-musl

update() {
  local pkg="$1"
  local var="$2"

  local pkgver
  pkgver="$(
    xbps-query \
      --memory-sync \
      --repository "$repo" \
      --property pkgver \
      -R \
      "$pkg"
  )"

  local version="${pkgver#"$pkg"-}"
  local url="$repo/$pkgver.aarch64-musl.xbps"

  local hash
  hash="$(
    nix store prefetch-file --json "$url" |
      jq -r .hash
  )"

  echo "$pkg -> $version"

  sed -i \
    "/^[[:space:]]*${var} = fetchurl rec {/,/^[[:space:]]*};/ {
      s#^[[:space:]]*version = \".*\";#  version = \"$version\";#
      s#^[[:space:]]*hash = \".*\";#  hash = \"$hash\";#
    }" \
    "$file"
}

update firefox firefoxXbps
update libffi libffiXbps
update libjpeg-turbo libjpegXbps
