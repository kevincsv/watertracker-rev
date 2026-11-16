#!/usr/bin/env bash
# Fails if the app gains a way to send data anywhere other than Apple Health
# and the user's own iCloud key-value store: network code, CloudKit, iCloud
# documents, remote push, or third-party packages.
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
check "CloudKit or iCloud documents in source" \
  'CloudKit|CKContainer|cloudKitDatabase|NSMetadataQuery|ubiquityContainer|forUbiquityContainerIdentifier' \
  --include='*.swift' "${sources[@]}"

# The iCloud key-value store is allowed in exactly one file: the settings.
if matches=$(grep -rnI 'NSUbiquitousKeyValueStore' --include='*.swift' "${sources[@]}" | grep -v '^WaterTracker/Model/AppSettings.swift:'); then
  echo "FAIL: iCloud key-value store used outside AppSettings.swift"
  echo "$matches"
  status=1
fi
check "analytics, ads or tracking SDKs" \
  'Firebase|Crashlytics|Sentry|Amplitude|Mixpanel|Bugsnag|AppCenter|AdSupport|ATTrackingManager|GoogleAnalytics' \
  --include='*.swift' "${sources[@]}"
check "CloudKit, iCloud documents or remote push entitlements" \
  'icloud-container|icloud-services|ubiquity-container|aps-environment|remote-notification' \
  --include='*.entitlements' --include='*.plist' "${sources[@]}"
check "third-party Swift packages" \
  'XCRemoteSwiftPackageReference|XCLocalSwiftPackageReference' \
  WaterTracker.xcodeproj/project.pbxproj

if [ "$status" -eq 0 ]; then
  echo "OK: data only goes to Apple Health and the iCloud key-value store."
fi
exit "$status"
