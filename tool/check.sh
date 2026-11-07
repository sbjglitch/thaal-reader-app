#!/usr/bin/env bash
# Local validation for the app: format, analysis, tests.
# Pass --build to also build the Android debug APK.
# iOS builds are deferred (see docs/READER_ENGINE_SPIKE.md).
set -euo pipefail
cd "$(dirname "$0")/.."

echo '==> dart format'
dart format --output=none --set-exit-if-changed lib test

echo '==> flutter analyze'
flutter analyze

echo '==> flutter test'
flutter test

if [[ "${1:-}" == '--build' ]]; then
  echo '==> flutter build apk --debug'
  flutter build apk --debug
fi

echo 'All checks passed.'
