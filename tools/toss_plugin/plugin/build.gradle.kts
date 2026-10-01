import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.zombieescape.payments"
    compileSdk = 35
    buildFeatures { buildConfig = true }
    defaultConfig {
        minSdk = 24
        manifestPlaceholders["godotPluginName"] = "TossGamePayments"
        manifestPlaceholders["godotPluginPackageName"] = "com.zombieescape.payments"
        buildConfigField("String", "GODOT_PLUGIN_NAME", "\"TossGamePayments\"")
        setProperty("archivesBaseName", "TossGamePayments")
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_17) } }
}

dependencies {
    implementation("org.godotengine:godot:4.7.2.stable")
    implementation("com.github.tosspayments:payment-sdk-android:0.1.22")
    implementation("androidx.appcompat:appcompat:1.7.1")
    testImplementation("junit:junit:4.13.2")
}

// A local test-runner fallback for Windows folders containing spaces and non-ASCII characters.
tasks.register("writeUnitTestClasspath") {
    val runtime = configurations.named("debugUnitTestRuntimeClasspath")
    doLast {
        val target = layout.buildDirectory.file("test-classpath.txt").get().asFile
        target.parentFile.mkdirs()
        target.writeText(runtime.get().files.joinToString(File.pathSeparator))
    }
}
