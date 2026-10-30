#!/usr/bin/env bash
# Builds an Android APK of the game from the command line, on Linux x86_64.
#
#   tools/build_apk.sh            # debug APK  -> build/paint-with-gems-debug.apk
#   tools/build_apk.sh release    # release APK (needs a release keystore, see below)
#
# Everything it needs goes in a cache folder (default ~/.cache/paint-with-gems-build,
# or $BUILD_CACHE) and nothing touches your own Godot settings:
#   - the Godot editor (GODOT_VERSION, default 4.7-stable),
#   - only the Android export templates out of the official templates bundle,
#   - the Android SDK command-line tools, platform-tools, build-tools and a platform,
#   - a debug keystore, made with keytool on first use.
# Godot runs with XDG_CONFIG_HOME / XDG_DATA_HOME / XDG_CACHE_HOME pointed into
# the cache, so its editor settings (SDK and JDK paths) and templates live there.
#
# Can't reach dl.google.com? Run with ANDROID_SDK_SOURCE=apt (see the SDK
# section below).
#
# Needs: bash, curl, unzip, a JDK 17+ (java and keytool on PATH, or JAVA_HOME).
#
# Release builds: set GODOT_ANDROID_KEYSTORE_RELEASE_PATH,
# GODOT_ANDROID_KEYSTORE_RELEASE_USER and GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
# (Godot reads them directly). Never commit a keystore.
set -euo pipefail

MODE="${1:-debug}"
case "$MODE" in debug | release) ;; *) echo "usage: $0 [debug|release]" >&2; exit 2 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_VERSION="${GODOT_VERSION:-4.7-stable}"
CACHE="${BUILD_CACHE:-$HOME/.cache/paint-with-gems-build}"
OUT_DIR="${OUT_DIR:-$ROOT/build}"
# Android SDK packages: build-tools for zipalign/apksigner, a platform Godot checks for.
ANDROID_BUILD_TOOLS="${ANDROID_BUILD_TOOLS:-35.0.1}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-35}"
CMDLINE_TOOLS_ZIP="commandlinetools-linux-13114758_latest.zip"

GODOT_DIR="$CACHE/godot-$GODOT_VERSION"
GODOT="$GODOT_DIR/Godot_v${GODOT_VERSION}_linux.x86_64"
SDK="$CACHE/android-sdk"
export XDG_CONFIG_HOME="$CACHE/xdg/config"
export XDG_DATA_HOME="$CACHE/xdg/data"
export XDG_CACHE_HOME="$CACHE/xdg/cache"
# Godot's template folder name: "4.7.stable" for "4.7-stable".
TEMPLATES="$XDG_DATA_HOME/godot/export_templates/${GODOT_VERSION/-/.}"
RELEASES="https://github.com/godotengine/godot/releases/download/$GODOT_VERSION"

mkdir -p "$CACHE" "$OUT_DIR" "$XDG_CONFIG_HOME/godot" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

fetch() {  # url dest: download with retries, only if missing
	[ -s "$2" ] && return
	echo "Downloading $1"
	curl -fsSL --retry 4 --retry-delay 2 -o "$2.part" "$1"
	mv "$2.part" "$2"
}

# --- JDK ---------------------------------------------------------------------
if [ -z "${JAVA_HOME:-}" ]; then
	JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac || command -v java)")")")"
fi
export JAVA_HOME

# --- Godot editor --------------------------------------------------------------
if [ ! -x "$GODOT" ]; then
	mkdir -p "$GODOT_DIR"
	fetch "$RELEASES/Godot_v${GODOT_VERSION}_linux.x86_64.zip" "$GODOT_DIR/godot.zip"
	unzip -o -q "$GODOT_DIR/godot.zip" -d "$GODOT_DIR"
	rm "$GODOT_DIR/godot.zip"
	chmod +x "$GODOT"
fi

# --- Android export templates (only these, out of the ~1 GB bundle) ------------
if [ ! -s "$TEMPLATES/android_release.apk" ]; then
	mkdir -p "$TEMPLATES"
	TPZ="$CACHE/Godot_v${GODOT_VERSION}_export_templates.tpz"
	fetch "$RELEASES/Godot_v${GODOT_VERSION}_export_templates.tpz" "$TPZ"
	unzip -o -q -j "$TPZ" "templates/android_*" "templates/version.txt" -d "$TEMPLATES"
	rm "$TPZ"
fi

# --- Android SDK -----------------------------------------------------------------
# A plain APK export only uses apksigner (from build-tools) and checks that
# platform-tools exists. ANDROID_SDK_SOURCE picks where they come from:
#   google (default): Google's command-line tools and sdkmanager (dl.google.com)
#   apt: Ubuntu/Debian's apksigner, zipalign and adb packages (installed if
#        missing, with sudo when not root), linked into a minimal SDK layout;
#        for machines that can't reach dl.google.com
#   existing: use $ANDROID_HOME as it is
ANDROID_SDK_SOURCE="${ANDROID_SDK_SOURCE:-google}"
case "$ANDROID_SDK_SOURCE" in
existing)
	SDK="${ANDROID_HOME:?ANDROID_HOME must point at an Android SDK}"
	;;
apt)
	SDK="$CACHE/android-sdk-apt"
	if ! command -v apksigner >/dev/null || ! command -v zipalign >/dev/null || ! command -v adb >/dev/null; then
		SUDO=""
		[ "$(id -u)" -eq 0 ] || SUDO="sudo"
		$SUDO apt-get update -q
		DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -q apksigner zipalign adb
	fi
	mkdir -p "$SDK/build-tools/$ANDROID_BUILD_TOOLS" "$SDK/platform-tools" "$SDK/platforms/$ANDROID_PLATFORM"
	ln -sf "$(command -v apksigner)" "$SDK/build-tools/$ANDROID_BUILD_TOOLS/apksigner"
	ln -sf "$(command -v zipalign)" "$SDK/build-tools/$ANDROID_BUILD_TOOLS/zipalign"
	ln -sf "$(command -v adb)" "$SDK/platform-tools/adb"
	;;
google)
	if [ ! -x "$SDK/build-tools/$ANDROID_BUILD_TOOLS/apksigner" ]; then
		if [ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]; then
			fetch "https://dl.google.com/android/repository/$CMDLINE_TOOLS_ZIP" "$CACHE/$CMDLINE_TOOLS_ZIP"
			rm -rf "$SDK/cmdline-tools"
			mkdir -p "$SDK/cmdline-tools"
			unzip -o -q "$CACHE/$CMDLINE_TOOLS_ZIP" -d "$SDK/cmdline-tools"
			mv "$SDK/cmdline-tools/cmdline-tools" "$SDK/cmdline-tools/latest"
		fi
		yes | "$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" --licenses >/dev/null || true
		"$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" \
			"platform-tools" "build-tools;$ANDROID_BUILD_TOOLS" "platforms;$ANDROID_PLATFORM"
	fi
	;;
*)
	echo "ANDROID_SDK_SOURCE must be google, apt or existing" >&2
	exit 2
	;;
esac
export ANDROID_HOME="$SDK"

# --- Debug keystore --------------------------------------------------------------
KEYSTORE="$CACHE/debug.keystore"
if [ ! -s "$KEYSTORE" ]; then
	keytool -genkeypair -v -keystore "$KEYSTORE" -storepass android -alias androiddebugkey \
		-keypass android -keyalg RSA -keysize 2048 -validity 10000 \
		-dname "CN=Android Debug,O=Android,C=US" >/dev/null
fi

# --- Godot editor settings (in the cache, not yours) -----------------------------
SHORT="$(echo "$GODOT_VERSION" | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')"
cat >"$XDG_CONFIG_HOME/godot/editor_settings-$SHORT.tres" <<EOF
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$SDK"
export/android/java_sdk_path = "$JAVA_HOME"
export/android/debug_keystore = "$KEYSTORE"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
EOF
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$KEYSTORE"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER="androiddebugkey"
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="android"

# --- Import and export -------------------------------------------------------------
cd "$ROOT"
echo "Importing the project (registers class names)"
"$GODOT" --headless --import --path "$ROOT" >/dev/null 2>&1 || "$GODOT" --headless --import --path "$ROOT"
echo "Checking that every script compiles"
"$GODOT" --headless --path "$ROOT" -s res://tools/check_scripts.gd
APK="$OUT_DIR/paint-with-gems-$MODE.apk"
echo "Exporting $APK"
"$GODOT" --headless --path "$ROOT" "--export-$MODE" "Android" "$APK"
[ -s "$APK" ] || { echo "Export failed: no APK written" >&2; exit 1; }
echo "Built $APK ($(du -h "$APK" | cut -f1))"
