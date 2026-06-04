# R8/ProGuard keep rules for the Jamboree release build.
#
# Most dependencies (AndroidX, Compose, Play Services Ads, Play Billing,
# OkHttp, NanoHTTPD) ship their own consumer ProGuard rules, so they need
# nothing here. The rules below cover libraries that rely on JNI/reflection
# and the small amount of app code reached reflectively.

# --- ONNX Runtime --------------------------------------------------------
# The Bureaucrat's on-device NLI model is loaded through ONNX Runtime, which
# binds to native code via JNI. Keep its classes and native methods so R8
# doesn't rename/strip symbols the native layer looks up by name.
-keep class ai.onnxruntime.** { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}
-dontwarn ai.onnxruntime.**

# --- NanoHTTPD -----------------------------------------------------------
# The embedded host server. Conservative keep; it does not normally need
# reflection, but keeping it avoids any surprise with the WebSocket subclass.
-keep class fi.iki.elonen.** { *; }
-dontwarn fi.iki.elonen.**

# --- OkHttp / Okio -------------------------------------------------------
# These ship consumer rules; silence the optional-platform warnings R8 emits
# for code paths Android never takes.
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# --- Kotlin / Coroutines -------------------------------------------------
-dontwarn kotlinx.coroutines.**

# --- App enums sent over the wire ---------------------------------------
# Engines serialize enum names (Enum.valueOf / name) for the JSON protocol;
# keep enum members so obfuscation can't change their string values.
-keepclassmembers enum com.example.jamboree.** {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
