#!/usr/bin/env python3
"""Generate a small dependency-free Xcode project; source files remain ordinary Swift."""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parent.parent
objects = {}
def ident(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def add(name, body):
    key = ident(name)
    objects[key] = body
    return key
def array(items):
    return '(' + ', '.join(items) + ')'
def quoted(value):
    return '"' + value.replace('"', '\\"') + '"'

core = sorted(root.glob('Sources/PepereteCore/*.swift'))
app = sorted(root.glob('Sources/PepereteApp/*.swift'))
widget = sorted(root.glob('Sources/PepereteWidget/*.swift'))
refs = {}
for file in core + app + widget:
    relative = str(file.relative_to(root))
    refs[file] = add(relative, '{ isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ' + quoted(relative) + '; sourceTree = "<group>"; }')

products = []
targets = []
configs = []
project_settings = 'MACOSX_DEPLOYMENT_TARGET = 14.0; SDKROOT = macosx; SWIFT_VERSION = 6.0; CODE_SIGN_IDENTITY = "-"; CODE_SIGN_STYLE = Manual; ENABLE_APP_SANDBOX = NO; ALWAYS_SEARCH_USER_PATHS = NO; SWIFT_STRICT_CONCURRENCY = complete;'
for conf in ['Debug', 'Release']:
    cfg = add('project-' + conf, '{ isa = XCBuildConfiguration; name = ' + conf + '; buildSettings = { ' + project_settings + ' }; }')
    configs.append(cfg)
project_config = add('project-config', '{ isa = XCConfigurationList; buildConfigurations = ' + array(configs) + '; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }')

for name, files, ext, product_type, info in [
    ('PepereteWidget', core + widget, 'appex', 'com.apple.product-type.app-extension', 'Widget'),
    ('Peperete', core + app, 'app', 'com.apple.product-type.application', 'App')
]:
    product = add(name + '-product', '{ isa = PBXFileReference; explicitFileType = ' + ('"wrapper.app-extension"' if ext == 'appex' else 'wrapper.application') + '; path = ' + name + '.' + ext + '; sourceTree = BUILT_PRODUCTS_DIR; }')
    products.append(product)
    builds = []
    for file in files:
        builds.append(add(name + '-' + str(file.relative_to(root)), '{ isa = PBXBuildFile; fileRef = ' + refs[file] + '; }'))
    source_phase = add(name + '-sources', '{ isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ' + array(builds) + '; runOnlyForDeploymentPostprocessing = 0; }')
    frameworks = add(name + '-frameworks', '{ isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }')
    phases = [source_phase, frameworks]
    dependencies = []
    if name == 'Peperete':
        embedded = add('embed-widget-file', '{ isa = PBXBuildFile; fileRef = ' + ident('PepereteWidget-product') + '; settings = { ATTRIBUTES = (RemoveHeadersOnCopy); }; }')
        phases.append(add('embed-widget', '{ isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = (' + embedded + '); name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0; }'))
        proxy = add('widget-proxy', '{ isa = PBXContainerItemProxy; containerPortal = ' + ident('project') + '; proxyType = 1; remoteGlobalIDString = ' + ident('PepereteWidget-target') + '; remoteInfo = PepereteWidget; }')
        dependencies.append(add('widget-dependency', '{ isa = PBXTargetDependency; target = ' + ident('PepereteWidget-target') + '; targetProxy = ' + proxy + '; }'))
    target_configs = []
    for conf in ['Debug', 'Release']:
        settings = f'PRODUCT_NAME = {name}; PRODUCT_BUNDLE_IDENTIFIER = local.peperete' + ('.widget' if ext == 'appex' else '') + f'; INFOPLIST_FILE = Config/{info}-Info.plist; GENERATE_INFOPLIST_FILE = NO; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks @executable_path/../../../../Frameworks";'
        if ext == 'appex': settings += ' APPLICATION_EXTENSION_API_ONLY = YES; SKIP_INSTALL = YES; ENABLE_APP_SANDBOX = YES; CODE_SIGN_ENTITLEMENTS = Config/Widget.entitlements; SWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) PEPERETE_WIDGET";'
        settings += ' SWIFT_OPTIMIZATION_LEVEL = ' + ('"-Onone"' if conf == 'Debug' else '"-O"') + ';'
        target_configs.append(add(name + '-' + conf, '{ isa = XCBuildConfiguration; name = ' + conf + '; buildSettings = { ' + settings + ' }; }'))
    config_list = add(name + '-config', '{ isa = XCConfigurationList; buildConfigurations = ' + array(target_configs) + '; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }')
    targets.append(add(name + '-target', '{ isa = PBXNativeTarget; buildConfigurationList = ' + config_list + '; buildPhases = ' + array(phases) + '; buildRules = (); dependencies = ' + array(dependencies) + '; name = ' + name + '; productName = ' + name + '; productReference = ' + product + '; productType = ' + quoted(product_type) + '; }'))

product_group = add('products', '{ isa = PBXGroup; children = ' + array(products) + '; name = Products; sourceTree = "<group>"; }')
main_group = add('main-group', '{ isa = PBXGroup; children = ' + array(list(refs.values()) + [product_group]) + '; sourceTree = "<group>"; }')
project = add('project', '{ isa = PBXProject; attributes = { LastUpgradeCheck = 2700; }; buildConfigurationList = ' + project_config + '; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = ' + main_group + '; productRefGroup = ' + product_group + '; projectDirPath = ""; projectRoot = ""; targets = ' + array(targets) + '; }')
folder = root / 'Peperete.xcodeproj'
folder.mkdir(exist_ok=True)
(folder / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(f'{key} = {value};' for key, value in objects.items()) + '\n}; rootObject = ' + project + '; }\n')
schemes = folder / 'xcshareddata/xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
(schemes / 'Peperete.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident('Peperete-target')}" BuildableName="Peperete.app" BlueprintName="Peperete" ReferencedContainer="container:Peperete.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident('Peperete-target')}" BuildableName="Peperete.app" BlueprintName="Peperete" ReferencedContainer="container:Peperete.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(folder)
