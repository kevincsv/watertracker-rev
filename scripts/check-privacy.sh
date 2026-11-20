#!/usr/bin/env bash
# Fails if the app gains a way to send data anywhere other than Apple Health,
# the user's own iCloud key-value store, and the friends feature (CloudKit
# sharing from the user's own iCloud, confined to WaterTracker/Friends):
# network code, other CloudKit use, iCloud documents, remote push, or
# third-party packages.
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
check "iCloud documents in source" \
  'NSMetadataQuery|ubiquityContainer|forUbiquityContainerIdentifier|publicCloudDatabase' \
  --include='*.swift' "${sources[@]}"

# CloudKit is allowed only for the friends feature, in its own folder.
if matches=$(grep -rnIE 'CloudKit|CKContainer|CKShare|cloudKitDatabase' --include='*.swift' "${sources[@]}" | grep -v '^WaterTracker/Friends/'); then
  echo "FAIL: CloudKit used outside WaterTracker/Friends"
  echo "$matches"
  status=1
fi

# The iCloud key-value store is allowed in exactly one file: the settings.
if matches=$(grep -rnI 'NSUbiquitousKeyValueStore' --include='*.swift' "${sources[@]}" | grep -v '^WaterTracker/Model/AppSettings.swift:'); then
  echo "FAIL: iCloud key-value store used outside AppSettings.swift"
  echo "$matches"
  status=1
fi
check "analytics, ads or tracking SDKs" \
  'Firebase|Crashlytics|Sentry|Amplitude|Mixpanel|Bugsnag|AppCenter|AdSupport|ATTrackingManager|GoogleAnalytics' \
  --include='*.swift' "${sources[@]}"
check "iCloud documents or remote push entitlements" \
  'ubiquity-container|aps-environment|remote-notification|CloudDocuments' \
  --include='*.entitlements' --include='*.plist' "${sources[@]}"

# The only CloudKit entitlement allowed is the app's own container, in the
# app itself (not the widget).
if matches=$(grep -rnIE 'icloud-container|icloud-services' --include='*.entitlements' --include='*.plist' "${sources[@]}" | grep -v '^WaterTracker/WaterTracker.entitlements:'); then
  echo "FAIL: CloudKit entitlement outside the app's entitlements"
  echo "$matches"
  status=1
fi
if matches=$(grep -oE 'iCloud\.[A-Za-z0-9.-]+' WaterTracker/WaterTracker.entitlements | grep -vx 'iCloud.com.kevincsv.hidrata'); then
  echo "FAIL: unexpected iCloud container"
  echo "$matches"
  status=1
fi
check "third-party Swift packages" \
  'XCRemoteSwiftPackageReference|XCLocalSwiftPackageReference' \
  WaterTracker.xcodeproj/project.pbxproj

if [ "$status" -eq 0 ]; then
  echo "OK: data only goes to Apple Health, the iCloud key-value store and CloudKit sharing for friends."
fi
exit "$status"
