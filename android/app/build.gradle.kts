plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.silverhorizon.horizongame"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.silverhorizon.horizongame"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Horizon math is Rust → .so for arm64-v8a / armeabi-v7a / x86_64.
        // x86 is deliberately excluded: Flutter stopped shipping libflutter.so
        // for 32-bit x86, so an x86 slice of libhorizon_math would be an
        // orphan with no engine to pair with.
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Keep the Rust-exported symbols from being stripped. The crate
            // already strips its own symbol table (strip = "symbols" in
            // Cargo.toml), so what's left is the public FFI surface we need.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // Flutter stuffs libflutter.so under the standard jniLibs layout, so our
    // Rust .so files sit alongside it. useLegacyPackaging keeps them
    // uncompressed (required by Android's dlopen since API 23).
    packaging {
        jniLibs {
            useLegacyPackaging = false
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

// ----- Rust math (horizon_math) ------------------------------------------
//
// The horizon_math crate is cross-compiled with cargo-ndk and the .so
// outputs are written into src/main/jniLibs/<abi>/libhorizon_math.so. The
// task below runs on every build; cargo itself is incremental and the
// re-run is a no-op (~0.3 s) when nothing in rust/ changed.
val rustRoot = file("${project.rootDir}/../rust")
val rustSrc = fileTree(rustRoot) {
    include("horizon_math/**/*.rs", "horizon_math/Cargo.toml", "build_android.sh")
    exclude("**/target/**")
}
val jniLibsDir = file("${project.projectDir}/src/main/jniLibs")

val buildRustMath by tasks.registering(Exec::class) {
    group = "build"
    description = "Cross-compile the horizon_math Rust crate for every Android ABI."
    workingDir = rustRoot
    commandLine("bash", "build_android.sh", "release")
    // Gradle's Exec runs in a sanitised env. Re-inject the pieces the
    // Rust toolchain and cargo-ndk rely on so this task works from a
    // bare `flutter build apk` invocation too — not just from a shell
    // where the user already sourced ~/.cargo/env and exported
    // ANDROID_NDK_HOME.
    val userHome = System.getProperty("user.home")
    val sysPath = System.getenv("PATH") ?: ""
    environment("HOME", userHome)
    environment(
        "PATH",
        listOf(
            "$userHome/.cargo/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            sysPath,
        ).filter { it.isNotEmpty() }.joinToString(":"),
    )
    // Prefer the caller's ANDROID_NDK_HOME; else fall back to the newest
    // NDK installed under the Android SDK that Gradle itself discovered.
    val envNdk = System.getenv("ANDROID_NDK_HOME")
        ?: System.getenv("NDK_HOME")
        ?: android.ndkDirectory.takeIf { it.exists() }?.absolutePath
    if (envNdk != null) {
        environment("ANDROID_NDK_HOME", envNdk)
    }
    inputs.files(rustSrc)
    outputs.files(
        file("$jniLibsDir/arm64-v8a/libhorizon_math.so"),
        file("$jniLibsDir/armeabi-v7a/libhorizon_math.so"),
        file("$jniLibsDir/x86_64/libhorizon_math.so"),
    )
}

tasks.named("preBuild").configure {
    dependsOn(buildRustMath)
}
