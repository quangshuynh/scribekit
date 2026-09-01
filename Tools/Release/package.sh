#!/bin/bash
#
# Builds the ScribeKit distribution candidate: a Developer ID signed, notarized
# and stapled disk image.
#
# Run from the repository root. Everything it writes lands in build/release,
# which is not tracked. It stores no credentials: notarization reads the
# keychain profile named by SCRIBEKIT_NOTARY_PROFILE (default "ScribeKit"),
# created once with:
#
#     xcrun notarytool store-credentials ScribeKit \
#         --apple-id <apple-id> --team-id <team-id>
#
# Only the archive step of this script has been exercised. The export,
# notarization, stapling and disk-image steps have never run, because no
# Developer ID Application certificate exists for this project yet; the DMG
# layout below was proved separately with the same hdiutil invocation. Treat
# what follows the archive as the intended sequence rather than as a tested
# one, and read its output rather than its exit status the first time it runs.
#
# Usage:
#     Tools/Release/package.sh
#
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
version=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' "$root/ScribeKit.xcodeproj/project.pbxproj" | head -1)
profile="${SCRIBEKIT_NOTARY_PROFILE:-ScribeKit}"

out="$root/build/release"
archive="$out/ScribeKit.xcarchive"
export_dir="$out/export"
staging="$out/dmg"
dmg="$out/ScribeKit-$version.dmg"

rm -rf "$archive" "$export_dir" "$staging" "$dmg"
mkdir -p "$out"

echo "==> Archiving (Release, Developer ID)"
xcodebuild -project "$root/ScribeKit.xcodeproj" \
    -scheme ScribeKit \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$archive" \
    archive

echo "==> Exporting the Developer ID application"
xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportPath "$export_dir" \
    -exportOptionsPlist "$root/Tools/Release/ExportOptions.plist"

app="$export_dir/ScribeKit.app"

echo "==> Verifying the exported application"
codesign --verify --deep --strict --verbose=2 "$app"
codesign -d --verbose=4 "$app" 2>&1 | grep -E 'Authority|TeamIdentifier|flags|Identifier'
codesign -d --entitlements :- "$app"

echo "==> Notarizing the application"
ditto -c -k --keepParent "$app" "$out/ScribeKit.zip"
xcrun notarytool submit "$out/ScribeKit.zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"

echo "==> Building $dmg"
mkdir -p "$staging"
cp -R "$app" "$staging/ScribeKit.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "ScribeKit $version" \
    -srcfolder "$staging" \
    -fs HFS+ -format UDZO \
    "$dmg"

echo "==> Notarizing the disk image"
xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"

echo "==> Result"
spctl --assess --type open --context context:primary-signature -vv "$dmg"
shasum -a 256 "$dmg"
ls -lh "$dmg"
