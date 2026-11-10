plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "jp.wojak.blepoc"
    compileSdk = 37

    defaultConfig {
        applicationId = "jp.wojak.blepoc"
        minSdk = 31
        // 34: Android 15 以降の挙動の変更 (edge-to-edge の強制など) を検証の変数に入れないため
        targetSdk = 34
        versionCode = 1
        versionName = "0.1"
    }

    buildFeatures {
        compose = true
    }
}

dependencies {
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.material3)
    implementation(libs.activity.compose)
    implementation(libs.play.services.nearby)
    implementation(libs.fragment)
}
