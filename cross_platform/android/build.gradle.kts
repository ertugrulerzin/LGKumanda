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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Release lint crashes inside webview_flutter_android (pulled in by
// google_mobile_ads) with a JDK 17 NoSuchMethodError in lint itself; the
// plugin's own code is not ours to lint, so skip lint-vital for plugins.
subprojects {
    if (name != "app") {
        tasks.matching { it.name.startsWith("lintVital") }.configureEach { enabled = false }
    }
}
