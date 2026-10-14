import com.android.build.gradle.AppExtension

val android = project.extensions.getByType(AppExtension::class.java)

android.apply {
    flavorDimensions("flavor-type")

    productFlavors {
        create("dev") {
            dimension = "flavor-type"
            applicationId = "com.yemanzefen.yeman_zefen.dev"
            resValue(type = "string", name = "app_name", value = "Yeman Zefen DEV")
        }
        create("prod") {
            dimension = "flavor-type"
            applicationId = "com.yemanzefen.yeman_zefen"
            resValue(type = "string", name = "app_name", value = "Yeman Zefen")
        }
    }

    buildFeatures.resValues = true
}