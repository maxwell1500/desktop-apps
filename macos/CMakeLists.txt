cmake_minimum_required(VERSION 3.22)
project(EuroOfficeMac LANGUAGES C CXX OBJC OBJCXX)

set(EO_MAC_STAGE_DIR "" CACHE PATH "Path to the staged desktop-sdk output tree")
set(EO_MAC_PRECOMPILED_RESOURCES_DIR "" CACHE PATH "Optional path to precompiled .storyboardc, Assets.car, and AppIcon.icns (used when Xcode's ibtool/actool are unavailable)")
set(EO_PRODUCT_NAME "Euro-Office" CACHE STRING "Application bundle and executable name")
set(EO_BUNDLE_ID "asc.euro-office.Euro-Office" CACHE STRING "CFBundleIdentifier")
set(EO_DEPLOY_TARGET "13.0" CACHE STRING "macOS deployment target")
set(EO_CODESIGN_IDENTITY "-" CACHE STRING "Code signing identity (default: ad-hoc '-')")
set(URL_WEBAPPS_HELP "" CACHE STRING "Optional URL_WEBAPPS_HELP preprocessor value")

if(NOT EO_MAC_STAGE_DIR OR NOT EXISTS "${EO_MAC_STAGE_DIR}/ascdocumentscore.framework")
    message(FATAL_ERROR "EO_MAC_STAGE_DIR must point to a staged desktop-sdk directory containing ascdocumentscore.framework")
endif()

if(NOT CMAKE_OSX_ARCHITECTURES)
    set(CMAKE_OSX_ARCHITECTURES "${CMAKE_HOST_SYSTEM_PROCESSOR}")
endif()
set(CMAKE_OSX_DEPLOYMENT_TARGET "${EO_DEPLOY_TARGET}")

file(GLOB_RECURSE APP_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/Euro-Office/*.m"
    "${CMAKE_CURRENT_SOURCE_DIR}/Euro-Office/*.mm"
    "${CMAKE_CURRENT_SOURCE_DIR}/Vendor/CocoaAnalytics/*.m"
    "${CMAKE_CURRENT_SOURCE_DIR}/Vendor/KSNavigationController/*.mm"
    "${CMAKE_CURRENT_SOURCE_DIR}/Vendor/PFMoveApplication/*.m"
    "${CMAKE_CURRENT_SOURCE_DIR}/Vendor/PureLayout/*.m"
    "${CMAKE_CURRENT_SOURCE_DIR}/Vendor/SFBPopover/*.m"
)

set_source_files_properties(
    "${CMAKE_CURRENT_SOURCE_DIR}/Vendor/PFMoveApplication/PFMoveApplication.m"
    PROPERTIES COMPILE_OPTIONS "-fno-objc-arc"
)

add_executable(EuroOfficeApp MACOSX_BUNDLE ${APP_SOURCES})

set_target_properties(EuroOfficeApp PROPERTIES
    OUTPUT_NAME "${EO_PRODUCT_NAME}"
    MACOSX_BUNDLE_GUI_IDENTIFIER "${EO_BUNDLE_ID}"
    C_STANDARD 99
    CXX_STANDARD 11
    BUILD_RPATH "@executable_path/../Frameworks;@loader_path/../Frameworks;@executable_path/../Resources/converter;@loader_path/../Resources/converter"
    INSTALL_RPATH "@executable_path/../Frameworks;@loader_path/../Frameworks;@executable_path/../Resources/converter;@loader_path/../Resources/converter"
)

target_include_directories(EuroOfficeApp PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/Euro-Office"
    "${CMAKE_CURRENT_SOURCE_DIR}/Vendor/CocoaAnalytics"
    "${CMAKE_CURRENT_SOURCE_DIR}/Vendor/KSNavigationController"
    "${CMAKE_CURRENT_SOURCE_DIR}/Vendor/PFMoveApplication"
    "${CMAKE_CURRENT_SOURCE_DIR}/Vendor/PureLayout"
    "${CMAKE_CURRENT_SOURCE_DIR}/Vendor/SFBPopover"
    "${CMAKE_CURRENT_SOURCE_DIR}/../../desktop-sdk/ChromiumBasedEditors/lib/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/../../core/Common"
    "${CMAKE_CURRENT_SOURCE_DIR}/../../core/DesktopEditor/xmlsec/src/include"
)

# Gather subdirectories for non-relative #import headers
file(GLOB_RECURSE HEADER_DIRS LIST_DIRECTORIES true "${CMAKE_CURRENT_SOURCE_DIR}/Euro-Office/Code/*")
foreach(dir ${HEADER_DIRS})
    if(IS_DIRECTORY "${dir}")
        target_include_directories(EuroOfficeApp PRIVATE "${dir}")
    endif()
endforeach()

target_compile_definitions(EuroOfficeApp PRIVATE
    _MAC
    _PRODUCT_ONLYOFFICE
    "URL_WEBAPPS_HELP=@\"${URL_WEBAPPS_HELP}\""
)

if(CMAKE_OSX_ARCHITECTURES STREQUAL "arm64")
    target_compile_definitions(EuroOfficeApp PRIVATE _ARM_ONLY)
elseif(CMAKE_OSX_ARCHITECTURES STREQUAL "x86_64")
    target_compile_definitions(EuroOfficeApp PRIVATE _X86_64_ONLY)
endif()

target_compile_options(EuroOfficeApp PRIVATE
    $<$<COMPILE_LANGUAGE:OBJC,OBJCXX>:-fobjc-arc>
    -fmodules
    "-mmacosx-version-min=${EO_DEPLOY_TARGET}"
    "-F${EO_MAC_STAGE_DIR}"
    "-F${EO_MAC_STAGE_DIR}/converter"
    "-F${CMAKE_CURRENT_SOURCE_DIR}/Vendor/Sparkle"
)

target_link_options(EuroOfficeApp PRIVATE
    "-F${EO_MAC_STAGE_DIR}"
    "-F${EO_MAC_STAGE_DIR}/converter"
    "-F${CMAKE_CURRENT_SOURCE_DIR}/Vendor/Sparkle"
    "-headerpad_max_install_names"
    "SHELL:-framework ascdocumentscore"
    "SHELL:-framework ooxmlsignature"
    "SHELL:-framework Sparkle"
    "SHELL:-framework WebKit"
    "SHELL:-framework Security"
    "SHELL:-framework Cocoa"
)

add_custom_command(TARGET EuroOfficeApp POST_BUILD
    COMMAND /usr/bin/env bash "${CMAKE_CURRENT_SOURCE_DIR}/bundle-macos.sh"
        --app "$<TARGET_BUNDLE_DIR:EuroOfficeApp>"
        --stage-dir "${EO_MAC_STAGE_DIR}"
        --product-name "${EO_PRODUCT_NAME}"
        --bundle-id "${EO_BUNDLE_ID}"
        --deploy-target "${EO_DEPLOY_TARGET}"
        --codesign-identity "${EO_CODESIGN_IDENTITY}"
        --precompiled-resources "${EO_MAC_PRECOMPILED_RESOURCES_DIR}"
    COMMENT "Bundling Euro-Office.app resources, frameworks, and helpers"
    VERBATIM
)
