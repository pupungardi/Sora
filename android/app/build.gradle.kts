plugins {
    id("com.android.application")
    kotlin("android")
}

android {
    namespace = "app.sora"
    compileSdk = 36

    defaultConfig {
        applicationId = "app.sora"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"

        // nuvio-engine ships JNI code for these four ABIs.
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        viewBinding = true
    }

    packaging {
        resources {
            excludes += setOf("META-INF/AL2.0", "META-INF/LGPL2.1")
        }
        // nuvio-libass deliberately excludes libc++_shared.so from its AAR.
        // When you add that AAR, drop the .so files into app/src/main/jniLibs/<abi>/
        // and the default jniLibs packaging picks them up.
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    // engine-release.aar (and, later, nuvio-libass-release.aar) live here.
    implementation(fileTree("libs") { include("*.aar", "*.jar") })

    implementation("androidx.media3:media3-exoplayer:1.8.0")
    implementation("androidx.media3:media3-ui:1.8.0")
    implementation("androidx.activity:activity-ktx:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}
