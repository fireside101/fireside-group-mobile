plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties

val signingPropertiesFile = rootProject.file("key.properties")
val signingProperties = Properties()
if (signingPropertiesFile.exists()) {
    signingPropertiesFile.inputStream().use(signingProperties::load)
}

android {
    namespace = "com.firesideafrica.fireside_group"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // Native preflight tests use framework objects, not Flutter assets/resources.
    testOptions {
        unitTests.isIncludeAndroidResources = false
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.firesideafrica.firesidegroup"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Local builds retain the debug signing fallback. CI restores
            // key.properties from GitHub Actions secrets for production builds.
            signingConfig = if (signingPropertiesFile.exists()) {
                signingConfigs.create("production") {
                    keyAlias = signingProperties.getProperty("keyAlias")
                    keyPassword = signingProperties.getProperty("keyPassword")
                    storeFile = signingProperties.getProperty("storeFile")?.let(::file)
                    storePassword = signingProperties.getProperty("storePassword")
                }
            } else {
                signingConfigs.getByName("debug")
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

dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16.1")
    testImplementation("org.mockito:mockito-core:5.23.0")
    // Match Flutter integration_test's AndroidX runner constraints.
    androidTestImplementation("androidx.test:runner:1.3.0")
    androidTestImplementation("androidx.test.ext:junit:1.1.2")
    androidTestImplementation("junit:junit:4.12")
}
