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
project_hash() { find apps/ios/Dizi.xcodeproj -type f -not -path '*/xcuserdata/*' | sort | xargs shasum | shasum; }
before=$(project_hash)
(cd apps/ios && xcodegen generate --quiet)
if [[ "$(project_hash)" != "$before" ]]; then
    echo "error: apps/ios/Dizi.xcodeproj was out of date with apps/ios/project.yml; it has been regenerated, review it" >&2
    exit 1
fi

echo "==> Parser (typecheck, lint, tests)"
npm run --silent --workspace packages/parser check

echo "==> Score examples compiled from library/"
if ! node packages/parser/src/cli.ts library/molihua.jianpu | diff -q - docs/examples/molihua.ir.json >/dev/null; then
    echo "error: docs/examples/molihua.ir.json is out of date; run: node packages/parser/src/cli.ts library/molihua.jianpu > docs/examples/molihua.ir.json" >&2
    exit 1
fi

echo "==> ScoreKit tests"
swift test --quiet --package-path packages/scorekit

echo "==> Build and test ($SIMULATOR)"
xcodebuild test -quiet \
    -project apps/ios/Dizi.xcodeproj -scheme Dizi \
    -destination "platform=iOS Simulator,name=$SIMULATOR" \
    -derivedDataPath build/DerivedData

echo "All checks passed."
