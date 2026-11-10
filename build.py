"""Build only this standalone preview on a Mac with Xcode. No npm dependencies."""
import hashlib,json,plistlib,subprocess,sys,zipfile
from pathlib import Path

root=Path(__file__).resolve().parent
if sys.platform!='darwin':
    raise SystemExit('This iPhone build requires macOS with Xcode. Run the supplied Codemagic workflow.')
def output(*args):return subprocess.check_output(args,text=True).strip()
sdk=output('xcrun','--sdk','iphoneos','--show-sdk-path')
compiler=output('xcrun','--sdk','iphoneos','--find','clang')
destination=root/'build';app=destination/'Payload'/'WeatherPreview.app'
if destination.exists():raise SystemExit('Build folder already exists; use a clean checkout to preserve existing output.')
app.mkdir(parents=True)
info={'CFBundleIdentifier':'com.calibratedgolf.weatherpreview','CFBundleName':'WeatherPreview','CFBundleDisplayName':'CG Weather Preview','CFBundleExecutable':'WeatherPreview','CFBundlePackageType':'APPL','CFBundleInfoDictionaryVersion':'6.0','CFBundleSupportedPlatforms':['iPhoneOS'],'CFBundleDevelopmentRegion':'en','CFBundleVersion':'2','CFBundleShortVersionString':'0.1.1','MinimumOSVersion':'27.2','LSRequiresIPhoneOS':True,'UIDeviceFamily':[1],'UILaunchScreen':{},'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait'],'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False,'UISceneConfigurations':{'UIWindowSceneSessionRoleApplication':[{'UISceneConfigurationName':'Preview','UISceneDelegateClassName':'PreviewSceneDelegate'}]}}}
(app/'Info.plist').write_bytes(plistlib.dumps(info))
command=[compiler,'-arch','arm64','-isysroot',sdk,'-miphoneos-version-min=27.2','-fobjc-arc','-fmodules','-O1','-Wall','-Wextra','-Wno-unused-parameter','-framework','UIKit','-framework','Foundation','-framework','QuartzCore','-framework','Metal',str(root/'Preview.m'),'-o',str(app/'WeatherPreview')]
with (destination/'build.log').open('w',encoding='utf-8') as log:
    host_sdk=output('xcrun','--sdk','macosx','--show-sdk-path')
    host_compiler=output('xcrun','--sdk','macosx','--find','clang')
    regression=destination/'OwnershipRegression'
    host_command=[host_compiler,'-isysroot',host_sdk,'-fobjc-arc','-O1','-Wall','-Wextra','-Wno-unused-parameter','-framework','Foundation',str(root/'OwnershipRegression.m'),'-o',str(regression)]
    subprocess.run(host_command,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run([str(regression)],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=30)
    result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
if result.returncode:
    print((destination/'build.log').read_text());raise SystemExit(result.returncode)
ipa=destination/'Apple-Weather-Native-Preview-2-UNSIGNED.ipa'
with zipfile.ZipFile(ipa,'w',compression=zipfile.ZIP_DEFLATED) as archive:
    for item in sorted((destination/'Payload').rglob('*')):
        if item.is_file():archive.write(item,item.relative_to(destination).as_posix())
proof={'previewBuild':2,'bundleIdentifier':info['CFBundleIdentifier'],'sdk':output('xcrun','--sdk','iphoneos','--show-sdk-version'),'sourceSHA256':hashlib.sha256((root/'Preview.m').read_bytes()).hexdigest(),'signed':False,'ownershipRegressionPassed':True,'nativePlaybackVerified':False,'exactWeatherPresetsConnected':False}
(destination/'build-proof.json').write_text(json.dumps(proof,indent=2))
print('Created standalone unsigned preview:',ipa)
