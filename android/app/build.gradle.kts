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
if (!keystoreProps.containsKey("storeFile")) {
    logger.warn(
        "AVISO Scrotify: no hay android/key.properties; los builds release se firman " +
            "con la clave DEBUG. Sirve para instalar por adb, no para distribuir."
    )
}

android {
    namespace = "com.example.navidrome_client"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.navidrome_client"
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
            manifestPlaceholders["appLabel"] = "Scrotify"
        }
        create("tv") {
            dimension = "device"
            manifestPlaceholders["appLabel"] = "Scrotify TV"
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
    }

    buildTypes {
        release {
            signingConfig =
                if (keystoreProps.containsKey("storeFile")) signingConfigs.getByName("release")
                else signingConfigs.getByName("debug")
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
