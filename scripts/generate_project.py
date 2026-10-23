#!/usr/bin/env python3
"""Generate the checked-in Xcode project using only Python's standard library."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]

def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def quote(value):
    return json.dumps(str(value), ensure_ascii=False)

objects = []

def add(name, content):
    objects.append(f'\t\t{uid(name)} = {{ {content} }};')
    return uid(name)

def refs(values):
    return '(' + ', '.join(values) + ',)'

app_files = sorted((ROOT / 'Sources/App').glob('*.swift')) + sorted((ROOT / 'Sources/Shared').glob('*.swift'))
test_files = sorted((ROOT / 'Tests/UI').glob('*.swift'))
app_refs, app_builds, test_refs, test_builds = [], [], [], []
for files, file_refs, builds in [(app_files, app_refs, app_builds), (test_files, test_refs, test_builds)]:
    for file in files:
        path = file.relative_to(ROOT).as_posix()
        file_ref = add(path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(path)}; sourceTree = SOURCE_ROOT;')
        file_refs.append(file_ref)
        builds.append(add('build:' + path, f'isa = PBXBuildFile; fileRef = {file_ref};'))

widget_refs, widget_builds = [], []
for file in sorted((ROOT / 'Sources/Widget').glob('*.swift')) + sorted((ROOT / 'Sources/Shared').glob('*.swift')):
    path = file.relative_to(ROOT).as_posix()
    ref = add('widget:' + path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(path)}; sourceTree = SOURCE_ROOT;')
    widget_refs.append(ref)
    widget_builds.append(add('widgetbuild:' + path, f'isa = PBXBuildFile; fileRef = {ref};'))
widget_product = add('widgetproduct', 'isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; path = YIClassWidget.appex; sourceTree = BUILT_PRODUCTS_DIR;')
widget_group = add('widgetgroup', f'isa = PBXGroup; children = {refs(widget_refs)}; name = Widget; sourceTree = "<group>";')
assets = add('assets', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Sources/App/Assets.xcassets; sourceTree = SOURCE_ROOT;')
privacy = add('privacy', 'isa = PBXFileReference; lastKnownFileType = text.xml; path = Sources/App/PrivacyInfo.xcprivacy; sourceTree = SOURCE_ROOT;')
resource_builds = [add('build:assets', f'isa = PBXBuildFile; fileRef = {assets};'), add('build:privacy', f'isa = PBXBuildFile; fileRef = {privacy};')]
product = add('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = YIClass.app; sourceTree = BUILT_PRODUCTS_DIR;')
test_product = add('testproduct', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = YIClassUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
products = add('products', f'isa = PBXGroup; children = {refs([product, test_product, widget_product])}; name = Products; sourceTree = "<group>";')
app_group = add('appgroup', f'isa = PBXGroup; children = {refs(app_refs + [assets, privacy])}; name = App; sourceTree = "<group>";')
test_group = add('testgroup', f'isa = PBXGroup; children = {refs(test_refs)}; name = UITests; sourceTree = "<group>";')
root_group = add('rootgroup', f'isa = PBXGroup; children = {refs([app_group, widget_group, test_group, products])}; sourceTree = "<group>";')

package = add('package', 'isa = XCLocalSwiftPackageReference; relativePath = .;')
core_product = add('coreproduct', f'isa = XCSwiftPackageProductDependency; package = {package}; productName = YIClassCore;')
core_build = add('corebuild', f'isa = PBXBuildFile; productRef = {core_product};')

sources = add('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(app_builds)}; runOnlyForDeploymentPostprocessing = 0;')
resources = add('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {refs(resource_builds)}; runOnlyForDeploymentPostprocessing = 0;')
frameworks = add('frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {refs([core_build])}; runOnlyForDeploymentPostprocessing = 0;')
test_sources = add('testsources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(test_builds)}; runOnlyForDeploymentPostprocessing = 0;')
pdf_fixture = add('pdffixture', 'isa = PBXFileReference; lastKnownFileType = image.pdf; path = Tests/Fixtures/timetable-grid.pdf; sourceTree = SOURCE_ROOT;')
pdf_fixture_build = add('pdffixturebuild', f'isa = PBXBuildFile; fileRef = {pdf_fixture};')
test_resources = add('testresources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {refs([pdf_fixture_build])}; runOnlyForDeploymentPostprocessing = 0;')
test_frameworks = add('testframeworks' , 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')

widget_core_product = add('widgetcoreproduct', f'isa = XCSwiftPackageProductDependency; package = {package}; productName = YIClassCore;')
widget_core_build = add('widgetcorebuild', f'isa = PBXBuildFile; productRef = {widget_core_product};')
widget_sources = add('widgetsources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(widget_builds)}; runOnlyForDeploymentPostprocessing = 0;')
widget_frameworks = add('widgetframeworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {refs([widget_core_build])}; runOnlyForDeploymentPostprocessing = 0;')
embed_build = add('embedwidgetbuild', f'isa = PBXBuildFile; fileRef = {widget_product}; settings = {{ ATTRIBUTES = (RemoveHeadersOnCopy,); }};')
embed_phase = add('embedwidgets', f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = {refs([embed_build])}; name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0;')
widget_proxy = add('widgetproxy', f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("widgettarget")}; remoteInfo = YIClassWidget;')
widget_dependency = add('widgetdependency', f'isa = PBXTargetDependency; target = {uid("widgettarget")}; targetProxy = {widget_proxy};')

project_settings = {
    'CLANG_ENABLE_MODULES': 'YES', 'SDKROOT': 'iphoneos', 'IPHONEOS_DEPLOYMENT_TARGET': '26.0',
    'SWIFT_VERSION': '6.0', 'SWIFT_STRICT_CONCURRENCY': 'complete', 'ENABLE_USER_SCRIPT_SANDBOXING': 'YES',
}
app_settings = {
    'PRODUCT_BUNDLE_IDENTIFIER': 'com.ddyec.YIClassNative', 'PRODUCT_NAME': 'YIClass',
    'GENERATE_INFOPLIST_FILE': 'YES', 'INFOPLIST_KEY_CFBundleDisplayName': 'YIClass',
    'INFOPLIST_FILE': 'Sources/App/Info.plist',
    'INFOPLIST_KEY_LSRequiresIPhoneOS': 'YES',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation': 'YES',
    'INFOPLIST_KEY_UISupportedInterfaceOrientations': 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
    'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad': 'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
    'TARGETED_DEVICE_FAMILY': '1,2', 'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator',
    'SUPPORTS_MACCATALYST': 'NO', 'SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD': 'NO',
    'CODE_SIGN_STYLE': 'Automatic', 'MARKETING_VERSION': '3.2.3', 'CURRENT_PROJECT_VERSION': '24',
    'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIconSlate', 'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME': 'AccentColor',
    'SWIFT_EMIT_LOC_STRINGS': 'YES', 'CODE_SIGN_ENTITLEMENTS': 'Sources/App/YIClass.entitlements',
}
test_settings = {
    'PRODUCT_BUNDLE_IDENTIFIER': 'com.ddyec.YIClassNative.UITests', 'PRODUCT_NAME': 'YIClassUITests',
    'GENERATE_INFOPLIST_FILE': 'YES', 'TARGETED_DEVICE_FAMILY': '1,2', 'TEST_TARGET_NAME': 'YIClass',
    'CODE_SIGN_STYLE': 'Automatic',
}

widget_settings = {
    'PRODUCT_BUNDLE_IDENTIFIER': 'com.ddyec.YIClassNative.Widget', 'PRODUCT_NAME': 'YIClassWidget',
    'GENERATE_INFOPLIST_FILE': 'YES', 'INFOPLIST_FILE': 'Sources/Widget/Info.plist',
    'INFOPLIST_KEY_CFBundleDisplayName': '课程安排', 'SKIP_INSTALL': 'YES',
    'APPLICATION_EXTENSION_API_ONLY': 'YES', 'TARGETED_DEVICE_FAMILY': '1,2',
    'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator', 'SUPPORTS_MACCATALYST': 'NO',
    'CODE_SIGN_STYLE': 'Automatic', 'CODE_SIGN_ENTITLEMENTS': 'Sources/Widget/YIClass.entitlements',
    'MARKETING_VERSION': '3.2.3', 'CURRENT_PROJECT_VERSION': '24',
    'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks',
}

def configuration_list(name, settings):
    configurations = []
    for mode in ['Debug', 'Release']:
        values = dict(settings)
        values['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone' if mode == 'Debug' else '-O'
        values['DEBUG_INFORMATION_FORMAT'] = 'dwarf' if mode == 'Debug' else 'dwarf-with-dsym'
        values['ONLY_ACTIVE_ARCH'] = 'YES' if mode == 'Debug' else 'NO'
        if mode == 'Debug': values['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG $(inherited)'
        body = ' '.join(f'{k} = {quote(v)};' for k, v in values.items())
        configurations.append(add(name + mode, f'isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {mode};'))
    return add(name + 'configlist', f'isa = XCConfigurationList; buildConfigurations = {refs(configurations)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')

project_configs = configuration_list('project', project_settings)
app_configs = configuration_list('app', app_settings)
test_configs = configuration_list('test', test_settings)
widget_configs = configuration_list('widget', widget_settings)
widget_target = add('widgettarget', f'isa = PBXNativeTarget; buildConfigurationList = {widget_configs}; buildPhases = {refs([widget_sources, widget_frameworks])}; buildRules = (); dependencies = (); name = YIClassWidget; packageProductDependencies = {refs([widget_core_product])}; productName = YIClassWidget; productReference = {widget_product}; productType = "com.apple.product-type.app-extension";')
app_target = add('apptarget' , f'isa = PBXNativeTarget; buildConfigurationList = {app_configs}; buildPhases = {refs([sources, frameworks, resources, embed_phase])}; buildRules = (); dependencies = {refs([widget_dependency])}; name = YIClass; packageProductDependencies = {refs([core_product])}; productName = YIClass; productReference = {product}; productType = "com.apple.product-type.application";')
proxy = add('testproxy', f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {app_target}; remoteInfo = YIClass;')
dependency = add('testdependency', f'isa = PBXTargetDependency; target = {app_target}; targetProxy = {proxy};')
test_target = add('testtarget', f'isa = PBXNativeTarget; buildConfigurationList = {test_configs}; buildPhases = {refs([test_sources, test_frameworks, test_resources])}; buildRules = (); dependencies = {refs([dependency])}; name = YIClassUITests; productName = YIClassUITests; productReference = {test_product}; productType = "com.apple.product-type.bundle.ui-testing";')
add('project', f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600; TargetAttributes = {{ {test_target} = {{ TestTargetID = {app_target}; }}; }}; }}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh-Hans; hasScannedForEncodings = 0; knownRegions = ("zh-Hans", en, Base); mainGroup = {root_group}; packageReferences = {refs([package])}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {refs([app_target, widget_target, test_target])};')
project_dir = ROOT / 'YIClass.xcodeproj'
project_dir.mkdir(exist_ok=True)
(project_dir / 'project.pbxproj').write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 60;\n\tobjects = {\n' + '\n'.join(objects) + f'\n\t}};\n\trootObject = {uid("project")};\n}}\n')

scheme_dir = project_dir / 'xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)

def reference(target, buildable, name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{buildable}" BlueprintName="{name}" ReferencedContainer="container:YIClass.xcodeproj"/>'

app_ref = reference(app_target, 'YIClass.app', 'YIClass')
test_ref = reference(test_target, 'YIClassUITests.xctest', 'YIClassUITests')
(scheme_dir / 'YIClass.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><PreActions><ExecutionAction ActionType="Xcode.IDEStandardExecutionActionsCore.ExecutionActionType.ShellScriptAction"><ActionContent title="Prepare app and notification icons" scriptText="python3 &quot;$SRCROOT/scripts/prepare-icons.py&quot;" shellToInvoke="/bin/bash"><EnvironmentBuildable>{app_ref}</EnvironmentBuildable></ActionContent></ExecutionAction></PreActions><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>
    <TestableReference skipped="NO">{test_ref}</TestableReference>
  </Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugServiceExtension="internal"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print('Generated YIClass.xcodeproj and shared scheme')
