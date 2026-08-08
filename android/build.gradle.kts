import com.android.build.api.dsl.LibraryExtension

allprojects {
    repositories {
        val useMirror = System.getenv("OMNI_ANDROID_MAVEN_MIRROR") == "aliyun"
        if (useMirror) {
            maven(url = "https://maven.aliyun.com/repository/google")
            maven(url = "https://maven.aliyun.com/repository/public")
        } else {
            google()
            mavenCentral()
        }
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
    val ndkOverride = System.getenv("OMNI_ANDROID_NDK_VERSION")
    if (ndkOverride != null) {
        plugins.withId("com.android.library") {
            extensions.configure<LibraryExtension> {
                ndkVersion = ndkOverride
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
