plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.aplicativo"

    // Requerido pelos plugins (activity-ktx/core-ktx e plugins Flutter)
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        // Você já está usando Java 11, pode manter
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11

        // *** IMPORTANTE: habilita core library desugaring ***
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.aplicativo"
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug") // troque pela release se tiver
            isMinifyEnabled = false
            isShrinkResources = false
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

// *** AQUI É FUNDAMENTAL TER ESSE BLOCO ***
dependencies {
    // Outras dependências que você já tiver podem ficar aqui
    // implementation("org.jetbrains.kotlin:kotlin-stdlib")

    // *** ESTA LINHA É OBRIGATÓRIA PARA O DESUGARING ***
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
