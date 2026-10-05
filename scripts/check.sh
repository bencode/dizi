#!/usr/bin/env bash
# Runs every check: format, lint, project sync, build, and tests. All must pass before work is done.
set -euo pipefail
cd "$(dirname "$0")/.."

SIMULATOR="${SIMULATOR:-iPhone 17e}"
swift_files=()
while IFS= read -r file; do swift_files+=("$file"); done \
    < <(git ls-files --cached --others --exclude-standard -- '*.swift')

echo "==> Format"
xcrun swift-format lint --strict --parallel "${swift_files[@]}"

echo "==> Lint"
swiftlint lint --quiet

echo "==> Project"
project_hash() { find App/Dizi.xcodeproj -type f -not -path '*/xcuserdata/*' | sort | xargs shasum | shasum; }
before=$(project_hash)
(cd App && xcodegen generate --quiet)
if [[ "$(project_hash)" != "$before" ]]; then
    echo "error: App/Dizi.xcodeproj was out of date with App/project.yml; it has been regenerated, review it" >&2
    exit 1
fi

echo "==> Build and test ($SIMULATOR)"
xcodebuild test -quiet \
    -project App/Dizi.xcodeproj -scheme Dizi \
    -destination "platform=iOS Simulator,name=$SIMULATOR" \
    -derivedDataPath build/DerivedData

echo "All checks passed."
