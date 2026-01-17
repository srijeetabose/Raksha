plugins {
    id("com.android.application")
    id("com.google.gms.google-services") 
    id("org.jetbrains.kotlin.android") 
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.raksha"
    compileSdk = flutter.compileSdkVersion 
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        // FIX 1: Use string literal "1.8" for consistent KTS
        jvmTarget = "1.8" 
    }

    defaultConfig {
        applicationId = "com.example.raksha"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false // Disable R8 minification to fix MediaPipe issues
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Standard Kotlin and AndroidX core libraries - FIXED VERSION MATCHING
    implementation("org.jetbrains.kotlin:kotlin-stdlib:1.9.20")
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.9.20")
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.6.1")
    implementation("androidx.lifecycle:lifecycle-service:2.6.1")
    implementation("androidx.appcompat:appcompat:1.6.1")

    // FIREBASE SERVICES
    implementation(platform("com.google.firebase:firebase-bom:33.0.0")) 
    implementation("com.google.firebase:firebase-firestore-ktx")
    implementation("com.google.firebase:firebase-auth-ktx")
    implementation("com.google.firebase:firebase-storage-ktx")

    // LOCATION SERVICES
    implementation("com.google.android.gms:play-services-location:21.0.1")

    // MEDIA PIPE TASKS (using stable version that works)
    implementation("com.google.mediapipe:tasks-vision:0.10.0")
    implementation("com.google.mediapipe:tasks-core:0.10.0")

    // CAMERA X
    val camerax_version = "1.3.1"
    implementation("androidx.camera:camera-core:${camerax_version}")
    implementation("androidx.camera:camera-camera2:${camerax_version}")
    implementation("androidx.camera:camera-lifecycle:${camerax_version}")
    implementation("androidx.camera:camera-video:${camerax_version}")

    // NOTIFICATIONS
    implementation("androidx.core:core:1.12.0")
    
    // SPEECH RECOGNITION
    implementation("androidx.core:core-ktx:1.12.0")
}