allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Disable Android lint across all modules. Not needed for a personal/sideload APK, and the
// lint cache hits Windows file locks when the project lives under a OneDrive-synced folder.
gradle.taskGraph.whenReady {
    allTasks.filter { it.name.contains("lint", ignoreCase = true) }.forEach { it.enabled = false }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
