# Firebase component registrars are discovered by NAME (manifest metadata)
# and instantiated reflectively via their no-arg constructor. R8 kept the
# class but stripped the constructor in release builds:
#   NoSuchMethodException: com.google.firebase.crashlytics.CrashlyticsRegistrar.<init> []
# → "FirebaseCrashlytics component is not present" → (pre-guard) splash brick.
# Keep every registrar implementation together with its no-arg constructor.
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    <init>();
}
