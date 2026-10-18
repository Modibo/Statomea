import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signature de publication : clé dans ~/.statomea (hors dépôt), mot de passe dans le trousseau macOS, transmis par
// deploy/publish-web.sh (STATOMEA_KEY_PASSWORD). Sans eux (développement), la clé de débogage est utilisée.
val statomeaKey = Properties().apply {
    val f = file(System.getProperty("user.home") + "/.statomea/key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val statomeaKeyPassword: String? = System.getenv("STATOMEA_KEY_PASSWORD")?.takeIf { it.isNotEmpty() }

android {
    namespace = "org.statomea.statomea"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "org.statomea.statomea"
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

    signingConfigs {
        if (statomeaKey.getProperty("storeFile") != null && statomeaKeyPassword != null) {
            create("release") {
                storeFile = file(statomeaKey.getProperty("storeFile"))
                storePassword = statomeaKeyPassword
                keyAlias = statomeaKey.getProperty("keyAlias")
                keyPassword = statomeaKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
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
    // FileProvider : ouverture de l'installateur pour une mise à jour téléchargée par l'application.
    implementation("androidx.core:core-ktx:1.13.1")
}
