buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // FIXED: Modern Build Tool version for JDK 17 compatibility
        classpath("com.android.tools.build:gradle:8.1.0")
        // FIXED: Updated Google Services for Firebase integration
        classpath("com.google.gms:google-services:4.4.1")
        // ADDED: Kotlin Gradle Plugin for modern Android features
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.0")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Build directory configuration (Standard for Flutter 3.x)
val newBuildDir: Directory =
    rootProject.layout.buildDirectory.dir("../../build").get()

rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}