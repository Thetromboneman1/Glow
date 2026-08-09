#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/glow-link-tests.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

xcrun clang \
  -fobjc-arc \
  -fblocks \
  -framework Foundation \
  -I"$root/Sources" \
  "$root/Sources/GlowLinkRouting.m" \
  "$root/Tests/GlowLinkRoutingTests.m" \
  -o "$build_dir/GlowLinkRoutingTests"

"$build_dir/GlowLinkRoutingTests"
node "$root/Tests/GlowSafariRedirectTests.js"
