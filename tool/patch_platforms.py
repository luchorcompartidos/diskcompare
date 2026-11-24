"""Ajustes a la carpeta android/ que genera `flutter create` en GitHub Actions.

Uso: python3 tool/patch_platforms.py android|signing
"""
import glob
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KOTLIN = ["MainActivity.kt", "SmbBridge.kt", "Secret.kt"]  # tool/android/*.kt

# smbj (SMB 2/3, para leer carpetas compartidas de Windows) + desugaring de Java 8
# (smbj usa APIs de Java 8 que Android 5/6 no trae).
SMB_GRADLE = """

// DiskCompare: SMB con smbj
android {
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
    }
    packaging {
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/INDEX.LIST",
                "META-INF/versions/9/OSGI-INF/MANIFEST.MF",
            )
        }
    }
    buildTypes {
        getByName("release") { proguardFiles("proguard-rules.pro") }
    }
}

dependencies {
    implementation("com.hierynomus:smbj:0.13.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
"""

SIGNING = """

// Firma fija (la clave llega desde los Secrets del repo)
System.getenv("DC_KEYSTORE_PATH")?.let { ks ->
    android {
        signingConfigs {
            create("dc") {
                storeFile = file(ks)
                storePassword = System.getenv("DC_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("DC_KEY_ALIAS")
                keyPassword = System.getenv("DC_KEYSTORE_PASSWORD")
            }
        }
        buildTypes {
            getByName("release") { signingConfig = signingConfigs.getByName("dc") }
        }
    }
}
"""


def patch(path, old, new):
    s = open(path, encoding="utf-8").read()
    if new in s:
        return
    if old not in s:
        sys.exit(f"::error::No encontré el punto a modificar en {path}: {old!r}")
    open(path, "w", encoding="utf-8").write(s.replace(old, new, 1))
    print(f"OK {path}")


def android():
    m = "android/app/src/main/AndroidManifest.xml"
    s = open(m, encoding="utf-8").read()
    s = re.sub(r'android:label="[^"]*"', 'android:label="DiskCompare"', s, count=1)
    open(m, "w", encoding="utf-8").write(s)
    if "android.permission.INTERNET" not in s:
        patch(m, "<application",
              '<uses-permission android:name="android.permission.INTERNET" />\n'
              '    <application')
    s = open(m, encoding="utf-8").read()
    if "MANAGE_EXTERNAL_STORAGE" not in s:
        patch(m, "<application",
              '<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />\n'
              '    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />\n'
              '    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29" />\n'
              '    <application')
    s = open(m, encoding="utf-8").read()
    if "requestLegacyExternalStorage" not in s:
        patch(m, "<application", '<application android:requestLegacyExternalStorage="true"')
    found = glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True)
    if not found:
        sys.exit("::error::No encontré MainActivity.kt")
    dest = os.path.dirname(found[0])
    for k in KOTLIN:
        shutil.copy(os.path.join(HERE, "android", k), os.path.join(dest, k))
        print(f"OK {dest}/{k}")
    shutil.copy(os.path.join(HERE, "android", "proguard-rules.pro"), "android/app/proguard-rules.pro")
    g = "android/app/build.gradle.kts"
    gs = open(g, encoding="utf-8").read()
    if "com.hierynomus:smbj" not in gs:
        open(g, "a", encoding="utf-8").write(SMB_GRADLE)
        print(f"OK {g} (smbj)")


def signing():
    g = "android/app/build.gradle.kts"
    s = open(g, encoding="utf-8").read()
    if "DC_KEYSTORE_PATH" not in s:
        open(g, "a", encoding="utf-8").write(SIGNING)
        print(f"OK {g}")


if __name__ == "__main__":
    {"android": android, "signing": signing}[sys.argv[1]]()
