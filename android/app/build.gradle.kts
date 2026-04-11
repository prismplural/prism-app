import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.prism.prism_plurality"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    // Release signing reads from app/key.properties (never commit this file or the keystore).
    // One-time setup:
    //   1. Generate keystore:
    //        keytool -genkey -v -keystore upload-keystore.jks -storetype JKS \
    //          -keyalg RSA -keysize 2048 -validity 10000 -alias upload
    //   2. Move to app/upload-keystore.jks (it is .gitignored).
    //   3. Create app/key.properties:
    //        storePassword=<keystore password>
    //        keyPassword=<key password>
    //        keyAlias=upload
    //        storeFile=../upload-keystore.jks
    //   For CI: set KEY_STORE_PASSWORD, KEY_PASSWORD, KEY_ALIAS, KEY_STORE_FILE
    //   as environment variables and replace the properties lookup below.
    val keyPropertiesFile = rootProject.file("app/key.properties")
    val keyProperties = Properties()
    if (keyPropertiesFile.exists()) {
        keyProperties.load(keyPropertiesFile.inputStream())
    }

    signingConfigs {
        if (keyPropertiesFile.exists()) {
            create("release") {
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
            }
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.prism.prism_plurality"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            ndk {
                // Only compile for arm64 in debug builds — skips armeabi-v7a,
                // cutting Rust FFI + native plugin compilation time ~40%.
                // clear() + add() (not +=) ensures Flutter's Gradle plugin cannot
                // re-add other ABIs. Release builds have no filter (Play Store
                // needs all ABIs).
                abiFilters.clear()
                abiFilters.add("arm64-v8a")
            }
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // Use release signing when key.properties is configured; fall back to
            // debug keys so `flutter run --release` works locally before setup.
            val hasRelease = signingConfigs.names.contains("release")
            signingConfig = if (hasRelease) signingConfigs.getByName("release")
                            else signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
