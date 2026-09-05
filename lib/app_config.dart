// ملف الإعدادات — كل ما قد تغيّره لاحقاً موجود هنا فقط.
// غيّر اسم التطبيق والمنطقة والتصنيفات والألوان من هذا الملف دون لمس main.dart
// KM2 Development — KASEM BALAD

import 'package:flutter/material.dart';

/// خدمة استضافة الصور المستخدمة.
/// github  = مستودع GitHub + jsDelivr — مجاني بلا حدود ولا بطاقة (الموصى به)
/// imgbb   = استضافة صور بسيطة، تسجيل بالبريد فقط
/// firebaseStorage = يتطلب ترقية المشروع إلى خطة Blaze
enum ImageBackend { github, imgbb, firebaseStorage }

/// خدمة استضافة الفيديو.
/// supabase = مجاني بلا بطاقة، ومصمّم للوسائط (الموصى به)
/// youtubeOnly = لا رفع مباشر، روابط يوتيوب فقط
/// firebaseStorage = يتطلب خطة Blaze
enum VideoBackend { supabase, youtubeOnly, firebaseStorage }

class AppConfig {
  // ===== الهوية =====
  static const String appName = 'أخبار بلد';
  static const String regionName = 'بلد';
  static const String tagline = 'أخبار منطقتك أولاً بأول';
  static const String developer = 'KASEM BALAD';
  static const String publisherName = 'أخبار بلد'; // الاسم الظاهر ككاتب للمنشور

  // ===== الألوان (أبيض + أزرق) =====
  static const Color primary = Color(0xFF0B63CE);
  static const Color primaryDark = Color(0xFF084A9C);
  static const Color primarySoft = Color(0xFFE8F1FD);
  static const Color background = Color(0xFFF6F8FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textStrong = Color(0xFF102039);
  static const Color textSoft = Color(0xFF6C7B90);
  static const Color line = Color(0xFFE4EAF2);
  static const Color danger = Color(0xFFD93B3B);

  // ===== التصنيفات (للتوسّع مستقبلاً) =====
  static const String allCategory = 'الكل';
  static const List<String> categories = <String>[
    'عام',
    'عاجل',
    'خدمات',
    'مجتمع',
    'رياضة',
    'إعلانات',
  ];

  // ===== الفيديو =====
  static const bool allowVideo = true;
  static const VideoBackend videoBackend = VideoBackend.supabase;

  /// حد حجم الفيديو بالميغابايت
  static const int maxVideoMB = 45;

  /// الرفع المباشر من المتصفح.
  /// false = يُخفى زر رفع الفيديو على الويب ويبقى رابط يوتيوب فقط.
  /// السبب: المتصفح لا يستطيع تحويل ترميز الفيديو، فمقاطع الآيفون (HEVC)
  /// تُرفع كما هي ولا تعمل على أندرويد وكروم. التحويل يتم في تطبيق الجوال.
  static const bool allowVideoUploadOnWeb = false;

  /// من لوحة Supabase: Project Settings → Data API → Project URL
  static const String supabaseUrl = 'https://ضع_معرّف_مشروعك.supabase.co';
  static const String supabaseBucket = 'media';

  // ===== حدود =====
  static const int maxImagesPerPost = 4;
  static const int pageSize = 10;
  static const int maxPostLength = 5000;
  static const int maxCommentLength = 500;

  // ===== الصور =====
  static const ImageBackend imageBackend = ImageBackend.github;

  // مستودع GitHub الذي تُرفع إليه صور الأخبار (اجعله Public)
  static const String githubOwner = 'pcbalad2020-coder';
  static const String githubRepo = 'new_balad';
  static const String githubBranch = 'main';
  static const String githubFolder = 'images';

  /// true = روابط jsDelivr (أسرع وCDN عالمي، لكن قد تتأخر ثوانٍ لأول ظهور)
  /// false = روابط raw.githubusercontent (فورية دائماً)
  static const bool useJsDelivr = true;

  // المفاتيح السرية (توكن GitHub / مفتاح ImgBB) لا تُكتب هنا،
  // بل في Firestore: config/secrets — يقرؤها الأدمن فقط.

  // ===== الإشعارات =====
  static const String newsTopic = 'news';
  static const String notificationChannelId = 'news_channel';

  // ===== أسماء المجموعات في Firestore =====
  static const String postsCollection = 'posts';
  static const String adminsCollection = 'admins';
  static const String likesSubcollection = 'likes';
  static const String commentsSubcollection = 'comments';
  static const String storageFolder = 'posts';
}
