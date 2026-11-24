#!/usr/bin/env bash
# Post-build bundler for the Xcode-free CMake build (desktop-apps/macos/CMakeLists.txt).
# Mirrors the Xcode Copy Resources, Render About text, Copy Frameworks, and
# Rename symbols phases using only standard macOS CLI tools.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_BUNDLE=""
STAGE_DIR=""
PRODUCT_NAME="Euro-Office"
BUNDLE_ID="asc.euro-office.Euro-Office"
DEPLOY_TARGET="13.0"
CODESIGN_IDENTITY="-"
PRECOMPILED_RES_DIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --app) APP_BUNDLE="$2"; shift 2 ;;
        --stage-dir) STAGE_DIR="$2"; shift 2 ;;
        --product-name) PRODUCT_NAME="$2"; shift 2 ;;
        --bundle-id) BUNDLE_ID="$2"; shift 2 ;;
        --deploy-target) DEPLOY_TARGET="$2"; shift 2 ;;
        --codesign-identity) CODESIGN_IDENTITY="$2"; shift 2 ;;
        --precompiled-resources) PRECOMPILED_RES_DIR="$2"; shift 2 ;;
        *) echo "error: unknown argument: $1" 1>&2; exit 1 ;;
    esac
done

CONTENTS="${APP_BUNDLE}/Contents"
RESOURCES="${CONTENTS}/Resources"
FRAMEWORKS="${CONTENTS}/Frameworks"
ENTITLEMENTS="${SCRIPT_DIR}/Euro-Office/Resources/Euro-Office-arm/Euro-Office.entitlements"
INFO_PLIST_SRC="${SCRIPT_DIR}/Euro-Office/Resources/Euro-Office-arm/Info.plist"

mkdir -p "${RESOURCES}" "${FRAMEWORKS}"

echo "==> Writing Info.plist"
python3 - "${INFO_PLIST_SRC}" "${CONTENTS}/Info.plist" "${PRODUCT_NAME}" "${BUNDLE_ID}" "${DEPLOY_TARGET}" <<'PYEOF'
import sys
src, dst, product, bundle_id, deploy = sys.argv[1:]
with open(src, "r", encoding="utf-8") as f:
    text = f.read()
text = text.replace("$(EXECUTABLE_NAME)", product)
text = text.replace("$(PRODUCT_NAME)", product)
text = text.replace("$(PRODUCT_BUNDLE_IDENTIFIER)", bundle_id)
text = text.replace("$(MACOSX_DEPLOYMENT_TARGET)", deploy)
with open(dst, "w", encoding="utf-8") as f:
    f.write(text)
PYEOF

echo "==> Copying staged editors, converter, providers, and login resources"
rm -rf "${RESOURCES}/login" "${RESOURCES}/providers" "${RESOURCES}/editors" "${RESOURCES}/converter" "${RESOURCES}/license" "${RESOURCES}/dictionaries"
mkdir -p "${RESOURCES}/login" "${RESOURCES}/license"
cp -R "${STAGE_DIR}/index.html" "${RESOURCES}/login/index.html"
cp -R "${STAGE_DIR}/editors/webext/noconnect.html" "${RESOURCES}/login/noconnect.html"
cp -R "${STAGE_DIR}/fonts" "${RESOURCES}/login/fonts"
cp -R "${SCRIPT_DIR}/Euro-Office/Resources/acknowledgments.html" "${RESOURCES}/login/acknowledgments.html"
cp -R "${STAGE_DIR}/providers" "${RESOURCES}/providers"
cp -R "${STAGE_DIR}/editors" "${RESOURCES}/editors"
cp -R "${STAGE_DIR}/converter" "${RESOURCES}/converter"

if [ -d "${SCRIPT_DIR}/../../dictionaries" ]; then
    cp -R "${SCRIPT_DIR}/../../dictionaries" "${RESOURCES}/dictionaries"
fi

ABOUT_SCRIPT="${ABOUT_HTML_SCRIPT:-${SCRIPT_DIR}/../../web-apps/build/about-html.mjs}"
if [ -f "${ABOUT_SCRIPT}" ] && command -v node >/dev/null 2>&1; then
    echo "==> Rendering About text"
    node "${ABOUT_SCRIPT}" > "${RESOURCES}/about.html"
fi

echo "==> Copying icons and localizations"
cp "${SCRIPT_DIR}/Euro-Office/Resources/file-formats/"*.icns "${RESOURCES}/"

for lproj in "${SCRIPT_DIR}/Euro-Office/"*.lproj "${SCRIPT_DIR}/Euro-Office/Resources/Euro-Office-arm/"*.lproj; do
    [ -d "${lproj}" ] || continue
    base="$(basename "${lproj}")"
    mkdir -p "${RESOURCES}/${base}"
    for f in "${lproj}"/*.strings "${lproj}"/*.stringsdict; do
        [ -f "${f}" ] && cp "${f}" "${RESOURCES}/${base}/"
    done
done

echo "==> Handling storyboards and asset catalog"
if [ -n "${PRECOMPILED_RES_DIR}" ]; then
    for sb in Main Document-Sign Presentation-Reporter Separate-Editor; do
        if [ ! -d "${PRECOMPILED_RES_DIR}/${sb}.storyboardc" ]; then
            echo "error: missing ${PRECOMPILED_RES_DIR}/${sb}.storyboardc" 1>&2
            exit 1
        fi
        rm -rf "${RESOURCES}/Base.lproj/${sb}.storyboardc"
        mkdir -p "${RESOURCES}/Base.lproj"
        cp -R "${PRECOMPILED_RES_DIR}/${sb}.storyboardc" "${RESOURCES}/Base.lproj/"
    done
    [ -f "${PRECOMPILED_RES_DIR}/Assets.car" ] && cp "${PRECOMPILED_RES_DIR}/Assets.car" "${RESOURCES}/"
    [ -f "${PRECOMPILED_RES_DIR}/AppIcon.icns" ] && cp "${PRECOMPILED_RES_DIR}/AppIcon.icns" "${RESOURCES}/"
elif xcrun --find ibtool >/dev/null 2>&1 && xcrun --find actool >/dev/null 2>&1; then
    mkdir -p "${RESOURCES}/Base.lproj"
    for sb in Main Document-Sign Presentation-Reporter Separate-Editor; do
        xcrun ibtool --compile "${RESOURCES}/Base.lproj/${sb}.storyboardc" \
            "${SCRIPT_DIR}/Euro-Office/Base.lproj/${sb}.storyboard"
    done
    xcrun actool --compile "${RESOURCES}" --platform macosx --minimum-deployment-target "${DEPLOY_TARGET}" \
        --app-icon AppIcon --output-partial-info-plist /dev/null \
        "${SCRIPT_DIR}/Euro-Office/Images.xcassets"
else
    cat >&2 <<EOF
error: Xcode's ibtool/actool are not available (Command Line Tools only).
Pass -DEO_MAC_PRECOMPILED_RESOURCES_DIR=/path/to/Resources pointing to a directory
containing precompiled *.storyboardc bundles, Assets.car, and AppIcon.icns
(for example, extracted from an existing Euro-Office.app/Contents/Resources).
EOF
    exit 1
fi

echo "==> Embedding frameworks and helpers"
restructure_cef_framework() {
    local dst="$1" src="$2" real_src
    real_src="$(cd "$src" && pwd -P)"
    rm -rf "$dst"
    mkdir -p "$dst/Versions/A"
    cp -R "${real_src}/." "$dst/Versions/A/"
    ln -sfn "A" "$dst/Versions/Current"
    ln -sfn "Versions/Current/Chromium Embedded Framework" "$dst/Chromium Embedded Framework"
    ln -sfn "Versions/Current/Libraries" "$dst/Libraries"
    ln -sfn "Versions/Current/Resources" "$dst/Resources"
}

rm -rf "${FRAMEWORKS}/Sparkle.framework" \
       "${FRAMEWORKS}/Chromium Embedded Framework.framework" \
       "${FRAMEWORKS}/editors_helper.app" \
       "${FRAMEWORKS}/editors_helper (GPU).app" \
       "${FRAMEWORKS}/editors_helper (Renderer).app" \
       "${FRAMEWORKS}/ascdocumentscore.framework" \
       "${FRAMEWORKS}/ooxmlsignature.framework"

cp -R "${SCRIPT_DIR}/Vendor/Sparkle/Sparkle.framework" "${FRAMEWORKS}/"
cp -R "${STAGE_DIR}/editors_helper.app" "${FRAMEWORKS}/"
cp -R "${STAGE_DIR}/editors_helper (GPU).app" "${FRAMEWORKS}/"
cp -R "${STAGE_DIR}/editors_helper (Renderer).app" "${FRAMEWORKS}/"
cp -R "${STAGE_DIR}/ascdocumentscore.framework" "${FRAMEWORKS}/"
cp -R "${STAGE_DIR}/ooxmlsignature.framework" "${FRAMEWORKS}/"
restructure_cef_framework "${FRAMEWORKS}/Chromium Embedded Framework.framework" "${STAGE_DIR}/Chromium Embedded Framework.framework"

ln -sfn "../../../Chromium Embedded Framework.framework" "${FRAMEWORKS}/editors_helper.app/Contents/Frameworks/Chromium Embedded Framework.framework"
ln -sfn "../../../Chromium Embedded Framework.framework" "${FRAMEWORKS}/editors_helper (GPU).app/Contents/Frameworks/Chromium Embedded Framework.framework"
ln -sfn "../../../Chromium Embedded Framework.framework" "${FRAMEWORKS}/editors_helper (Renderer).app/Contents/Frameworks/Chromium Embedded Framework.framework"

install_name_tool -change \
    "@executable_path/../Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework" \
    "@rpath/Chromium Embedded Framework.framework/Chromium Embedded Framework" \
    "${CONTENTS}/MacOS/${PRODUCT_NAME}"

echo "==> Code signing (${CODESIGN_IDENTITY})"
codesign --force --sign "${CODESIGN_IDENTITY}" --preserve-metadata=identifier,entitlements "${FRAMEWORKS}/ooxmlsignature.framework/Versions/Current"
codesign --force --sign "${CODESIGN_IDENTITY}" --preserve-metadata=identifier,entitlements "${FRAMEWORKS}/ascdocumentscore.framework/Versions/Current"
for fw in "${RESOURCES}/converter"/*.framework; do
    [ -d "$fw" ] && codesign --force --sign "${CODESIGN_IDENTITY}" --preserve-metadata=identifier,entitlements "$fw/Versions/Current"
done
codesign --force --options runtime --entitlements "${ENTITLEMENTS}" --sign "${CODESIGN_IDENTITY}" "${RESOURCES}/converter/x2t"
for lib in libEGL.dylib libGLESv2.dylib libvk_swiftshader.dylib; do
    [ -f "${FRAMEWORKS}/Chromium Embedded Framework.framework/Libraries/${lib}" ] && \
        codesign --force --deep --options runtime --sign "${CODESIGN_IDENTITY}" "${FRAMEWORKS}/Chromium Embedded Framework.framework/Libraries/${lib}"
done
codesign --force --deep --options runtime --sign "${CODESIGN_IDENTITY}" "${FRAMEWORKS}/Chromium Embedded Framework.framework"
for helper in "editors_helper.app" "editors_helper (GPU).app" "editors_helper (Renderer).app"; do
    codesign --force --deep --options runtime --sign "${CODESIGN_IDENTITY}" --entitlements "${ENTITLEMENTS}" "${FRAMEWORKS}/${helper}"
done
codesign --force --options runtime --sign "${CODESIGN_IDENTITY}" "${FRAMEWORKS}/Sparkle.framework/Versions/B"
codesign --force --options runtime --entitlements "${ENTITLEMENTS}" --sign "${CODESIGN_IDENTITY}" "${CONTENTS}/MacOS/${PRODUCT_NAME}"
