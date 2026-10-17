import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma de release: si existe android/key.properties se usa; si no, cae a la
// clave debug para que `flutter run --release` siga funcionando en desarrollo.
val keystoreProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
// Solo para tool/migrate_android_signing.sh (ver docs/SIGNING.md), que usa
// builds debug porque `run-as` solo funciona con apps depurables:
// - legacyAppId: id de la instalación vieja, así se actualiza encima sin
//   perder datos y se copian. legacyKeyProperties: el key.properties de la
//   clave con que se firmó (sin él, la clave debug).
// - signingMigration: el build debug se firma con la clave propia, así el
//   release normal se instala después encima conservando los datos.
val legacyAppId = project.findProperty("legacyAppId") as String?
val legacyKeyProps = (project.findProperty("legacyKeyProperties") as String?)?.let { path ->
    Properties().apply { file(path).inputStream().use { load(it) } }
}
val signingMigration = project.hasProperty("signingMigration")
// Un release sin clave propia solo se permite si se pide explícitamente
// (`ORG_GRADLE_PROJECT_allowDebugSigning=true` o `-PallowDebugSigning`); así
// nadie distribuye por error un APK firmado con la clave debug.
gradle.taskGraph.whenReady {
    val releaseRequested = allTasks.any {
        it.project == project &&
            it.name.contains("Release") &&
            (it.name.startsWith("assemble") || it.name.startsWith("bundle") ||
                it.name.startsWith("package"))
    }
    if (releaseRequested && !keystoreProps.containsKey("storeFile") &&
        !project.hasProperty("allowDebugSigning")
    ) {
        throw GradleException(
            "Falta android/key.properties: un release no se firma con la clave debug " +
                "por defecto. Crea key.properties o define " +
                "ORG_GRADLE_PROJECT_allowDebugSigning=true para una instalación local."
        )
    }
}
if (!keystoreProps.containsKey("storeFile")) {
    logger.warn(
        "AVISO CrotoWave: no hay android/key.properties; los builds release se firman " +
            "con la clave DEBUG. Sirve para instalar por adb, no para distribuir."
    )
}

android {
    namespace = "cloud.templo.crotowave"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Definitivo: no cambiarlo nunca más (Android lo trata como otra app y
        // Play no deja publicar con otro). Antes: cloud.templo.crotowave
        // (plantilla).
        applicationId = legacyAppId ?: "cloud.templo.crotowave"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Dos APK separados: `phone` (táctil, cámara QR, huella) y `tv` (control
    // remoto, leanback). Build: scripts/build_apks.sh
    flavorDimensions += "device"
    productFlavors {
        create("phone") {
            dimension = "device"
            manifestPlaceholders["appLabel"] = "CrotoWave"
        }
        create("tv") {
            dimension = "device"
            manifestPlaceholders["appLabel"] = "CrotoWave TV"
        }
    }

    signingConfigs {
        create("release") {
            if (keystoreProps.containsKey("storeFile")) {
                storeFile = file(keystoreProps["storeFile"] as String)
                storePassword = keystoreProps["storePassword"] as String
                keyAlias = keystoreProps["keyAlias"] as String
                keyPassword = keystoreProps["keyPassword"] as String
            }
        }
        if (legacyKeyProps != null) {
            create("legacy") {
                storeFile = file(legacyKeyProps["storeFile"] as String)
                storePassword = legacyKeyProps["storePassword"] as String
                keyAlias = legacyKeyProps["keyAlias"] as String
                keyPassword = legacyKeyProps["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (keystoreProps.containsKey("storeFile")) signingConfigs.getByName("release")
                else signingConfigs.getByName("debug")
        }
        debug {
            if (legacyKeyProps != null) {
                signingConfig = signingConfigs.getByName("legacy")
            } else if (signingMigration && keystoreProps.containsKey("storeFile")) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
