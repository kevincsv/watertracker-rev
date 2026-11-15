#!/usr/bin/env bash
# Fails if the app gains any way to send data off the device: network code,
# iCloud/CloudKit, remote push, or third-party packages.
set -euo pipefail
cd "$(dirname "$0")/.."

status=0
check() {
  local description=$1 pattern=$2
  shift 2
  if matches=$(grep -rnIE "$pattern" "$@" 2>/dev/null); then
    echo "FAIL: $description"
    echo "$matches"
    status=1
  fi
}

sources=(Shared WaterTracker "WaterTracker Widget")

check "network or web APIs in source" \
  'URLSession|URLRequest|NSURLConnection|WKWebView|SFSafariViewController|NWConnection|CFNetwork|import Network|WebSocket|https?://' \
  --include='*.swift' "${sources[@]}"
check "CloudKit or iCloud in source" \
  'CloudKit|CKContainer|NSUbiquitous|cloudKitDatabase' \
  --include='*.swift' "${sources[@]}"
check "analytics, ads or tracking SDKs" \
  'Firebase|Crashlytics|Sentry|Amplitude|Mixpanel|Bugsnag|AppCenter|AdSupport|ATTrackingManager|GoogleAnalytics' \
  --include='*.swift' "${sources[@]}"
check "iCloud or remote push entitlements" \
  'icloud|aps-environment|remote-notification' \
  --include='*.entitlements' --include='*.plist' "${sources[@]}"
check "third-party Swift packages" \
  'XCRemoteSwiftPackageReference|XCLocalSwiftPackageReference' \
  WaterTracker.xcodeproj/project.pbxproj

if [ "$status" -eq 0 ]; then
  echo "OK: nothing in the app can send data off the device."
fi
exit "$status"
