-keep class io.flutter.** { *; }
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn io.flutter.embedding.**
-dontwarn com.google.android.gms.**

# video_player / ExoPlayer
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# video_compress
-keep class com.otaliastudios.** { *; }
-dontwarn com.otaliastudios.**