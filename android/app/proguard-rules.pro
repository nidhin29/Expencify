# ProGuard rules for Fintastics (Expencify)

# MediaPipe (used by flutter_gemma)
-keep class com.google.mediapipe.** { *; }
-keep interface com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# ML Kit (used by text recognition)
-keep class com.google.mlkit.** { *; }
-keep interface com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# Keep specific missing classes mentioned in build errors
-keep class com.google.mediapipe.proto.** { *; }
-keep class com.google.mlkit.vision.text.chinese.** { *; }
-keep class com.google.mlkit.vision.text.devanagari.** { *; }
-keep class com.google.mlkit.vision.text.japanese.** { *; }
-keep class com.google.mlkit.vision.text.korean.** { *; }

# Standard Flutter ProGuard rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Keep everything in our package just in case
-keep class com.example.expencify.** { *; }

# Telephony plugin (SMS Monitoring)
-keep class com.shounakmulay.telephony.** { *; }
-keep interface com.shounakmulay.telephony.** { *; }
-dontwarn com.shounakmulay.telephony.**
