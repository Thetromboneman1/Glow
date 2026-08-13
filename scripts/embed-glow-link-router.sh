#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
router_root="$repo_root/LinkRouter"
input_ipa="${1:?Usage: embed-glow-link-router.sh INPUT_IPA OUTPUT_IPA}"
output_ipa="${2:?Usage: embed-glow-link-router.sh INPUT_IPA OUTPUT_IPA}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/glow-link-router.XXXXXX")"

cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ -f "$input_ipa" ]] || fail "Input IPA not found: $input_ipa"
[[ -f "$router_root/project.yml" ]] || fail "Link Router project is missing"
command -v xcodegen >/dev/null || fail "xcodegen is required"

"$router_root/test.sh"
xcodegen generate --spec "$router_root/project.yml" --project "$router_root"

for scheme in GlowLinkShare GlowSafariRedirect; do
  xcodebuild \
    -project "$router_root/GlowLinkRouter.xcodeproj" \
    -scheme "$scheme" \
    -configuration Release \
    -sdk iphoneos \
    -derivedDataPath "$router_root/.build" \
    CODE_SIGNING_ALLOWED=NO \
    build >/dev/null
done

products="$router_root/.build/Build/Products/Release-iphoneos"
share_product="$products/GlowLinkShare.appex"
safari_product="$products/GlowSafariRedirect.appex"
[[ -x "$share_product/GlowLinkShare" ]] || fail "Share extension did not build"
[[ -x "$safari_product/GlowSafariRedirect" ]] || fail "Safari extension did not build"

unzip -q "$input_ipa" -d "$work_dir/archive"
app_path="$(find "$work_dir/archive/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
[[ -n "$app_path" ]] || fail "No app bundle found in IPA"

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Info.plist")"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Info.plist")"
[[ -n "$bundle_id" && -n "$version" && -n "$build" ]] || fail "App metadata is incomplete"

plugins="$app_path/PlugIns"
mkdir -p "$plugins"
rm -rf "$plugins/GlowLinkShare.appex" "$plugins/GlowSafariRedirect.appex"
cp -R "$share_product" "$plugins/GlowLinkShare.appex"
cp -R "$safari_product" "$plugins/GlowSafariRedirect.appex"

share_path="$plugins/GlowLinkShare.appex"
safari_path="$plugins/GlowSafariRedirect.appex"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id.GlowLinkShare" "$share_path/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id.GlowSafariRedirect" "$safari_path/Info.plist"
for extension_path in "$share_path" "$safari_path"; do
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$extension_path/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$extension_path/Info.plist"
  rm -rf "$extension_path/_CodeSignature"
done

[[ -f "$safari_path/manifest.json" ]] || fail "Safari manifest is missing"
grep -Fq 'fb-www-link://www_link/?url=' "$safari_path/redirect.js" ||
  fail "Destination-preserving route is missing"

output_parent="$(cd "$(dirname "$output_ipa")" && pwd)"
output_name="$(basename "$output_ipa")"
rm -f "$output_parent/$output_name"
(
  cd "$work_dir/archive"
  zip -q -6 -r "$output_parent/$output_name" Payload
)
unzip -tq "$output_parent/$output_name"

printf 'Embedded Glow Link Router 1.0.3 into %s (%s)\n' "$bundle_id" "$version"
