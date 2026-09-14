#!/usr/bin/env python3
"""Generate the checked-in, dependency-free Xcode project deterministically."""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parent
objects = {}
def ident(value):
    return hashlib.sha256(value.encode()).hexdigest()[:24].upper()
def add(name, text):
    key = ident(name); objects[key] = text; return key
def array(items):
    return '(' + ', '.join(items) + ')'
def config(name, settings):
    return add(name, 'isa = XCBuildConfiguration; name = '+name.split(':')[-1]+'; buildSettings = {'+settings+'};')
def configs(name, settings):
    ids = [config(name+':'+mode,settings+(' DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; ENABLE_TESTABILITY = YES;' if mode=='Debug' else ' SWIFT_OPTIMIZATION_LEVEL = "-O";')) for mode in ['Debug','Release']]
    return add(name+':configs','isa = XCConfigurationList; buildConfigurations = '+array(ids)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')

target_names = ['Orbit','OrbitTests','OrbitUITests']
target_ids = {name:ident('target:'+name) for name in target_names}
products = []; groups = []
for name in target_names:
    files = []; builds = []
    for path in sorted((root/name).glob('*.swift')):
        file = add('file:'+str(path.relative_to(root)),f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path.name}"; sourceTree = "<group>";')
        files.append(file)
        builds.append(add('build:'+str(path.relative_to(root)),f'isa = PBXBuildFile; fileRef = {file};'))
    resources = []
    if name == 'Orbit':
        assets = add('assets','isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>";')
        files.append(assets); resources.append(add('assets-build',f'isa = PBXBuildFile; fileRef = {assets};'))
    groups.append(add('group:'+name,f'isa = PBXGroup; children = {array(files)}; path = {name}; sourceTree = "<group>";'))
    source_phase = add('sources:'+name,f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(builds)}; runOnlyForDeploymentPostprocessing = 0;')
    resource_phase = add('resources:'+name,f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {array(resources)}; runOnlyForDeploymentPostprocessing = 0;')
    frameworks = add('frameworks:'+name,'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    extension = 'app' if name=='Orbit' else 'xctest'
    file_type = 'wrapper.application' if name=='Orbit' else 'wrapper.cfbundle'
    product = add('product:'+name,f'isa = PBXFileReference; explicitFileType = {file_type}; includeInIndex = 0; path = {name}.{extension}; sourceTree = BUILT_PRODUCTS_DIR;')
    products.append(product)
    settings = f'PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = com.digitaldropkick.{name.lower()}; SWIFT_VERSION = 5.0; IPHONEOS_DEPLOYMENT_TARGET = 18.0; TARGETED_DEVICE_FAMILY = 1; CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; SDKROOT = iphoneos; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";'
    if name=='Orbit': settings += ' INFOPLIST_FILE = Orbit/Info.plist; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; ENABLE_PREVIEWS = YES;'
    else: settings += ' GENERATE_INFOPLIST_FILE = YES;'
    if name=='OrbitTests': settings += ' TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Orbit.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Orbit"; BUNDLE_LOADER = "$(TEST_HOST)";'
    if name=='OrbitUITests': settings += ' TEST_TARGET_NAME = Orbit;'
    dep = []
    if name!='Orbit':
        proxy = add('proxy:'+name,f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {target_ids["Orbit"]}; remoteInfo = Orbit;')
        dep.append(add('dependency:'+name,f'isa = PBXTargetDependency; target = {target_ids["Orbit"]}; targetProxy = {proxy};'))
    kind = 'application' if name=='Orbit' else 'bundle.unit-test' if name=='OrbitTests' else 'bundle.ui-testing'
    add('target:'+name,f'isa = PBXNativeTarget; buildConfigurationList = {configs(name,settings)}; buildPhases = {array([source_phase,frameworks,resource_phase])}; buildRules = (); dependencies = {array(dep)}; name = {name}; productName = {name}; productReference = {product}; productType = "com.apple.product-type.{kind}";')
product_group=add('products',f'isa = PBXGroup; children = {array(products)}; name = Products; sourceTree = "<group>";')
main_group=add('main',f'isa = PBXGroup; children = {array(groups+[product_group])}; sourceTree = "<group>";')
project_config=configs('Project','CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; SWIFT_VERSION = 5.0;')
add('project',f'isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600;}}; buildConfigurationList = {project_config}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {main_group}; productRefGroup = {product_group}; projectDirPath = ""; projectRoot = ""; targets = {array(list(target_ids.values()))};')
project=root/'Orbit.xcodeproj'; project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+''.join(key+' = {'+value+'};\n' for key,value in objects.items())+'}; rootObject = '+ident('project')+';}\n')
schemes=project/'xcshareddata/xcschemes'; schemes.mkdir(parents=True,exist_ok=True)
def reference(name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_ids[name]}" BuildableName="{name}.{"app" if name=="Orbit" else "xctest"}" BlueprintName="{name}" ReferencedContainer="container:Orbit.xcodeproj"/>'
(schemes/'Orbit.xcscheme').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<Scheme LastUpgradeVersion="2600" version="1.7"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>'+''.join('<BuildActionEntry buildForTesting="YES" buildForRunning="'+('YES' if name=='Orbit' else 'NO')+'" buildForProfiling="NO" buildForArchiving="'+('YES' if name=='Orbit' else 'NO')+'" buildForAnalyzing="YES">'+reference(name)+'</BuildActionEntry>' for name in target_names)+'</BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables>'+''.join('<TestableReference skipped="NO">'+reference(name)+'</TestableReference>' for name in target_names[1:])+'</Testables></TestAction><LaunchAction buildConfiguration="Debug" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">'+reference('Orbit')+'</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">'+reference('Orbit')+'</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>\n')
print('Orbit Xcode project generated.')
