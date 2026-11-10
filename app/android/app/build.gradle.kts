import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// FlutterFire の Android 設定を、Dart の起動前に FirebaseInitProvider が読める形にする。
val firebaseAndroidOptions = providers
    .fileContents(layout.projectDirectory.file("../../lib/firebase_options.dart"))
    .asText.get()
    .substringAfter("static const FirebaseOptions android = FirebaseOptions(", "")
    .substringBefore(");")

fun firebaseAndroidOption(name: String): String =
    Regex("""\b${Regex.escape(name)}:\s*'([^']+)'""")
        .find(firebaseAndroidOptions)?.groupValues?.get(1)
        ?: error("Missing Android Firebase option: $name")

val releaseKeyFile = rootProject.file("key.properties")
val releaseKey = Properties().apply {
    if (releaseKeyFile.isFile) releaseKeyFile.inputStream().use { load(it) }
}
fun releaseKeyProperty(name: String): String =
    releaseKey.getProperty(name)?.takeIf { it.isNotBlank() }
        ?: error("Missing $name in android/key.properties")

android {
    namespace = "jp.dfhack26.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        resValues = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "jp.dfhack26.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // BLE の常駐 (A3) の権限が Android 12 (API 31) から。poc/ble と同じ
        minSdk = 31
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        resValue("string", "google_app_id", firebaseAndroidOption("appId"))
        resValue("string", "google_api_key", firebaseAndroidOption("apiKey"))
        resValue("string", "gcm_defaultSenderId", firebaseAndroidOption("messagingSenderId"))
        resValue("string", "project_id", firebaseAndroidOption("projectId"))
        resValue("string", "google_storage_bucket", firebaseAndroidOption("storageBucket"))
    }

    signingConfigs {
        if (releaseKeyFile.isFile) {
            create("release") {
                keyAlias = releaseKeyProperty("keyAlias")
                keyPassword = releaseKeyProperty("keyPassword")
                storeFile = rootProject.file(releaseKeyProperty("storeFile"))
                storePassword = releaseKeyProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
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
    // BLE の中身の決まりを実機なしで確かめる (src/test)
    testImplementation("junit:junit:4.13.2")
}
