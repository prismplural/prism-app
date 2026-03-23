# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }


# mobile_scanner — MLKit barcode scanning
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.vision.** { *; }

# flutter_local_notifications — uses reflection for notification handling
-keep class com.dexterous.** { *; }

# workmanager — background task callbacks
-keep class be.tramckrijte.workmanager.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep Parcelables
-keepclassmembers class * implements android.os.Parcelable {
    static ** CREATOR;
}

# Keep enums (used by various plugins)
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Suppress warnings for common Flutter plugin dependencies
-dontwarn com.google.android.play.core.**
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
