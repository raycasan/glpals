# flutter_local_notifications stores scheduled notifications with Gson and
# relies on generic type signatures at runtime. R8 must keep them.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# home_widget provider is looked up by name from Dart.
-keep class es.antonborri.home_widget.** { *; }
-keep class com.glpbuddy.glp_buddy.GlpalsWidgetProvider { *; }
