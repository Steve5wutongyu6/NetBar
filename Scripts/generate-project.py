#!/usr/bin/env python3
"""Generates NetBar.xcodeproj/project.pbxproj.

The project file is a build artifact of this script, not a hand-edited file:
adding a source means adding a line below and re-running it. Object ids are
derived from the file's role so regeneration is stable and diffs stay small.
"""

import hashlib
import os
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROJECT = ROOT / "NetBar.xcodeproj" / "project.pbxproj"

def oid(role: str) -> str:
    return hashlib.md5(f"netbar:{role}".encode()).hexdigest().upper()[:24]

# (display path, group) for every file the app compiles or links.
SOURCES = [
    ("NetBar/App/AppDelegate.swift", "App"),
    ("NetBar/App/Diagnostics.swift", "App"),
    ("NetBar/App/EngineBridge.swift", "App"),
    ("NetBar/App/MenuBarPanel.swift", "App"),
    ("NetBar/App/MenuRowViews.swift", "App"),
    ("NetBar/App/NetBarApp.swift", "App"),
    ("NetBar/App/SnapshotRenderer.swift", "App"),
    ("NetBar/App/WiFiIcon.swift", "App"),
    ("NetBar/App/WiFiStore.swift", "App"),
    ("NetBar/Bridge/NBWiFiBridge.m", "Bridge"),
    ("NetBar/Bridge/NBWiFiHotspot.m", "Bridge"),
    ("NetBar/Bridge/NBWiFiModels.m", "Bridge"),
    ("NetBar/Bridge/NBHotspotMonitor.m", "Bridge"),
    ("NetBar/Bridge/NBWiFiMonitor.m", "Bridge"),
    ("NetBar/Bridge/NBLocationAuthorizer.m", "Bridge"),
    ("Contracts/NBNodeJSON.m", "Contracts"),
]

HEADERS = [
    ("NetBar/NetBar-Bridging-Header.h", "NetBar"),
    ("NetBar/Bridge/NBWiFiBridge.h", "Bridge"),
    ("NetBar/Bridge/NBWiFiHotspot.h", "Bridge"),
    ("NetBar/Bridge/NBWiFiModels.h", "Bridge"),
    ("NetBar/Bridge/NBHotspotMonitor.h", "Bridge"),
    ("NetBar/Bridge/NBWiFiMonitor.h", "Bridge"),
    ("NetBar/Bridge/NBLocationAuthorizer.h", "Bridge"),
    ("Contracts/NBEngineExports.h", "Contracts"),
    ("Contracts/NBNodeJSON.h", "Contracts"),
]

CONFIGS = [
    "Configs/Shared.xcconfig",
    "Configs/Debug.xcconfig",
    "Configs/Release.xcconfig",
]

TEST_SOURCES = [
    ("NetBarTests/EngineTests.swift", "NetBarTests"),
    ("NetBarTests/HotspotDecodingTests.swift", "NetBarTests"),
    ("NetBarTests/MenuRenderTests.swift", "NetBarTests"),
]

# Fixtures ship inside the app so `--fixture/--snapshot` work from a built bundle.
RESOURCE_FOLDERS = [("NetBarTests/Fixtures", "NetBarTests")]

APP = "NetBar"
TESTS = "NetBarTests"

lines: list[str] = []
def emit(text: str = "") -> None:
    lines.append(text)

def file_type(path: str) -> str:
    if path.endswith(".swift"):
        return "sourcecode.swift"
    if path.endswith(".m"):
        return "sourcecode.c.objc"
    if path.endswith(".h"):
        return "sourcecode.c.h"
    if path.endswith(".xcconfig"):
        return "text.xcconfig"
    return "text"

groups: dict[str, list[str]] = {}
for path, group in SOURCES + HEADERS:
    groups.setdefault(group, []).append(path)
for path, group in TEST_SOURCES:
    groups.setdefault(group, []).append(path)
groups.setdefault("Configs", []).extend(CONFIGS)

emit("// !$*UTF8*$!")
emit("{")
emit("\tarchiveVersion = 1;")
emit("\tclasses = {")
emit("\t};")
emit("\tobjectVersion = 77;")
emit("\tobjects = {")

# --- PBXBuildFile -----------------------------------------------------------
emit()
emit("/* Begin PBXBuildFile section */")
for path, _ in SOURCES:
    emit(f"\t\t{oid('build:' + path)} /* {os.path.basename(path)} in Sources */ = "
         f"{{isa = PBXBuildFile; fileRef = {oid('file:' + path)} /* {os.path.basename(path)} */; }};")
for path, _ in TEST_SOURCES:
    emit(f"\t\t{oid('build:' + path)} /* {os.path.basename(path)} in Sources */ = "
         f"{{isa = PBXBuildFile; fileRef = {oid('file:' + path)} /* {os.path.basename(path)} */; }};")
for path, _ in RESOURCE_FOLDERS:
    emit(f"\t\t{oid('build:' + path)} /* {os.path.basename(path)} in Resources */ = "
         f"{{isa = PBXBuildFile; fileRef = {oid('file:' + path)} /* {os.path.basename(path)} */; }};")
emit("/* End PBXBuildFile section */")

# --- PBXContainerItemProxy --------------------------------------------------
emit()
emit("/* Begin PBXContainerItemProxy section */")
emit(f"\t\t{oid('proxy:tests')} = {{")
emit("\t\t\tisa = PBXContainerItemProxy;")
emit(f"\t\t\tcontainerPortal = {oid('project')};")
emit("\t\t\tproxyType = 1;")
emit(f"\t\t\tremoteGlobalIDString = {oid('target:app')};")
emit(f"\t\t\tremoteInfo = {APP};")
emit("\t\t};")
emit("/* End PBXContainerItemProxy section */")

# --- PBXFileReference -------------------------------------------------------
emit()
emit("/* Begin PBXFileReference section */")
emit(f"\t\t{oid('product:app')} /* {APP}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {APP}.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
emit(f"\t\t{oid('product:tests')} /* {TESTS}.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = {TESTS}.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
for path, _ in SOURCES + HEADERS + TEST_SOURCES:
    emit(f"\t\t{oid('file:' + path)} /* {os.path.basename(path)} */ = {{isa = PBXFileReference; "
         f"lastKnownFileType = {file_type(path)}; path = {os.path.basename(path)}; sourceTree = \"<group>\"; }};")
for path in CONFIGS:
    emit(f"\t\t{oid('file:' + path)} /* {os.path.basename(path)} */ = {{isa = PBXFileReference; "
         f"lastKnownFileType = text.xcconfig; name = {os.path.basename(path)}; path = {path}; sourceTree = \"<group>\"; }};")
for path, _ in RESOURCE_FOLDERS:
    emit(f"\t\t{oid('file:' + path)} /* {os.path.basename(path)} */ = {{isa = PBXFileReference; "
         f"lastKnownFileType = folder; path = {os.path.basename(path)}; sourceTree = \"<group>\"; }};")
emit("/* End PBXFileReference section */")

# --- PBXFrameworksBuildPhase ------------------------------------------------
emit()
emit("/* Begin PBXFrameworksBuildPhase section */")
for role in ("app", "tests"):
    emit(f"\t\t{oid('frameworks:' + role)} = {{")
    emit("\t\t\tisa = PBXFrameworksBuildPhase;")
    emit("\t\t\tbuildActionMask = 2147483647;")
    emit("\t\t\tfiles = (")
    emit("\t\t\t);")
    emit("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    emit("\t\t};")
emit("/* End PBXFrameworksBuildPhase section */")

# --- PBXGroup ---------------------------------------------------------------
def group_body(group_id: str, name: str, children: list[str], path: str | None = None) -> None:
    emit(f"\t\t{group_id} /* {name} */ = {{")
    emit("\t\t\tisa = PBXGroup;")
    emit("\t\t\tchildren = (")
    for child in children:
        emit(f"\t\t\t\t{child},")
    emit("\t\t\t);")
    if path is not None:
        emit(f"\t\t\tpath = {path};")
    else:
        emit(f"\t\t\tname = {name};")
    emit("\t\t\tsourceTree = \"<group>\";")
    emit("\t\t};")

emit()
emit("/* Begin PBXGroup section */")
emit(f"\t\t{oid('group:root')} = {{")
emit("\t\t\tisa = PBXGroup;")
emit("\t\t\tchildren = (")
# Nested groups belong to their parent; only top-level groups are listed here.
for group in ("NetBar", "Contracts", "NetBarTests", "Configs"):
    emit(f"\t\t\t\t{oid('group:' + group)},")
emit(f"\t\t\t\t{oid('group:products')},")
emit("\t\t\t);")
emit("\t\t\tsourceTree = \"<group>\";")
emit("\t\t};")
group_body(oid("group:products"), "Products",
           [f"{oid('product:app')} /* {APP}.app */", f"{oid('product:tests')} /* {TESTS}.xctest */"])
group_body(oid("group:NetBar"), "NetBar",
           [f"{oid('group:App')}", f"{oid('group:Bridge')}",
            f"{oid('file:NetBar/NetBar-Bridging-Header.h')} /* NetBar-Bridging-Header.h */"],
           path="NetBar")
group_body(oid("group:App"), "App",
           [f"{oid('file:' + path)} /* {os.path.basename(path)} */" for path, g in SOURCES if g == "App"],
           path="App")
group_body(oid("group:Bridge"), "Bridge",
           [f"{oid('file:' + path)} /* {os.path.basename(path)} */"
            for path, g in SOURCES + HEADERS if g == "Bridge"],
           path="Bridge")
group_body(oid("group:Contracts"), "Contracts",
           [f"{oid('file:' + path)} /* {os.path.basename(path)} */"
            for path, g in SOURCES + HEADERS if g == "Contracts"],
           path="Contracts")
group_body(oid("group:NetBarTests"), "NetBarTests",
           [f"{oid('file:' + path)} /* {os.path.basename(path)} */"
            for path, g in TEST_SOURCES if g == "NetBarTests"]
           + [f"{oid('file:' + path)} /* {os.path.basename(path)} */" for path, _ in RESOURCE_FOLDERS],
           path="NetBarTests")
group_body(oid("group:Configs"), "Configs",
           [f"{oid('file:' + path)} /* {os.path.basename(path)} */" for path in CONFIGS])
emit("/* End PBXGroup section */")

# --- PBXNativeTarget --------------------------------------------------------
emit()
emit("/* Begin PBXNativeTarget section */")
emit(f"\t\t{oid('target:app')} /* {APP} */ = {{")
emit("\t\t\tisa = PBXNativeTarget;")
emit(f"\t\t\tbuildConfigurationList = {oid('configlist:app')};")
emit("\t\t\tbuildPhases = (")
emit(f"\t\t\t\t{oid('phase:rust')} /* Build Rust Engine */,")
emit(f"\t\t\t\t{oid('phase:sources:app')} /* Sources */,")
emit(f"\t\t\t\t{oid('frameworks:app')} /* Frameworks */,")
emit(f"\t\t\t\t{oid('phase:resources')} /* Resources */,")
emit("\t\t\t);")
emit("\t\t\tbuildRules = (")
emit("\t\t\t);")
emit("\t\t\tdependencies = (")
emit("\t\t\t);")
emit(f"\t\t\tname = {APP};")
emit(f"\t\t\tproductName = {APP};")
emit(f"\t\t\tproductReference = {oid('product:app')} /* {APP}.app */;")
emit("\t\t\tproductType = \"com.apple.product-type.application\";")
emit("\t\t};")
emit(f"\t\t{oid('target:tests')} /* {TESTS} */ = {{")
emit("\t\t\tisa = PBXNativeTarget;")
emit(f"\t\t\tbuildConfigurationList = {oid('configlist:tests')};")
emit("\t\t\tbuildPhases = (")
emit(f"\t\t\t\t{oid('phase:sources:tests')} /* Sources */,")
emit(f"\t\t\t\t{oid('frameworks:tests')} /* Frameworks */,")
emit("\t\t\t);")
emit("\t\t\tbuildRules = (")
emit("\t\t\t);")
emit("\t\t\tdependencies = (")
emit(f"\t\t\t\t{oid('dependency:tests')} /* PBXTargetDependency */,")
emit("\t\t\t);")
emit(f"\t\t\tname = {TESTS};")
emit(f"\t\t\tproductName = {TESTS};")
emit(f"\t\t\tproductReference = {oid('product:tests')} /* {TESTS}.xctest */;")
emit("\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";")
emit("\t\t};")
emit("/* End PBXNativeTarget section */")

# --- PBXProject -------------------------------------------------------------
emit()
emit("/* Begin PBXProject section */")
emit(f"\t\t{oid('project')} = {{")
emit("\t\t\tisa = PBXProject;")
emit("\t\t\tattributes = {")
emit("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
emit("\t\t\t\tLastSwiftUpdateCheck = 2700;")
emit("\t\t\t\tLastUpgradeCheck = 2700;")
emit("\t\t\t\tTargetAttributes = {")
emit(f"\t\t\t\t\t{oid('target:app')} = {{")
emit("\t\t\t\t\t\tCreatedOnToolsVersion = 27.0;")
emit("\t\t\t\t\t};")
emit(f"\t\t\t\t\t{oid('target:tests')} = {{")
emit("\t\t\t\t\t\tCreatedOnToolsVersion = 27.0;")
emit(f"\t\t\t\t\t\tTestTargetID = {oid('target:app')};")
emit("\t\t\t\t\t};")
emit("\t\t\t\t};")
emit("\t\t\t};")
emit(f"\t\t\tbuildConfigurationList = {oid('configlist:project')};")
emit("\t\t\tdevelopmentRegion = en;")
emit("\t\t\thasScannedForEncodings = 0;")
emit("\t\t\tknownRegions = (")
emit("\t\t\t\ten,")
emit("\t\t\t\tBase,")
emit("\t\t\t);")
emit(f"\t\t\tmainGroup = {oid('group:root')};")
emit("\t\t\tminimizedProjectReferenceProxies = 1;")
emit("\t\t\tpreferredProjectObjectVersion = 77;")
emit(f"\t\t\tproductRefGroup = {oid('group:products')} /* Products */;")
emit("\t\t\tprojectDirPath = \"\";")
emit("\t\t\tprojectRoot = \"\";")
emit("\t\t\ttargets = (")
emit(f"\t\t\t\t{oid('target:app')} /* {APP} */,")
emit(f"\t\t\t\t{oid('target:tests')} /* {TESTS} */,")
emit("\t\t\t);")
emit("\t\t};")
emit("/* End PBXProject section */")

# --- PBXResourcesBuildPhase -------------------------------------------------
emit()
emit("/* Begin PBXResourcesBuildPhase section */")
emit(f"\t\t{oid('phase:resources')} /* Resources */ = {{")
emit("\t\t\tisa = PBXResourcesBuildPhase;")
emit("\t\t\tbuildActionMask = 2147483647;")
emit("\t\t\tfiles = (")
for path, _ in RESOURCE_FOLDERS:
    emit(f"\t\t\t\t{oid('build:' + path)} /* {os.path.basename(path)} in Resources */,")
emit("\t\t\t);")
emit("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
emit("\t\t};")
emit("/* End PBXResourcesBuildPhase section */")

# --- PBXShellScriptBuildPhase ----------------------------------------------
emit()
emit("/* Begin PBXShellScriptBuildPhase section */")
emit(f"\t\t{oid('phase:rust')} /* Build Rust Engine */ = {{")
emit("\t\t\tisa = PBXShellScriptBuildPhase;")
emit("\t\t\talwaysOutOfDate = 1;")
emit("\t\t\tbuildActionMask = 2147483647;")
emit("\t\t\tfiles = (")
emit("\t\t\t);")
emit("\t\t\tinputPaths = (")
emit("\t\t\t);")
emit("\t\t\tname = \"Build Rust Engine\";")
emit("\t\t\toutputPaths = (")
emit("\t\t\t);")
emit("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
emit("\t\t\tshellPath = /bin/sh;")
emit("\t\t\tshellScript = \"set -euo pipefail\\n\\\"$SRCROOT/Scripts/build-rust.sh\\\"\\n\";")
emit("\t\t};")
emit("/* End PBXShellScriptBuildPhase section */")

# --- PBXSourcesBuildPhase ---------------------------------------------------
emit()
emit("/* Begin PBXSourcesBuildPhase section */")
emit(f"\t\t{oid('phase:sources:app')} /* Sources */ = {{")
emit("\t\t\tisa = PBXSourcesBuildPhase;")
emit("\t\t\tbuildActionMask = 2147483647;")
emit("\t\t\tfiles = (")
for path, _ in SOURCES:
    emit(f"\t\t\t\t{oid('build:' + path)} /* {os.path.basename(path)} in Sources */,")
emit("\t\t\t);")
emit("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
emit("\t\t};")
emit(f"\t\t{oid('phase:sources:tests')} /* Sources */ = {{")
emit("\t\t\tisa = PBXSourcesBuildPhase;")
emit("\t\t\tbuildActionMask = 2147483647;")
emit("\t\t\tfiles = (")
for path, _ in TEST_SOURCES:
    emit(f"\t\t\t\t{oid('build:' + path)} /* {os.path.basename(path)} in Sources */,")
emit("\t\t\t);")
emit("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
emit("\t\t};")
emit("/* End PBXSourcesBuildPhase section */")

# --- PBXTargetDependency ----------------------------------------------------
emit()
emit("/* Begin PBXTargetDependency section */")
emit(f"\t\t{oid('dependency:tests')} = {{")
emit("\t\t\tisa = PBXTargetDependency;")
emit(f"\t\t\ttarget = {oid('target:app')} /* {APP} */;")
emit(f"\t\t\ttargetProxy = {oid('proxy:tests')} /* PBXContainerItemProxy */;")
emit("\t\t};")
emit("/* End PBXTargetDependency section */")

# --- XCBuildConfiguration ---------------------------------------------------
APP_SETTINGS = [
    ("INFOPLIST_FILE", "\"$(SRCROOT)/NetBar/Info.plist\""),
    ("PRODUCT_BUNDLE_IDENTIFIER", "dev.netbar.app"),
    ("PRODUCT_NAME", "\"$(TARGET_NAME)\""),
    ("SWIFT_OBJC_BRIDGING_HEADER", "\"$(SRCROOT)/NetBar/NetBar-Bridging-Header.h\""),
    ("HEADER_SEARCH_PATHS", "(\"$(SRCROOT)/NetBar/Bridge\", \"$(SRCROOT)/Contracts\")"),
    ("LIBRARY_SEARCH_PATHS", "(\"$(NETBAR_ENGINE_LIB_DIR)\")"),
    ("OTHER_LDFLAGS", "(\"-lnetbar_engine\", \"-lc++\", \"-lresolv\", \"-framework\", \"AppKit\", \"-framework\", \"CoreLocation\", \"-framework\", \"CoreWLAN\", \"-framework\", \"Foundation\", \"-framework\", \"Security\")"),
    ("ENABLE_APP_SANDBOX", "NO"),
    # Xcode resolves a concrete destination for the host machine and would
    # otherwise build a single slice; the release must carry both.
    ("ARCHS", "\"arm64 x86_64\""),
    ("ENABLE_HARDENED_RUNTIME", "YES"),
    ("SWIFT_EMIT_LOC_STRINGS", "NO"),
    ("COMBINE_HIDPI_IMAGES", "YES"),
]
TEST_SETTINGS = [
    ("GENERATE_INFOPLIST_FILE", "YES"),
    ("PRODUCT_BUNDLE_IDENTIFIER", "dev.netbar.app.tests"),
    ("PRODUCT_NAME", "\"$(TARGET_NAME)\""),
    ("BUNDLE_LOADER", "\"$(TEST_HOST)\""),
    ("TEST_HOST", "\"$(BUILT_PRODUCTS_DIR)/NetBar.app/Contents/MacOS/NetBar\""),
    ("SWIFT_VERSION", "5.0"),
    ("ENABLE_HARDENED_RUNTIME", "YES"),
    ("ARCHS", "\"arm64 x86_64\""),
]
PROJECT_SETTINGS = [
    ("MARKETING_VERSION", "1.0.0"),
    ("CURRENT_PROJECT_VERSION", "1"),
    ("CLANG_ENABLE_MODULES", "YES"),
    ("CLANG_ENABLE_OBJC_ARC", "YES"),
    ("SWIFT_VERSION", "5.0"),
    ("GCC_WARN_UNDECLARED_SELECTOR", "YES"),
    ("CLANG_ANALYZER_NONNULL", "YES"),
    ("ENABLE_STRICT_OBJC_MSGSEND", "YES"),
    ("SWIFT_STRICT_CONCURRENCY", "minimal"),
    ("SWIFT_TREAT_WARNINGS_AS_ERRORS", "NO"),
    ("GCC_TREAT_WARNINGS_AS_ERRORS", "NO"),
]

# Per-configuration overrides applied on top of the lists above. Debug builds
# only the host slice; Release ships both.
CONFIG_OVERRIDES = {
    ("app", "Debug"): [("ONLY_ACTIVE_ARCH", "YES")],
    ("app", "Release"): [("ONLY_ACTIVE_ARCH", "NO")],
    ("tests", "Debug"): [("ONLY_ACTIVE_ARCH", "YES")],
    ("tests", "Release"): [("ONLY_ACTIVE_ARCH", "NO")],
}

def settings_block(settings: list[tuple[str, str]]) -> None:
    for key, value in settings:
        emit(f"\t\t\t\t{key} = {value};")

emit()
emit("/* Begin XCBuildConfiguration section */")
configs = [
    ("project", "Debug", "Configs/Debug.xcconfig", PROJECT_SETTINGS),
    ("project", "Release", "Configs/Release.xcconfig", PROJECT_SETTINGS),
    ("app", "Debug", "Configs/Debug.xcconfig", APP_SETTINGS),
    ("app", "Release", "Configs/Release.xcconfig", APP_SETTINGS),
    ("tests", "Debug", "Configs/Debug.xcconfig", TEST_SETTINGS),
    ("tests", "Release", "Configs/Release.xcconfig", TEST_SETTINGS),
]
for role, name, xcconfig, settings in configs:
    settings = settings + CONFIG_OVERRIDES.get((role, name), [])
    emit(f"\t\t{oid('config:' + role + ':' + name)} /* {name} */ = {{")
    emit("\t\t\tisa = XCBuildConfiguration;")
    emit(f"\t\t\tbaseConfigurationReference = {oid('file:' + xcconfig)} /* {os.path.basename(xcconfig)} */;")
    emit("\t\t\tbuildSettings = {")
    settings_block(settings)
    emit("\t\t\t};")
    emit(f"\t\t\tname = {name};")
    emit("\t\t};")
emit("/* End XCBuildConfiguration section */")

# --- XCConfigurationList ----------------------------------------------------
emit()
emit("/* Begin XCConfigurationList section */")
for role, label in (("project", f"PBXProject \"{APP}\""), ("app", f"PBXNativeTarget \"{APP}\""),
                    ("tests", f"PBXNativeTarget \"{TESTS}\"")):
    emit(f"\t\t{oid('configlist:' + role)} /* Build configuration list for {label} */ = {{")
    emit("\t\t\tisa = XCConfigurationList;")
    emit("\t\t\tbuildConfigurations = (")
    for name in ("Debug", "Release"):
        emit(f"\t\t\t\t{oid('config:' + role + ':' + name)} /* {name} */,")
    emit("\t\t\t);")
    emit("\t\t\tdefaultConfigurationIsVisible = 0;")
    emit("\t\t\tdefaultConfigurationName = Release;")
    emit("\t\t};")
emit("/* End XCConfigurationList section */")

emit("\t};")
emit(f"\trootObject = {oid('project')};")
emit("}")

PROJECT.parent.mkdir(parents=True, exist_ok=True)
PROJECT.write_text("\n".join(lines) + "\n")
print(f"wrote {PROJECT} ({len(lines)} lines)")
