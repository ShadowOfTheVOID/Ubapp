plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.example.ubapp"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.example.ubapp"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    buildFeatures { compose = true }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.09.03")
    implementation(composeBom)
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.navigation:navigation-compose:2.8.2")

    // QR for the host's "guests join here" screen.
    implementation("com.google.zxing:core:3.5.3")

    // Embedded HTTP + WebSocket server for browser-tier games.
    implementation("org.nanohttpd:nanohttpd-websocket:2.3.1")

    // WebSocket client for Tag peers connecting to a host.
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // Compose permission helpers for the Tag BLE prompts.
    implementation("com.google.accompanist:accompanist-permissions:0.36.0")

    // On-device NLI for The Bureaucrat's contradiction detector. The model
    // file itself (assets/nli_minilm.onnx) is not committed; OnnxContradiction-
    // Detector falls back to the keyword detector when the asset is absent.
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.19.2")

    // One-time IAP to remove ads. Wire up BillingClient in AdManager when ready.
    implementation("com.android.billingclient:billing-ktx:7.0.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlin:kotlin-test")
}
