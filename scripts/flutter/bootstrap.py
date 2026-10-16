"""Generate pinned Flutter native scaffolds and install our reviewed platform overlays."""
from pathlib import Path
import subprocess, tempfile, shutil, plistlib
root=Path(__file__).resolve().parents[2]
u=root/'universal'
with tempfile.TemporaryDirectory() as tmp:
    scaffold=Path(tmp)/'business_tracker'
    subprocess.run(['flutter','create','--platforms=android,ios','--android-language=java','--org=au.monster.tracker','--project-name=business_tracker',str(scaffold)],check=True)
    for platform in ['android','ios']:
        for src in (scaffold/platform).rglob('*'):
            target=u/platform/src.relative_to(scaffold/platform)
            if src.is_dir():target.mkdir(parents=True,exist_ok=True)
            elif not target.exists():shutil.copy2(src,target)
# Copy the original tested Java backup exporter, not its activities or payment SDK.
classes=['Ledger','Json','Backup','Receipts','Purchases','BusinessBackup','Catalog','CatalogBackup','Finance','FinanceBackup','Refunds','Store','BusinessStore','CatalogStore','FinanceStore','RefundStore','PhotoFiles','PaymentSettings']
java=u/'android/app/src/main/java/au/monster/tracker'
for name in classes:
    source=(root/f'app/src/main/java/au/monster/tracker/{name}.java').read_text()
    source=source.replace('PaymentCheckJob.schedule(helper.context);','')
    (java/f'{name}.java').write_text(source)
assets=u/'android/app/src/main/assets';assets.mkdir(parents=True,exist_ok=True)
for p in (root/'app/src/main/assets').glob('*.sql'):shutil.copy2(p,assets/p.name)
# Flutter's generated launcher has a different Java package; use our migration-aware one.
shutil.rmtree(u/'android/app/src/main/java/au/monster/tracker/business_tracker',ignore_errors=True)
gradle=u/'android/app/build.gradle.kts'
s=gradle.read_text().replace('namespace = "au.monster.tracker.business_tracker"','namespace = "au.monster.tracker"').replace('applicationId = "au.monster.tracker.business_tracker"','applicationId = "au.monster.tracker.plus"').replace('minSdk = flutter.minSdkVersion','minSdk = 26')
signing='''val playUploadPath = System.getenv("PLAY_UPLOAD_KEYSTORE_PATH")
val debugKeystorePath = System.getenv("MONSTER_DEBUG_KEYSTORE")
val activeSigningConfig = if (!playUploadPath.isNullOrBlank()) "playUpload" else "compatible"
signingConfigs {
    if (!debugKeystorePath.isNullOrBlank()) {
        create("compatible") {
            storeFile = file(debugKeystorePath)
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }
    if (!playUploadPath.isNullOrBlank()) {
        create("playUpload") {
            storeFile = file(playUploadPath)
            storePassword = System.getenv("PLAY_UPLOAD_STORE_PASSWORD") ?: error("Play upload store password required")
            keyAlias = System.getenv("PLAY_UPLOAD_KEY_ALIAS") ?: error("Play upload key alias required")
            keyPassword = System.getenv("PLAY_UPLOAD_KEY_PASSWORD") ?: error("Play upload key password required")
        }
    }
}
if (activeSigningConfig == "compatible" && debugKeystorePath.isNullOrBlank()) {
    error("Provide the existing compatible signing key or the protected Play upload key")
}
'''
s=s.replace('buildTypes {',signing+'buildTypes {',1)
s=s.replace('signingConfig = signingConfigs.getByName("debug")','signingConfig = signingConfigs.getByName(activeSigningConfig)')
s=s.replace('buildTypes {\n','buildTypes {\n        getByName("debug") { signingConfig = signingConfigs.getByName(activeSigningConfig) }\n',1)
s=s.replace('sourceCompatibility = JavaVersion.VERSION_11','sourceCompatibility = JavaVersion.VERSION_17').replace('targetCompatibility = JavaVersion.VERSION_11','targetCompatibility = JavaVersion.VERSION_17').replace('jvmTarget = JavaVersion.VERSION_11.toString()','jvmTarget = JavaVersion.VERSION_17.toString()')
import re
s=re.sub(r'(release|getByName\("release"\))\s*\{',r'\1 {\n            isMinifyEnabled = false\n            isShrinkResources = false',s)
s+='\ndependencies { implementation("com.google.android.gms:play-services-auth:21.5.0") }\n'
gradle.write_text(s)
info=u/'ios/Runner/Info.plist'
with info.open('rb') as f:p=plistlib.load(f)
p.update(CFBundleDisplayName='Business Tracker',NSCameraUsageDescription='Take product and receipt photos or scan product barcodes.',NSPhotoLibraryUsageDescription='Choose product and receipt photos.',NSPhotoLibraryAddUsageDescription='Save exported receipt photos.',UIBackgroundModes=['fetch','processing'],BGTaskSchedulerPermittedIdentifiers=['au.monster.tracker.plus.sync','au.monster.tracker.plus.backup'])
# Public OAuth client IDs only; never a client secret. Empty builds keep setup disabled.
import os
client=os.environ.get('GOOGLE_IOS_CLIENT_ID','')
if client:
    p['GIDClientID']=client
    p['CFBundleURLTypes']=[{'CFBundleURLSchemes':['.'.join(reversed(client.split('.')))]}]
with info.open('wb') as f:plistlib.dump(p,f)
pbx=u/'ios/Runner.xcodeproj/project.pbxproj';s=pbx.read_text().replace('au.monster.tracker.businessTracker','au.monster.tracker.plus').replace('IPHONEOS_DEPLOYMENT_TARGET = 13.0','IPHONEOS_DEPLOYMENT_TARGET = 15.5');pbx.write_text(s)
pod=u/'ios/Podfile'
if pod.exists():
    s=pod.read_text()
    import re
    s=re.sub(r"#?\s*platform :ios, '[0-9.]+'", "platform :ios, '15.5'",s)
    pod.write_text(s)
print('Native projects prepared. Android signing key is mandatory; iOS signing remains owner configured.')
