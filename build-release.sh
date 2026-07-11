#!/bin/bash
set -e

echo "=== novfind Release Build ==="
VERSION=$(sed -n 's/^version: //p' pubspec.yaml | sed 's/+.*//')
echo "Version: $VERSION"

echo ""
echo "=== 1. Clean ==="
flutter clean

echo ""
echo "=== 2. Dependencies ==="
flutter pub get

echo ""
echo "=== 3. Fix flutter_inappwebview Gradle compat ==="
INAPPWEBVIEW_BUILD=$(find ~/.pub-cache -path "*/flutter_inappwebview_android-*/android/build.gradle" 2>/dev/null | head -1)
if [ -n "$INAPPWEBVIEW_BUILD" ]; then
  sed -i 's/proguard-android\.txt/proguard-android-optimize.txt/g' "$INAPPWEBVIEW_BUILD"
  echo "  Patched: $INAPPWEBVIEW_BUILD"
fi

echo ""
echo "=== 4. Tests ==="
flutter test

echo ""
echo "=== 5. Release APK ==="
flutter build apk --release

echo ""
echo "=== 6. Versioned APK ==="
cp build/app/outputs/flutter-apk/app-release.apk "build/app/outputs/flutter-apk/novfind-v${VERSION}.apk"
echo "  build/app/outputs/flutter-apk/novfind-v${VERSION}.apk"

echo ""
echo "=== Done ==="
echo "Release: v$VERSION"
echo "APK: $(ls -lh build/app/outputs/flutter-apk/novfind-v${VERSION}.apk | awk '{print $5}')"
