# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Firebase / Google Play services
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Gson (used by some plugins)
-keepattributes Signature
-keepattributes *Annotation*
