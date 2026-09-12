#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
swift run CompanionCoreCheck
echo "CompanionCoreCheck passed"
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
  echo "xcodegen generate passed"
else
  echo "xcodegen not installed; skipped project generation"
fi
if command -v xcodebuild >/dev/null 2>&1 && [ -d /Applications/Xcode.app ]; then
  xcodebuild -scheme VibeXCompanion -destination 'generic/platform=iOS Simulator' -quiet build
  echo "xcodebuild passed"
else
  echo "Xcode.app not present; iOS target sources were not compiled by xcodebuild"
fi
