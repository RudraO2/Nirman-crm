import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

android {
    namespace = "com.nirmanmedia.nirman_crm"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    defaultConfig {
        applicationId = "com.nirmanmedia.nirman_crm"
        // NFR-19: Android API 26+ (Android 8.0)
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            // proguard-rules.pro: keep Firebase ComponentRegistrar no-arg
            // constructors — R8 stripped CrashlyticsRegistrar.<init>() and
            // killed Crashlytics in every release build.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_1_8)
    }
}

flutter {
    source = "../.."
}

// NO manual Firebase deps here. The flutter plugins (firebase_core,
// firebase_messaging, firebase_crashlytics) each bundle their own matched
// native libraries. The old hand-pinned firebase-bom:33.0.0 sat UNDER the
// versions firebase_crashlytics 4.3.10 expects and broke component
// registration in release builds ("FirebaseCrashlytics component is not
// present" — app stuck on splash until the fail-soft guard in main.dart).
// If a future native-only Firebase API is ever needed, add it WITHOUT a BoM
// and let Gradle resolve against the plugin versions.
