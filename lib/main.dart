// ===========================================================================
//  تطبيق أخبار المنطقة — نمط تواصل اجتماعي، النشر للإدارة فقط
//  الزائر: يقرأ + يعجب + يعلّق   |   الأدمن: ينشر نصاً وصوراً ويحذف ويثبّت
//  Flutter + Firebase  |  Android / iOS / Web
//  المطوّر: KASEM BALAD — KM2 Development
// ===========================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

import 'app_config.dart';
import 'firebase_options.dart';

/// مفتاح التنقّل — يفتح الخبر عند الضغط على الإشعار.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// معالج الرسائل والتطبيق مغلق (يجب أن يكون دالة عليا).
@pragma('vm:entry-point')
Future<void> _backgroundMessageHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_backgroundMessageHandler);
  }
  await Notifications.init();
  await Blocked.load();
  runApp(const NewsApp());
}

// ===========================================================================
//  التطبيق والثيم
// ===========================================================================

class NewsApp extends StatelessWidget {
  const NewsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: _buildTheme(),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const AuthGate(),
    );
  }

  ThemeData _buildTheme() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppConfig.primary,
        primary: AppConfig.primary,
        surface: AppConfig.surface,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AppConfig.background,
      fontFamily: 'Cairo',
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppConfig.surface,
        foregroundColor: AppConfig.textStrong,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      dividerTheme: const DividerThemeData(
        color: AppConfig.line,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppConfig.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppConfig.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppConfig.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppConfig.primary, width: 1.6),
        ),
        hintStyle: const TextStyle(color: AppConfig.textSoft),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppConfig.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppConfig.textStrong,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppConfig.textStrong,
        displayColor: AppConfig.textStrong,
      ),
    );
  }
}

// ===========================================================================
//  الخدمات: المصادقة + البيانات
// ===========================================================================

class Api {
  Api._();

  static FirebaseFirestore get db => FirebaseFirestore.instance;
  static FirebaseAuth get auth => FirebaseAuth.instance;
  static FirebaseStorage get storage => FirebaseStorage.instance;

  static User? get user => auth.currentUser;
  static String get uid => auth.currentUser?.uid ?? '';
  static String get displayName =>
      (auth.currentUser?.displayName ?? '').trim().isEmpty
          ? 'زائر'
          : auth.currentUser!.displayName!.trim();

  /// دخول تلقائي كمجهول ليتمكن الزائر من الإعجاب والتعليق.
  static Future<void> ensureSignedIn() async {
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
  }

  /// هل المستخدم الحالي أدمن؟ يعتمد على وجود مستند في مجموعة admins.
  static Stream<bool> isAdminStream() {
    return auth.authStateChanges().asyncExpand((u) {
      if (u == null || u.isAnonymous) return Stream<bool>.value(false);
      return db
          .collection(AppConfig.adminsCollection)
          .doc(u.uid)
          .snapshots()
          .map((d) => d.exists);
    });
  }

  static CollectionReference<Map<String, dynamic>> get posts =>
      db.collection(AppConfig.postsCollection);

  /// استعلام واحد بلا شروط تصنيف — فالفلترة تتم في التطبيق.
  /// هكذا لا نحتاج فهرساً مركّباً في Firestore، وتعمل التصنيفات فوراً.
  static Query<Map<String, dynamic>> postsQuery({required int limit}) {
    return posts.orderBy('createdAt', descending: true).limit(limit);
  }

  // ---------- النشر ----------

  static Future<void> createPost({
    required String text,
    required String category,
    required bool pinned,
    required List<XFile> images,
    XFile? video,
    double videoRatio = 16 / 9,
    String youtubeId = '',
    void Function(double)? onProgress,
  }) async {
    final docRef = posts.doc();
    final urls = <String>[];
    final paths = <String>[];
    final ratios = <double>[];
    var videoUrl = '';
    var videoPath = '';

    for (var i = 0; i < images.length; i++) {
      final bytes = Uint8List.fromList(await images[i].readAsBytes());
      ratios.add(await imageRatio(bytes));
      final uploaded = await ImageUploader.upload(bytes, docRef.id, i);
      urls.add(uploaded.url);
      paths.add(uploaded.path);
      onProgress?.call((i + 1) / images.length);
    }

    if (video != null) {
      final bytes = Uint8List.fromList(await video.readAsBytes());
      final sizeMB = bytes.lengthInBytes / (1024 * 1024);
      if (sizeMB > AppConfig.maxVideoMB) {
        throw Exception('حجم الفيديو ${sizeMB.toStringAsFixed(1)} ميغا،'
            ' والحد المسموح ${AppConfig.maxVideoMB} ميغا');
      }
      // نحافظ على الامتداد الأصلي — تسمية ملف mov باسم mp4 تمنع تشغيله
      final ext = videoExtension(video.name);
      final uploaded = await ImageUploader.uploadVideo(
          bytes, docRef.id, ext, videoMime(ext));
      videoUrl = uploaded.url;
      videoPath = uploaded.path;
    }

    await docRef.set({
      'text': text.trim(),
      'images': urls,
      'imagePaths': paths,
      'imageRatios': ratios,
      'videoUrl': videoUrl,
      'videoPath': videoPath,
      'videoRatio': videoUrl.isEmpty ? 0 : videoRatio,
      'youtubeId': youtubeId,
      'category': category,
      'pinned': pinned,
      'authorId': uid,
      'authorName': AppConfig.publisherName,
      'likesCount': 0,
      'commentsCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> updatePost(
    String postId, {
    required String text,
    required String category,
    required bool pinned,
  }) {
    return posts.doc(postId).update({
      'text': text.trim(),
      'category': category,
      'pinned': pinned,
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deletePost(String postId, List<String> imagePaths) async {
    if (AppConfig.imageBackend == ImageBackend.firebaseStorage) {
      for (final p in imagePaths) {
        try {
          await storage.ref(p).delete();
        } catch (_) {
          // الصورة محذوفة مسبقاً — نتجاهل
        }
      }
    }
    // ملاحظة: الصور المستضافة خارجياً (GitHub / ImgBB) لا تُحذف تلقائياً.
    // احذفها عند الحاجة من المستودع مباشرة.
    for (final sub in [
      AppConfig.commentsSubcollection,
      AppConfig.likesSubcollection
    ]) {
      final snap = await posts.doc(postId).collection(sub).limit(400).get();
      final batch = db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
    await posts.doc(postId).delete();
  }

  // ---------- الإعجاب ----------

  static Stream<bool> likedStream(String postId) {
    if (uid.isEmpty) return Stream<bool>.value(false);
    return posts
        .doc(postId)
        .collection(AppConfig.likesSubcollection)
        .doc(uid)
        .snapshots()
        .map((d) => d.exists);
  }

  static Future<void> toggleLike(String postId) async {
    await ensureSignedIn();
    final postRef = posts.doc(postId);
    final likeRef = postRef
        .collection(AppConfig.likesSubcollection)
        .doc(auth.currentUser!.uid);

    await db.runTransaction((tx) async {
      final likeSnap = await tx.get(likeRef);
      final postSnap = await tx.get(postRef);
      if (!postSnap.exists) return;
      final count = (postSnap.data()?['likesCount'] as num? ?? 0).toInt();

      if (likeSnap.exists) {
        tx.delete(likeRef);
        tx.update(postRef, {'likesCount': count > 0 ? count - 1 : 0});
      } else {
        tx.set(likeRef, {
          'uid': auth.currentUser!.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.update(postRef, {'likesCount': count + 1});
      }
    });
  }

  // ---------- التعليقات ----------

  static Stream<QuerySnapshot<Map<String, dynamic>>> commentsStream(
      String postId) {
    return posts
        .doc(postId)
        .collection(AppConfig.commentsSubcollection)
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

  static Future<void> addComment(String postId, String text) async {
    await ensureSignedIn();
    final postRef = posts.doc(postId);
    final commentRef =
        postRef.collection(AppConfig.commentsSubcollection).doc();

    await db.runTransaction((tx) async {
      final postSnap = await tx.get(postRef);
      if (!postSnap.exists) return;
      final count = (postSnap.data()?['commentsCount'] as num? ?? 0).toInt();

      tx.set(commentRef, {
        'uid': auth.currentUser!.uid,
        'name': displayName,
        'photo': photoUrl,
        'text': text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.update(postRef, {'commentsCount': count + 1});
    });
  }

  static Future<void> deleteComment(String postId, String commentId) async {
    final postRef = posts.doc(postId);
    final commentRef =
        postRef.collection(AppConfig.commentsSubcollection).doc(commentId);

    await db.runTransaction((tx) async {
      final postSnap = await tx.get(postRef);
      final commentSnap = await tx.get(commentRef);
      if (!commentSnap.exists) return;
      final count = (postSnap.data()?['commentsCount'] as num? ?? 0).toInt();
      tx.delete(commentRef);
      tx.update(postRef, {'commentsCount': count > 0 ? count - 1 : 0});
    });
  }

  // ---------- حساب الزائر ----------

  // ---------- الإبلاغ ----------

  static Future<void> reportContent({
    required String type, // post | comment
    required String postId,
    String commentId = '',
    String reportedUid = '',
    String reportedName = '',
    String snippet = '',
    required String reason,
  }) async {
    await ensureSignedIn();
    await db.collection(AppConfig.reportsCollection).add({
      'type': type,
      'postId': postId,
      'commentId': commentId,
      'reportedUid': reportedUid,
      'reportedName': reportedName,
      'snippet': snippet.length > 200 ? snippet.substring(0, 200) : snippet,
      'reason': reason,
      'reporterUid': auth.currentUser!.uid,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> reportsStream() {
    return db
        .collection(AppConfig.reportsCollection)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
  }

  // ---------- حذف الحساب ----------

  /// يحذف تعليقات المستخدم ثم حسابه نهائياً (متطلب Google Play).
  static Future<void> deleteAccount() async {
    final user = auth.currentUser;
    if (user == null) return;
    final uid = user.uid;

    try {
      final snap = await db
          .collectionGroup(AppConfig.commentsSubcollection)
          .where('uid', isEqualTo: uid)
          .limit(300)
          .get();
      for (final doc in snap.docs) {
        final postRef = doc.reference.parent.parent;
        if (postRef != null) {
          await deleteComment(postRef.id, doc.id);
        }
      }
    } catch (_) {
      // لا نمنع حذف الحساب إن تعذّر حذف التعليقات
    }

    await user.delete();
    Secrets.clear();
    await ensureSignedIn();
  }

  static Future<void> setDisplayName(String name) async {
    await ensureSignedIn();
    await auth.currentUser!.updateDisplayName(name.trim());
    await auth.currentUser!.reload();
  }

  static bool get isGuest =>
      auth.currentUser == null || (auth.currentUser?.isAnonymous ?? false);

  static String get photoUrl => auth.currentUser?.photoURL ?? '';

  /// دخول بحساب Google — يحافظ على إعجابات الزائر بربط الحساب المجهول.
  static Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      final current = auth.currentUser;
      if (current != null && current.isAnonymous) {
        try {
          await current.linkWithPopup(provider);
          return;
        } on FirebaseAuthException catch (e) {
          if (e.code != 'credential-already-in-use' &&
              e.code != 'email-already-in-use') {
            rethrow;
          }
        }
      }
      await auth.signInWithPopup(provider);
      return;
    }

    final account = await GoogleSignIn().signIn();
    if (account == null) return; // ألغى المستخدم

    final googleAuth = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final current = auth.currentUser;
    if (current != null && current.isAnonymous) {
      try {
        await current.linkWithCredential(credential);
        return;
      } on FirebaseAuthException catch (e) {
        if (e.code != 'credential-already-in-use' &&
            e.code != 'email-already-in-use') {
          rethrow;
        }
      }
    }
    await auth.signInWithCredential(credential);
  }

  static Future<void> adminSignIn(String email, String password) async {
    if (auth.currentUser?.isAnonymous ?? false) {
      await auth.signOut();
    }
    await auth.signInWithEmailAndPassword(
        email: email.trim(), password: password);
  }

  static Future<void> signOut() async {
    if (!kIsWeb) {
      try {
        await GoogleSignIn().signOut();
      } catch (_) {}
    }
    await auth.signOut();
    Secrets.clear();
    await ensureSignedIn();
  }
}

// ===========================================================================
//  رفع الصور — Cloudinary (مجاني بلا بطاقة) أو Firebase Storage
// ===========================================================================

class UploadedImage {
  final String url;
  final String path; // public_id في Cloudinary، أو مسار الملف في Storage
  const UploadedImage(this.url, this.path);
}

/// المفاتيح السرية محفوظة في Firestore (config/secrets) ويقرؤها الأدمن فقط،
/// حتى لا تُشحن داخل ملف التطبيق ويراها المستخدمون.
class Secrets {
  Secrets._();
  static Map<String, dynamic>? _cache;

  static Future<String> get(String key) async {
    _cache ??=
        (await Api.db.collection('config').doc('secrets').get()).data() ?? {};
    final value = (_cache![key] ?? '').toString();
    if (value.isEmpty) {
      throw Exception('المفتاح "$key" غير موجود في Firestore ← config/secrets');
    }
    return value;
  }

  static void clear() => _cache = null;
}

class ImageUploader {
  static Future<UploadedImage> upload(
    Uint8List bytes,
    String postId,
    int index, {
    String ext = 'jpg',
    String contentType = 'image/jpeg',
  }) {
    switch (AppConfig.imageBackend) {
      case ImageBackend.github:
        return _toGitHub(bytes, postId, index, ext);
      case ImageBackend.imgbb:
        if (ext != 'jpg') {
          throw Exception('ImgBB لا يدعم الفيديو — استخدم GitHub');
        }
        return _toImgbb(bytes, postId, index);
      case ImageBackend.firebaseStorage:
        return _toFirebase(bytes, postId, index, ext, contentType);
    }
  }

  /// رفع إلى مستودع GitHub، والعرض عبر jsDelivr.
  static Future<UploadedImage> _toGitHub(
      Uint8List bytes, String postId, int index, String ext) async {
    final token = await Secrets.get('githubToken');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = '${AppConfig.githubFolder}/$postId/${stamp}_$index.$ext';

    final response = await http.put(
      Uri.parse('https://api.github.com/repos/${AppConfig.githubOwner}'
          '/${AppConfig.githubRepo}/contents/$path'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'message': 'news image $postId',
        'content': base64Encode(bytes),
        'branch': AppConfig.githubBranch,
      }),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('فشل الرفع إلى GitHub (${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rawUrl = (data['content']?['download_url'] ?? '') as String;
    final url = AppConfig.useJsDelivr
        ? 'https://cdn.jsdelivr.net/gh/${AppConfig.githubOwner}'
            '/${AppConfig.githubRepo}@${AppConfig.githubBranch}/$path'
        : rawUrl;

    return UploadedImage(url, path);
  }

  /// رفع إلى ImgBB (بديل بسيط).
  static Future<UploadedImage> _toImgbb(
      Uint8List bytes, String postId, int index) async {
    final key = await Secrets.get('imgbbKey');
    final response = await http.post(
      Uri.parse('https://api.imgbb.com/1/upload'),
      body: {
        'key': key,
        'image': base64Encode(bytes),
        'name': '${postId}_$index',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('فشل الرفع إلى ImgBB (${response.statusCode})');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final info = data['data'] as Map<String, dynamic>;
    return UploadedImage(
      info['url'] as String,
      (info['delete_url'] ?? '') as String,
    );
  }

  /// رفع الفيديو — مسار مستقل عن الصور.
  /// jsDelivr تمنع استضافة الفيديو في شروطها، لذا نستخدم Supabase.
  static Future<UploadedImage> uploadVideo(
    Uint8List bytes,
    String postId,
    String ext,
    String contentType,
  ) async {
    switch (AppConfig.videoBackend) {
      case VideoBackend.supabase:
        return _videoToSupabase(bytes, postId, ext, contentType);
      case VideoBackend.firebaseStorage:
        return _toFirebase(bytes, postId, 0, ext, contentType);
      case VideoBackend.youtubeOnly:
        throw Exception('الرفع المباشر معطّل — استخدم رابط يوتيوب');
    }
  }

  static Future<UploadedImage> _videoToSupabase(
    Uint8List bytes,
    String postId,
    String ext,
    String contentType,
  ) async {
    if (AppConfig.supabaseUrl.contains('ضع_')) {
      throw Exception('لم تُضبط بيانات Supabase في app_config.dart');
    }
    final key = await Secrets.get('supabaseKey');
    final path = 'videos/$postId/${DateTime.now().millisecondsSinceEpoch}.$ext';

    final response = await http.post(
      Uri.parse(
          '${AppConfig.supabaseUrl}/storage/v1/object/${AppConfig.supabaseBucket}/$path'),
      headers: {
        'Authorization': 'Bearer $key',
        'apikey': key,
        'Content-Type': contentType,
        'x-upsert': 'true',
      },
      body: bytes,
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('فشل رفع الفيديو (${response.statusCode})');
    }

    final url = '${AppConfig.supabaseUrl}/storage/v1/object/public'
        '/${AppConfig.supabaseBucket}/$path';
    return UploadedImage(url, path);
  }

  static Future<UploadedImage> _toFirebase(Uint8List bytes, String postId,
      int index, String ext, String contentType) async {
    final path =
        '${AppConfig.storageFolder}/$postId/${DateTime.now().millisecondsSinceEpoch}_$index.$ext';
    final ref = Api.storage.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return UploadedImage(await ref.getDownloadURL(), path);
  }
}

// ===========================================================================
//  الإشعارات
//  داخل التطبيق: مراقبة الأخبار الجديدة لحظياً + شارة غير المقروء
//  خارج التطبيق: FCM عبر موضوع news (يُرسل من كونسول Firebase)
// ===========================================================================

class Notifications {
  Notifications._();

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  /// عدد الأخبار غير المقروءة — تستمع له أيقونة الجرس.
  static final ValueNotifier<int> unseen = ValueNotifier<int>(0);

  static DateTime _lastSeen = DateTime.fromMillisecondsSinceEpoch(0);
  static bool _enabled = true;
  static bool _firstSnapshot = true;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _postsSub;

  static const String _kLastSeen = 'notif_last_seen';
  static const String _kEnabled = 'notif_enabled';

  static bool get enabled => _enabled;
  static DateTime get lastSeen => _lastSeen;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_kEnabled) ?? true;
    _lastSeen =
        DateTime.fromMillisecondsSinceEpoch(prefs.getInt(_kLastSeen) ?? 0);

    if (!kIsWeb) {
      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
          macOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (response) =>
            openPost(response.payload),
      );

      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            AppConfig.notificationChannelId,
            'أخبار جديدة',
            description: 'إشعار عند نشر خبر جديد',
            importance: Importance.high,
          ));
    }

    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (_) {}

    await _applySubscription();

    FirebaseMessaging.onMessage.listen((message) {
      final n = message.notification;
      if (n != null && _enabled) {
        show(
            n.title ?? AppConfig.appName, n.body ?? '', message.data['postId']);
      }
    });
    FirebaseMessaging.onMessageOpenedApp
        .listen((message) => openPost(message.data['postId']));
  }

  static Future<void> _applySubscription() async {
    if (kIsWeb) return; // الاشتراك بالمواضيع غير مدعوم على الويب
    try {
      if (_enabled) {
        await FirebaseMessaging.instance.subscribeToTopic(AppConfig.newsTopic);
      } else {
        await FirebaseMessaging.instance
            .unsubscribeFromTopic(AppConfig.newsTopic);
      }
    } catch (_) {}
  }

  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, value);
    await _applySubscription();
  }

  /// يراقب آخر الأخبار ما دام التطبيق مفتوحاً.
  static void watchNewPosts() {
    _postsSub?.cancel();
    _firstSnapshot = true;
    _postsSub = Api.posts
        .orderBy('createdAt', descending: true)
        .limit(10)
        .snapshots()
        .listen((snap) {
      var count = 0;
      for (final d in snap.docs) {
        final created = (d.data()['createdAt'] as Timestamp?)?.toDate();
        if (created != null && created.isAfter(_lastSeen)) count++;
      }
      unseen.value = count;

      if (!_firstSnapshot && _enabled) {
        for (final change in snap.docChanges) {
          if (change.type != DocumentChangeType.added) continue;
          final data = change.doc.data() ?? {};
          final created = (data['createdAt'] as Timestamp?)?.toDate();
          if (created == null || !created.isAfter(_lastSeen)) continue;
          final text = (data['text'] ?? '') as String;
          show(
            'خبر جديد في ${AppConfig.appName}',
            text.length > 110 ? '${text.substring(0, 110)}…' : text,
            change.doc.id,
          );
        }
      }
      _firstSnapshot = false;
    });
  }

  static Future<void> markAllSeen() async {
    _lastSeen = DateTime.now();
    unseen.value = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastSeen, _lastSeen.millisecondsSinceEpoch);
  }

  static Future<void> show(String title, String body, String? postId) async {
    if (kIsWeb) return; // الويب يعرض إشعاراته عبر المتصفح
    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          AppConfig.notificationChannelId,
          'أخبار جديدة',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: postId,
    );
  }

  static void openPost(String? postId) {
    if (postId == null || postId.isEmpty) return;
    appNavigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => PostPage(postId: postId)),
    );
  }
}

// ===========================================================================
//  حظر المستخدمين — يُحفظ على الجهاز، ويخفي تعليقات من حظرهم المستخدم
// ===========================================================================

class Blocked {
  Blocked._();

  static const String _key = 'blocked_users';
  static Map<String, String> _users = {}; // uid -> الاسم

  static Map<String, String> get all => Map.unmodifiable(_users);
  static bool has(String uid) => _users.containsKey(uid);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      _users = Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      _users = {};
    }
  }

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_users));
  }

  static Future<void> block(String uid, String name) async {
    if (uid.isEmpty) return;
    _users[uid] = name;
    await _save();
  }

  static Future<void> unblock(String uid) async {
    _users.remove(uid);
    await _save();
  }
}

// ===========================================================================
//  نموذج المنشور
// ===========================================================================

class Post {
  final String id;
  final String text;
  final List<String> images;
  final List<String> imagePaths;
  final List<double> imageRatios;
  final String videoUrl;
  final String videoPath;
  final double videoRatio;
  final String youtubeId;
  final String category;
  final bool pinned;
  final String authorName;
  final int likesCount;
  final int commentsCount;
  final DateTime? createdAt;

  Post({
    required this.id,
    required this.text,
    required this.images,
    required this.imagePaths,
    required this.imageRatios,
    required this.videoUrl,
    required this.videoPath,
    required this.videoRatio,
    required this.youtubeId,
    required this.category,
    required this.pinned,
    required this.authorName,
    required this.likesCount,
    required this.commentsCount,
    required this.createdAt,
  });

  factory Post.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return Post(
      id: doc.id,
      text: (d['text'] ?? '') as String,
      images: List<String>.from(d['images'] ?? const []),
      imagePaths: List<String>.from(d['imagePaths'] ?? const []),
      imageRatios: ((d['imageRatios'] ?? const []) as List)
          .map((e) => (e as num).toDouble())
          .toList(),
      videoUrl: (d['videoUrl'] ?? '') as String,
      videoPath: (d['videoPath'] ?? '') as String,
      videoRatio: ((d['videoRatio'] as num?)?.toDouble() ?? 0) > 0
          ? (d['videoRatio'] as num).toDouble()
          : 16 / 9,
      youtubeId: (d['youtubeId'] ?? '') as String,
      category: (d['category'] ?? AppConfig.categories.first) as String,
      pinned: (d['pinned'] ?? false) as bool,
      authorName: (d['authorName'] ?? AppConfig.publisherName) as String,
      likesCount: (d['likesCount'] as num? ?? 0).toInt(),
      commentsCount: (d['commentsCount'] as num? ?? 0).toInt(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

// ===========================================================================
//  بوابة الدخول: تسجيل مجهول تلقائي ثم الواجهة
// ===========================================================================

const String _kWelcomeDone = 'welcome_done';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<bool> _boot = _bootstrap();
  bool _welcomeDismissed = false;

  /// يهيّئ الحساب، ويترك شاشة البداية ظاهرة مدة كافية لتُرى.
  Future<bool> _bootstrap() async {
    final results = await Future.wait<Object?>([
      _prepare(),
      Future<void>.delayed(const Duration(milliseconds: 1900)),
    ]);
    return results.first as bool;
  }

  Future<bool> _prepare() async {
    await Api.ensureSignedIn();
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_kWelcomeDone) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _boot,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SplashScreen();
        }
        if (snap.hasError) {
          return _ErrorView(
            message: 'تعذّر الاتصال بالخادم. تحقق من الإنترنت ثم أعد المحاولة.',
            onRetry: () => setState(() => _boot = _bootstrap()),
          );
        }
        final showWelcome = (snap.data ?? false) && !_welcomeDismissed;
        if (showWelcome) {
          return WelcomeScreen(
            onStart: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool(_kWelcomeDone, true);
              if (mounted) setState(() => _welcomeDismissed = true);
            },
          );
        }
        return const HomePage();
      },
    );
  }
}

// ===========================================================================
//  شاشة البداية
// ===========================================================================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..forward();

  late final AnimationController _halo = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat(reverse: true);

  late final Animation<double> _mark = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0, 0.55, curve: Curves.easeOutBack),
  );

  late final Animation<double> _title = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.3, 0.85, curve: Curves.easeOut),
  );

  late final Animation<double> _footer = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.6, 1, curve: Curves.easeOut),
  );

  @override
  void dispose() {
    _intro.dispose();
    _halo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF0A4FA8), Color(0xFF062E63), Color(0xFF041C3E)],
            stops: [0, 0.55, 1],
          ),
        ),
        // fit: StackFit.expand ضروري — بدونه يلتصق المحتوى بالحافة اليمنى في RTL
        child: Stack(
          fit: StackFit.expand,
          children: [
            // هالة ضوئية بطيئة خلف الشعار
            AnimatedBuilder(
              animation: _halo,
              builder: (context, _) => Align(
                alignment: const Alignment(0, -0.28),
                child: Container(
                  width: 320 + _halo.value * 46,
                  height: 320 + _halo.value * 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color.fromRGBO(90, 160, 255, 0.20 + _halo.value * 0.08),
                        const Color.fromRGBO(10, 79, 168, 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            Column(
              children: [
                const Spacer(flex: 3),
                ScaleTransition(
                  scale: _mark,
                  child: FadeTransition(
                    opacity: _mark,
                    child: Container(
                      width: 126,
                      height: 126,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(38),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x59000B1F),
                            blurRadius: 42,
                            offset: Offset(0, 18),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: ShaderMask(
                        shaderCallback: (rect) => const LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [AppConfig.primary, Color(0xFF062E63)],
                        ).createShader(rect),
                        child: const Icon(Icons.campaign_rounded,
                            size: 68, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 34),
                FadeTransition(
                  opacity: _title,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.4),
                      end: Offset.zero,
                    ).animate(_title),
                    child: Column(
                      children: [
                        Text(
                          AppConfig.appName,
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: 54,
                          height: 2,
                          color: const Color(0x8FFFFFFF),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          AppConfig.tagline,
                          style: TextStyle(
                            fontSize: 15,
                            color: Color(0xCCE8F1FD),
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(flex: 4),
                FadeTransition(
                  opacity: _footer,
                  child: Column(
                    children: [
                      SizedBox(
                        width: 130,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: const LinearProgressIndicator(
                            minHeight: 2.5,
                            backgroundColor: Color(0x33FFFFFF),
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'تطوير ${AppConfig.developer}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0x8FFFFFFF),
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 34),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
//  شاشة الترحيب — أول تشغيل فقط
// ===========================================================================

class WelcomeScreen extends StatelessWidget {
  final Future<void> Function() onStart;
  const WelcomeScreen({super.key, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConfig.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(26, 30, 26, 26),
              shrinkWrap: true,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 34),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [AppConfig.primary, AppConfig.primaryDark],
                    ),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.campaign_rounded,
                          size: 62, color: Colors.white),
                      const SizedBox(height: 14),
                      Text(
                        AppConfig.appName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'كل ما يجري في ${AppConfig.regionName}، في مكان واحد',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                const _WelcomeRow(
                  icon: Icons.verified_rounded,
                  title: 'أخبار موثوقة',
                  body: 'ينشرها فريق التحرير، بلا إشاعات ولا حسابات مجهولة.',
                ),
                const _WelcomeRow(
                  icon: Icons.forum_rounded,
                  title: 'شارك رأيك',
                  body: 'علّق وتفاعل مع أهل منطقتك على كل خبر.',
                ),
                const _WelcomeRow(
                  icon: Icons.notifications_active_rounded,
                  title: 'لا يفوتك جديد',
                  body: 'إشعار فوري لحظة نشر أي خبر مهم.',
                ),
                const SizedBox(height: 30),
                FilledButton(
                  onPressed: onStart,
                  child: const Text('ابدأ التصفح'),
                ),
                const SizedBox(height: 14),
                Text(
                  'تطوير ${AppConfig.developer}',
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 12, color: AppConfig.textSoft),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _WelcomeRow(
      {required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppConfig.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppConfig.primary, size: 23),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(body,
                    style: const TextStyle(
                        fontSize: 13.5,
                        color: AppConfig.textSoft,
                        height: 1.6)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppConfig.primary, AppConfig.primaryDark],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      alignment: Alignment.center,
      child:
          Icon(Icons.campaign_rounded, color: Colors.white, size: size * 0.55),
    );
  }
}

// ===========================================================================
//  الصفحة الرئيسية (الخلاصة)
// ===========================================================================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _category = AppConfig.allCategory;
  int _limit = AppConfig.pageSize;
  String _search = '';
  bool _searching = false;
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Notifications.watchNewPosts();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 400) {
        if (_limit < 200) {
          setState(() => _limit += AppConfig.pageSize);
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: Api.isAdminStream(),
      builder: (context, adminSnap) {
        final isAdmin = adminSnap.data ?? false;

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            title: _searching
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'ابحث في الأخبار',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (v) => setState(() => _search = v.trim()),
                  )
                : Row(
                    children: [
                      const AppLogo(size: 34),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text(AppConfig.appName,
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800)),
                          Text(AppConfig.tagline,
                              style: TextStyle(
                                  fontSize: 11, color: AppConfig.textSoft)),
                        ],
                      ),
                    ],
                  ),
            actions: [
              IconButton(
                tooltip: _searching ? 'إغلاق البحث' : 'بحث',
                icon: Icon(
                    _searching ? Icons.close_rounded : Icons.search_rounded),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  _search = '';
                  _searchController.clear();
                }),
              ),
              ValueListenableBuilder<int>(
                valueListenable: Notifications.unseen,
                builder: (context, count, _) => Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      tooltip: 'الإشعارات',
                      icon: const Icon(Icons.notifications_none_rounded),
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => NotificationsPage(isAdmin: isAdmin),
                          ),
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                    if (count > 0)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppConfig.danger,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          constraints: const BoxConstraints(minWidth: 17),
                          child: Text(
                            count > 9 ? '+9' : '$count',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: isAdmin ? 'لوحة الإدارة' : 'حسابي',
                icon: Icon(isAdmin
                    ? Icons.admin_panel_settings_rounded
                    : Icons.person_rounded),
                onPressed: () => _openAccountSheet(isAdmin),
              ),
              const SizedBox(width: 4),
            ],
            bottom: _searching
                ? null
                : PreferredSize(
                    preferredSize: const Size.fromHeight(52),
                    child: _CategoryBar(
                      selected: _category,
                      onSelect: (c) => setState(() {
                        _category = c;
                        _limit = AppConfig.pageSize;
                      }),
                    ),
                  ),
          ),
          floatingActionButton: isAdmin
              ? FloatingActionButton.extended(
                  backgroundColor: AppConfig.primary,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('خبر جديد',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ComposePage()),
                  ),
                )
              : null,
          body: _buildFeed(isAdmin),
        );
      },
    );
  }

  Widget _buildFeed(bool isAdmin) {
    // عند اختيار تصنيف نجلب عدداً أكبر لأن الفلترة تتم بعد الجلب
    final fetchLimit = _category == AppConfig.allCategory ? _limit : _limit * 5;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: Api.postsQuery(limit: fetchLimit).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorView(
            message: 'تعذّر تحميل الأخبار. تحقق من الاتصال بالإنترنت.',
            onRetry: () => setState(() {}),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var posts = snapshot.data!.docs.map(Post.fromDoc).toList();

        if (_category != AppConfig.allCategory) {
          posts = posts.where((p) => p.category == _category).toList();
        }

        if (_search.isNotEmpty) {
          posts = posts
              .where(
                  (p) => p.text.toLowerCase().contains(_search.toLowerCase()))
              .toList();
        }
        // المثبّت أولاً
        posts.sort((a, b) {
          if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
          final ad = a.createdAt ?? DateTime(1970);
          final bd = b.createdAt ?? DateTime(1970);
          return bd.compareTo(ad);
        });

        if (posts.isEmpty) {
          return _EmptyView(
            isAdmin: isAdmin,
            searching: _search.isNotEmpty,
            category: _category == AppConfig.allCategory ? '' : _category,
          );
        }

        return RefreshIndicator(
          onRefresh: () async => setState(() => _limit = AppConfig.pageSize),
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 90),
            itemCount: posts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: PostCard(post: posts[i], isAdmin: isAdmin),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الحساب'),
        content: const Text(
          'سيُحذف حسابك وتعليقاتك نهائياً، ولا يمكن التراجع.\n'
          'يمكنك التصفح بعدها كزائر.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف نهائياً',
                style: TextStyle(color: AppConfig.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await Api.deleteAccount();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حُذف حسابك')),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'requires-recent-login') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لأمانك، سجّل الدخول من جديد ثم أعد المحاولة'),
            duration: Duration(seconds: 5),
          ),
        );
        await Api.signOut();
        if (mounted) setState(() {});
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر حذف الحساب. حاول لاحقاً')),
        );
      }
    }
  }

  Future<void> _openAccountSheet(bool isAdmin) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppConfig.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppConfig.line,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 14),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppConfig.primarySoft,
                backgroundImage: Api.photoUrl.isNotEmpty
                    ? CachedNetworkImageProvider(Api.photoUrl)
                    : null,
                child: Api.photoUrl.isNotEmpty
                    ? null
                    : Icon(
                        isAdmin
                            ? Icons.verified_user_rounded
                            : Icons.person_rounded,
                        color: AppConfig.primary,
                      ),
              ),
              title: Text(isAdmin ? 'مدير التطبيق' : Api.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                isAdmin
                    ? Api.user?.email ?? ''
                    : Api.isGuest
                        ? 'تصفّح كزائر'
                        : Api.user?.email ?? 'حساب Google',
              ),
            ),
            const Divider(),
            if (Api.isGuest)
              ListTile(
                leading: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppConfig.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppConfig.line),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'G',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: Color(0xFF4285F4),
                    ),
                  ),
                ),
                title: const Text('تسجيل الدخول بحساب Google',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('ليظهر اسمك وصورتك في التعليقات'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  try {
                    await Api.signInWithGoogle();
                  } catch (_) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('تعذّر تسجيل الدخول. حاول مرة أخرى')),
                      );
                    }
                  }
                  if (mounted) setState(() {});
                },
              ),
            if (!isAdmin && Api.isGuest)
              ListTile(
                leading: const Icon(Icons.badge_rounded),
                title: const Text('تغيير اسمي في التعليقات'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _askForName(context);
                  if (mounted) setState(() {});
                },
              ),
            if (!isAdmin && Api.isGuest)
              ListTile(
                leading: const Icon(Icons.lock_rounded),
                title: const Text('دخول الإدارة'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminLoginPage()),
                  );
                },
              ),
            if (!Api.isGuest)
              ListTile(
                leading:
                    const Icon(Icons.logout_rounded, color: AppConfig.danger),
                title: const Text('تسجيل الخروج',
                    style: TextStyle(color: AppConfig.danger)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await Api.signOut();
                  if (mounted) setState(() {});
                },
              ),
            if (isAdmin)
              ListTile(
                leading: const Icon(Icons.flag_rounded),
                title: const Text('البلاغات الواردة'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ReportsPage()),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.block_rounded),
              title: const Text('المستخدمون المحظورون'),
              subtitle: Text('${Blocked.all.length}'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BlockedPage()),
                );
                if (mounted) setState(() {});
              },
            ),
            StatefulBuilder(
              builder: (context, setSheetState) => SwitchListTile(
                secondary: const Icon(Icons.notifications_active_rounded),
                title: const Text('إشعارات الأخبار الجديدة'),
                value: Notifications.enabled,
                onChanged: (v) async {
                  await Notifications.setEnabled(v);
                  setSheetState(() {});
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('سياسة الخصوصية'),
              onTap: () {
                Navigator.pop(sheetContext);
                launchUrl(Uri.parse(AppConfig.privacyPolicyUrl),
                    mode: LaunchMode.externalApplication);
              },
            ),
            if (!Api.isGuest)
              ListTile(
                leading: const Icon(Icons.person_remove_rounded,
                    color: AppConfig.danger),
                title: const Text('حذف حسابي نهائياً',
                    style: TextStyle(color: AppConfig.danger)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _confirmDeleteAccount();
                },
              ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('عن التطبيق'),
              onTap: () {
                Navigator.pop(sheetContext);
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    icon: const AppLogo(size: 52),
                    title: const Text(AppConfig.appName,
                        textAlign: TextAlign.center),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'تطبيق أخبار منطقة ${AppConfig.regionName}. '
                          'النشر من الإدارة، والتفاعل للجميع.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(height: 1.7),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'الإصدار 1.0.0',
                          style: TextStyle(
                              fontSize: 12.5, color: AppConfig.textSoft),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'تطوير ${AppConfig.developer}',
                          style: TextStyle(
                              fontSize: 12.5, color: AppConfig.textSoft),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('إغلاق'),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _CategoryBar({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final items = [AppConfig.allCategory, ...AppConfig.categories];
    return Container(
      height: 52,
      alignment: Alignment.centerRight,
      decoration: const BoxDecoration(
        color: AppConfig.surface,
        border: Border(bottom: BorderSide(color: AppConfig.line)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = items[i];
          final isSel = c == selected;
          return InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: () => onSelect(c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSel ? AppConfig.primary : AppConfig.primarySoft,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                c,
                style: TextStyle(
                  color: isSel ? Colors.white : AppConfig.primaryDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ===========================================================================
//  بطاقة المنشور
// ===========================================================================

class PostCard extends StatefulWidget {
  final Post post;
  final bool isAdmin;
  final bool expanded;

  const PostCard({
    super.key,
    required this.post,
    required this.isAdmin,
    this.expanded = false,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final showAll = _showAll || widget.expanded;
    final isLong = p.text.length > 240;

    return Container(
      decoration: const BoxDecoration(
        color: AppConfig.surface,
        border: Border(
          top: BorderSide(color: AppConfig.line),
          bottom: BorderSide(color: AppConfig.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // رأس البطاقة
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
            child: Row(
              children: [
                const AppLogo(size: 42),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              p.authorName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 15),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.verified_rounded,
                              size: 16, color: AppConfig.primary),
                          if (p.pinned) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.push_pin_rounded,
                                size: 15, color: AppConfig.textSoft),
                          ],
                        ],
                      ),
                      Row(
                        children: [
                          Text(timeAgo(p.createdAt),
                              style: const TextStyle(
                                  fontSize: 12, color: AppConfig.textSoft)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppConfig.primarySoft,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              p.category,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppConfig.primaryDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (widget.isAdmin)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz_rounded,
                        color: AppConfig.textSoft),
                    onSelected: (v) => _onAdminAction(v),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'pin',
                        child: Text(
                            p.pinned ? 'إلغاء التثبيت' : 'تثبيت في الأعلى'),
                      ),
                      const PopupMenuItem(
                          value: 'edit', child: Text('تعديل النص')),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('حذف المنشور',
                            style: TextStyle(color: AppConfig.danger)),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // النص
          if (p.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    showAll || !isLong
                        ? p.text
                        : '${p.text.substring(0, 240)}…',
                    style: const TextStyle(
                        fontSize: 15.5,
                        height: 1.75,
                        color: AppConfig.textStrong),
                  ),
                  if (isLong && !showAll)
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => setState(() => _showAll = true),
                      child: const Text('قراءة الخبر كاملاً'),
                    ),
                ],
              ),
            ),

          // الصور
          if (p.videoUrl.isNotEmpty)
            PostVideo(url: p.videoUrl, ratio: p.videoRatio)
          else if (p.youtubeId.isNotEmpty)
            YoutubeCard(videoId: p.youtubeId)
          else if (p.images.isNotEmpty)
            PostImages(images: p.images, ratios: p.imageRatios),

          // العدادات
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(
              children: [
                if (p.likesCount > 0) ...[
                  const Icon(Icons.favorite_rounded,
                      size: 15, color: AppConfig.primary),
                  const SizedBox(width: 4),
                  Text('${p.likesCount}',
                      style: const TextStyle(
                          fontSize: 12.5, color: AppConfig.textSoft)),
                ],
                const Spacer(),
                if (p.commentsCount > 0)
                  Text('${p.commentsCount} تعليق',
                      style: const TextStyle(
                          fontSize: 12.5, color: AppConfig.textSoft)),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Divider(height: 1),
          ),

          // الأزرار
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: StreamBuilder<bool>(
                    stream: Api.likedStream(p.id),
                    builder: (context, snap) {
                      final liked = snap.data ?? false;
                      return _ActionButton(
                        icon: liked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        label: 'إعجاب',
                        active: liked,
                        onTap: () => Api.toggleLike(p.id),
                      );
                    },
                  ),
                ),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.mode_comment_outlined,
                    label: 'تعليق',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            PostPage(postId: p.id, isAdmin: widget.isAdmin),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.copy_rounded,
                    label: 'نسخ',
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: p.text));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('نُسخ نص الخبر')),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onAdminAction(String value) async {
    final p = widget.post;
    if (value == 'pin') {
      await Api.posts.doc(p.id).update({'pinned': !p.pinned});
    } else if (value == 'edit') {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ComposePage(editing: p)),
      );
    } else if (value == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('حذف المنشور'),
          content: const Text('سيُحذف الخبر مع صوره وتعليقاته نهائياً.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('تراجع')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('حذف', style: TextStyle(color: AppConfig.danger)),
            ),
          ],
        ),
      );
      if (ok == true) {
        await Api.deletePost(p.id, p.imagePaths);
      }
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppConfig.primary : AppConfig.textSoft;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 13.5)),
          ],
        ),
      ),
    );
  }
}

/// يقرأ أبعاد الصورة قبل الرفع ليعرضها التطبيق بنسبتها الحقيقية.
Future<double> imageRatio(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final w = frame.image.width;
    final h = frame.image.height;
    frame.image.dispose();
    codec.dispose();
    if (h == 0) return 4 / 3;
    return w / h;
  } catch (_) {
    return 4 / 3;
  }
}

/// حدود العرض: لا أعرض من بانوراما عريضة ولا أطول من صورة عمودية.
double clampRatio(double r) => r.clamp(0.62, 1.91);

class PostImages extends StatefulWidget {
  final List<String> images;
  final List<double> ratios;
  const PostImages({super.key, required this.images, this.ratios = const []});

  @override
  State<PostImages> createState() => _PostImagesState();
}

class _PostImagesState extends State<PostImages> {
  final _controller = PageController();
  int _index = 0;
  double? _measuredRatio;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    // الأخبار القديمة لا تحمل الأبعاد، فنقيسها من الصورة نفسها.
    if (widget.ratios.isEmpty && widget.images.isNotEmpty) {
      _measureFirstImage();
    }
  }

  void _measureFirstImage() {
    final provider = CachedNetworkImageProvider(widget.images.first);
    final stream = provider.resolve(const ImageConfiguration());
    final listener = ImageStreamListener(
      (info, _) {
        final r = info.image.width / info.image.height;
        if (mounted) setState(() => _measuredRatio = r);
      },
      onError: (_, __) {},
    );
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  double get _displayRatio {
    if (widget.ratios.isNotEmpty) {
      final sum = widget.ratios.fold<double>(0, (a, b) => a + b);
      return clampRatio(sum / widget.ratios.length);
    }
    return clampRatio(_measuredRatio ?? 4 / 3);
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final single = widget.images.length == 1;

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          color: AppConfig.primarySoft,
          child: AspectRatio(
            aspectRatio: _displayRatio,
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ImageViewer(images: widget.images, initialIndex: i),
                  ),
                ),
                child: CachedNetworkImage(
                  imageUrl: widget.images[i],
                  // صورة واحدة: نعرضها كاملة بنسبتها.
                  // عدة صور: نملأ الإطار الموحّد حتى لا يتغيّر الارتفاع.
                  fit: single ? BoxFit.contain : BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: AppConfig.primarySoft,
                    child: const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: AppConfig.primarySoft,
                    child: const Icon(Icons.broken_image_rounded,
                        color: AppConfig.textSoft),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.images.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(widget.images.length, (i) {
                final sel = i == _index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: sel ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: sel ? Colors.white : Colors.white70,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 3),
                    ],
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

/// مشغّل فيديو داخل بطاقة الخبر.
/// لا يبدأ التحميل إلا عند ضغط المستخدم — متصفحات الجوال (خاصة سفاري)
/// ترفض تحميل الفيديو تلقائياً، فينتظر التطبيق إلى ما لا نهاية.
class PostVideo extends StatefulWidget {
  final String url;
  final double ratio;
  const PostVideo({super.key, required this.url, this.ratio = 16 / 9});

  @override
  State<PostVideo> createState() => _PostVideoState();
}

class _PostVideoState extends State<PostVideo> {
  VideoPlayerController? _controller;
  bool _loading = false;
  bool _failed = false;

  Future<void> _onTap() async {
    final c = _controller;
    if (c != null && c.value.isInitialized) {
      setState(() => c.value.isPlaying ? c.pause() : c.play());
      return;
    }
    if (_loading) return;

    setState(() {
      _loading = true;
      _failed = false;
    });

    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await controller.initialize().timeout(const Duration(seconds: 30));
      await controller.setLooping(true);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
      await controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      await controller.dispose();
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;

    final targetRatio =
        ready ? clampRatio(c.value.aspectRatio) : clampRatio(widget.ratio);

    return GestureDetector(
      onTap: _onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: targetRatio, end: targetRatio),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        builder: (context, ratio, child) =>
            AspectRatio(aspectRatio: ratio, child: child),
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            if (ready)
              VideoPlayer(c)
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF16324F), Color(0xFF0B2136)],
                  ),
                ),
              ),

            // زر التشغيل أو مؤشر التحميل
            if (!ready || !c.value.isPlaying)
              Center(
                child: _loading
                    ? const SizedBox(
                        width: 34,
                        height: 34,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.6, color: Colors.white),
                      )
                    : Container(
                        width: 66,
                        height: 66,
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(130),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24, width: 1.5),
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 40),
                      ),
              ),

            if (!ready && !_loading && !_failed)
              const Positioned(
                bottom: 12,
                child: Text(
                  'اضغط لتشغيل الفيديو',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ),

            if (_failed)
              Positioned(
                bottom: 10,
                child: TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(widget.url),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded,
                      size: 16, color: Colors.white),
                  label: const Text('تعذّر التشغيل — افتحه في المتصفح',
                      style: TextStyle(color: Colors.white, fontSize: 12.5)),
                ),
              ),

            if (ready)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: VideoProgressIndicator(
                  c,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: AppConfig.primary,
                    bufferedColor: Colors.white54,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ),

            if (ready)
              Positioned(
                bottom: 10,
                left: 10,
                child: InkWell(
                  onTap: () =>
                      setState(() => c.setVolume(c.value.volume > 0 ? 0 : 1)),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.black45,
                    child: Icon(
                      c.value.volume > 0
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      color: Colors.white,
                      size: 17,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// بطاقة فيديو يوتيوب — صورة مصغّرة تفتح الفيديو في تطبيق يوتيوب.
class YoutubeCard extends StatelessWidget {
  final String videoId;
  const YoutubeCard({super.key, required this.videoId});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => launchUrl(
        Uri.parse('https://www.youtube.com/watch?v=$videoId'),
        mode: LaunchMode.externalApplication,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: CachedNetworkImage(
              imageUrl: 'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: AppConfig.primarySoft),
              errorWidget: (_, __, ___) =>
                  Container(color: AppConfig.primarySoft),
            ),
          ),
          Container(
            width: 66,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFCC0000),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.play_arrow_rounded,
                color: Colors.white, size: 34),
          ),
        ],
      ),
    );
  }
}

/// امتداد ملف الفيديو كما هو، لا كما نفترض.
String videoExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return 'mp4';
  final ext = fileName.substring(dot + 1).toLowerCase();
  const known = {'mp4', 'mov', 'm4v', 'webm', '3gp', 'mkv'};
  return known.contains(ext) ? ext : 'mp4';
}

String videoMime(String ext) {
  switch (ext) {
    case 'mov':
      return 'video/quicktime';
    case 'webm':
      return 'video/webm';
    case '3gp':
      return 'video/3gpp';
    case 'mkv':
      return 'video/x-matroska';
    default:
      return 'video/mp4';
  }
}

/// يستخرج معرّف فيديو يوتيوب من أي صيغة رابط.
String extractYoutubeId(String input) {
  final url = input.trim();
  if (url.isEmpty) return '';
  final patterns = [
    RegExp(r'youtu\.be/([A-Za-z0-9_-]{11})'),
    RegExp(r'[?&]v=([A-Za-z0-9_-]{11})'),
    RegExp(r'youtube\.com/(?:embed|shorts|live)/([A-Za-z0-9_-]{11})'),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(url);
    if (m != null) return m.group(1)!;
  }
  if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(url)) return url;
  return '';
}

class ImageViewer extends StatelessWidget {
  final List<String> images;
  final int initialIndex;
  const ImageViewer({super.key, required this.images, this.initialIndex = 0});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: images.length,
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: CachedNetworkImage(
              imageUrl: images[i],
              fit: BoxFit.contain,
              placeholder: (_, __) =>
                  const CircularProgressIndicator(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
//  صفحة المنشور + التعليقات
// ===========================================================================

class PostPage extends StatefulWidget {
  final String postId;
  final bool isAdmin;
  const PostPage({super.key, required this.postId, this.isAdmin = false});

  @override
  State<PostPage> createState() => _PostPageState();
}

class _PostPageState extends State<PostPage> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _reportComment(
      String commentId, String uid, String name, String text) async {
    final reason = await showReasonSheet(context);
    if (reason == null) return;
    try {
      await Api.reportContent(
        type: 'comment',
        postId: widget.postId,
        commentId: commentId,
        reportedUid: uid,
        reportedName: name,
        snippet: text,
        reason: reason,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('وصلنا بلاغك، وسيراجعه فريق الإدارة')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر إرسال البلاغ')),
        );
      }
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    if ((Api.user?.displayName ?? '').trim().isEmpty) {
      final name = await _askForName(context);
      if (name == null) return;
    }

    setState(() => _sending = true);
    try {
      await Api.addComment(widget.postId, text);
      _controller.clear();
      FocusScope.of(context).unfocus();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لم يُرسل التعليق. حاول مرة أخرى.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الخبر والتعليقات')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: Api.posts.doc(widget.postId).snapshots(),
              builder: (context, postSnap) {
                if (!postSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!postSnap.data!.exists) {
                  return const Center(child: Text('هذا الخبر لم يعد متاحاً.'));
                }
                final post = Post.fromDoc(postSnap.data!);

                return ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: PostCard(
                            post: post,
                            isAdmin: widget.isAdmin,
                            expanded: true),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'التعليقات (${post.commentsCount})',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 15),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: Api.commentsStream(widget.postId),
                      builder: (context, cSnap) {
                        if (!cSnap.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final docs = cSnap.data!.docs;
                        if (docs.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 28),
                            child: Center(
                              child: Text('كن أول من يعلّق على هذا الخبر',
                                  style: TextStyle(color: AppConfig.textSoft)),
                            ),
                          );
                        }
                        final visible = docs
                            .where((d) =>
                                !Blocked.has((d.data()['uid'] ?? '') as String))
                            .toList();

                        if (visible.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text('التعليقات المعروضة مخفية بالحظر',
                                  style: TextStyle(color: AppConfig.textSoft)),
                            ),
                          );
                        }

                        return Column(
                          children: visible.map((d) {
                            final data = d.data();
                            final uid = (data['uid'] ?? '') as String;
                            final name = (data['name'] ?? 'زائر') as String;
                            final text = (data['text'] ?? '') as String;
                            final mine = uid == Api.uid;
                            return Center(
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 680),
                                child: _CommentTile(
                                  uid: uid,
                                  name: name,
                                  photo: (data['photo'] ?? '') as String,
                                  text: text,
                                  date: (data['createdAt'] as Timestamp?)
                                      ?.toDate(),
                                  canDelete: mine || widget.isAdmin,
                                  isMine: mine,
                                  onDelete: () =>
                                      Api.deleteComment(widget.postId, d.id),
                                  onReport: () =>
                                      _reportComment(d.id, uid, name, text),
                                  onBlock: () async {
                                    await Blocked.block(uid, name);
                                    if (mounted) {
                                      setState(() {});
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              'حُظر $name — لن ترى تعليقاته'),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: const BoxDecoration(
                color: AppConfig.surface,
                border: Border(top: BorderSide(color: AppConfig.line)),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          maxLength: AppConfig.maxCommentLength,
                          minLines: 1,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            hintText: 'اكتب تعليقك',
                            counterText: '',
                            fillColor: AppConfig.background,
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: AppConfig.primary,
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: _sending ? null : _send,
                        icon: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send_rounded,
                                color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final String uid;
  final String name;
  final String photo;
  final String text;
  final DateTime? date;
  final bool canDelete;
  final bool isMine;
  final VoidCallback onDelete;
  final VoidCallback onReport;
  final VoidCallback onBlock;

  const _CommentTile({
    required this.uid,
    required this.name,
    required this.photo,
    required this.text,
    required this.date,
    required this.canDelete,
    required this.isMine,
    required this.onDelete,
    required this.onReport,
    required this.onBlock,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppConfig.primarySoft,
            backgroundImage:
                photo.isNotEmpty ? CachedNetworkImageProvider(photo) : null,
            child: photo.isNotEmpty
                ? null
                : Text(
                    name.trim().isEmpty ? '؟' : name.trim().substring(0, 1),
                    style: const TextStyle(
                        color: AppConfig.primaryDark,
                        fontWeight: FontWeight.w800),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
              decoration: BoxDecoration(
                color: AppConfig.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppConfig.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 13.5)),
                      ),
                      Text(timeAgo(date),
                          style: const TextStyle(
                              fontSize: 11, color: AppConfig.textSoft)),
                      SizedBox(
                        width: 34,
                        height: 30,
                        child: PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.more_horiz_rounded,
                              size: 18, color: AppConfig.textSoft),
                          onSelected: (value) {
                            switch (value) {
                              case 'report':
                                onReport();
                              case 'block':
                                onBlock();
                              case 'delete':
                                onDelete();
                            }
                          },
                          itemBuilder: (_) => [
                            if (!isMine)
                              const PopupMenuItem(
                                value: 'report',
                                child: Row(
                                  children: [
                                    Icon(Icons.flag_outlined, size: 18),
                                    SizedBox(width: 10),
                                    Text('إبلاغ عن التعليق'),
                                  ],
                                ),
                              ),
                            if (!isMine)
                              const PopupMenuItem(
                                value: 'block',
                                child: Row(
                                  children: [
                                    Icon(Icons.block_rounded, size: 18),
                                    SizedBox(width: 10),
                                    Text('حظر هذا المستخدم'),
                                  ],
                                ),
                              ),
                            if (canDelete)
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline_rounded,
                                        size: 18, color: AppConfig.danger),
                                    SizedBox(width: 10),
                                    Text('حذف التعليق',
                                        style:
                                            TextStyle(color: AppConfig.danger)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(text,
                        style: const TextStyle(fontSize: 14.5, height: 1.6)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// نافذة اختيار سبب الإبلاغ.
Future<String?> showReasonSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppConfig.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          const Text('سبب الإبلاغ',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          const Text('يراجع فريق الإدارة كل بلاغ',
              style: TextStyle(fontSize: 12.5, color: AppConfig.textSoft)),
          const SizedBox(height: 10),
          const Divider(),
          ...AppConfig.reportReasons.map(
            (r) => ListTile(
              title: Text(r, style: const TextStyle(fontSize: 14.5)),
              trailing: const Icon(Icons.chevron_left_rounded,
                  color: AppConfig.textSoft),
              onTap: () => Navigator.pop(ctx, r),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
}

// ===========================================================================
//  صفحة النشر (للأدمن)
// ===========================================================================

class ComposePage extends StatefulWidget {
  final Post? editing;
  const ComposePage({super.key, this.editing});

  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  final _textController = TextEditingController();
  final _picker = ImagePicker();
  final List<XFile> _images = [];
  final List<Uint8List> _previews = [];
  final _youtubeController = TextEditingController();
  XFile? _video;
  String _videoName = '';
  bool _processingVideo = false;
  double _videoProgress = 0;
  double _videoRatio = 16 / 9;
  String _category = AppConfig.categories.first;
  bool _pinned = false;
  bool _publishing = false;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _textController.text = e.text;
      _category = AppConfig.categories.contains(e.category)
          ? e.category
          : AppConfig.categories.first;
      _pinned = e.pinned;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _youtubeController.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final picked = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );
    if (picked == null) return;
    XFile file = picked;

    // على الجوال نحوّل الفيديو إلى mp4/H.264 ليعمل على كل الأجهزة والمتصفحات
    if (!kIsWeb) {
      setState(() {
        _processingVideo = true;
        _videoProgress = 0;
      });
      final sub = VideoCompress.compressProgress$.subscribe((p) {
        if (mounted) setState(() => _videoProgress = p / 100);
      });
      try {
        final info = await VideoCompress.compressVideo(
          file.path,
          quality: VideoQuality.MediumQuality,
          deleteOrigin: false,
          includeAudio: true,
        );
        if (info?.path != null) {
          file = XFile(info!.path!);
          final w = (info.width ?? 0).toDouble();
          final h = (info.height ?? 0).toDouble();
          final rotation = info.orientation ?? 0;
          if (w > 0 && h > 0) {
            // المقاطع العمودية تُسجَّل أفقياً مع علامة دوران،
            // فنقلب الأبعاد لتظهر البطاقة بمقاسها الحقيقي
            final rotated = rotation == 90 || rotation == 270;
            _videoRatio = rotated ? h / w : w / h;
          }
        }
      } catch (_) {
        // نكمل بالملف الأصلي إن فشل التحويل
      } finally {
        sub.unsubscribe();
        if (mounted) setState(() => _processingVideo = false);
      }
    }

    final sizeMB = (await file.length()) / (1024 * 1024);
    if (sizeMB > AppConfig.maxVideoMB) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'الفيديو ${sizeMB.toStringAsFixed(1)} ميغا بعد الضغط. '
                'الحد ${AppConfig.maxVideoMB} ميغا — اقتصّه أو ضع رابط يوتيوب.'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      return;
    }

    setState(() {
      _video = file;
      _videoName = file.name;
      _images.clear();
      _previews.clear();
    });

    if (videoExtension(file.name) != 'mp4' && mounted) {
      setState(() {
        _video = null;
        _videoName = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّر تحويل هذا المقطع إلى صيغة متوافقة. '
              'ارفعه على يوتيوب والصق الرابط.'),
          duration: Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _pickImages() async {
    final remaining = AppConfig.maxImagesPerPost - _images.length;
    if (remaining <= 0) return;
    final picked =
        await _picker.pickMultiImage(imageQuality: 82, maxWidth: 1600);
    if (picked.isEmpty) return;
    for (final f in picked.take(remaining)) {
      final bytes = await f.readAsBytes();
      _images.add(f);
      _previews.add(Uint8List.fromList(bytes));
    }
    if (mounted) setState(() {});
  }

  Future<void> _publish() async {
    final text = _textController.text.trim();
    final youtubeId = extractYoutubeId(_youtubeController.text);
    if (_youtubeController.text.trim().isNotEmpty && youtubeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رابط يوتيوب غير صحيح')),
      );
      return;
    }
    if (text.isEmpty &&
        _images.isEmpty &&
        _video == null &&
        youtubeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('أضف نص الخبر أو صورة أو فيديو قبل النشر')),
      );
      return;
    }

    setState(() => _publishing = true);
    try {
      if (_isEditing) {
        await Api.updatePost(widget.editing!.id,
            text: text, category: _category, pinned: _pinned);
      } else {
        await Api.createPost(
          text: text,
          category: _category,
          pinned: _pinned,
          images: _images,
          video: _video,
          videoRatio: _videoRatio,
          youtubeId: extractYoutubeId(_youtubeController.text),
        );
      }
      if (!kIsWeb && _video != null) {
        try {
          await VideoCompress.deleteAllCache();
        } catch (_) {}
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEditing ? 'حُفظ التعديل' : 'نُشر الخبر')),
        );
      }
    } catch (e) {
      if (mounted) {
        final message = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message.length > 140
                ? 'فشل النشر. تحقق من الاتصال والصلاحيات.'
                : message),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'تعديل الخبر' : 'نشر خبر جديد')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _textController,
                maxLines: 10,
                minLines: 6,
                maxLength: AppConfig.maxPostLength,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: 'اكتب تفاصيل الخبر…',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
              const Text('التصنيف',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AppConfig.categories.map((c) {
                  final sel = c == _category;
                  return ChoiceChip(
                    label: Text(c),
                    selected: sel,
                    onSelected: (_) => setState(() => _category = c),
                    selectedColor: AppConfig.primary,
                    backgroundColor: AppConfig.primarySoft,
                    labelStyle: TextStyle(
                      color: sel ? Colors.white : AppConfig.primaryDark,
                      fontWeight: FontWeight.w700,
                    ),
                    side: BorderSide.none,
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _pinned,
                onChanged: (v) => setState(() => _pinned = v),
                title: const Text('تثبيت الخبر في أعلى الصفحة'),
                contentPadding: EdgeInsets.zero,
              ),
              if (!_isEditing) ...[
                const Divider(height: 24),
                Row(
                  children: [
                    const Text('الصور',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Text('${_images.length}/${AppConfig.maxImagesPerPost}',
                        style: const TextStyle(color: AppConfig.textSoft)),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 104,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      if (_images.length < AppConfig.maxImagesPerPost &&
                          _video == null)
                        InkWell(
                          onTap: _pickImages,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: 104,
                            decoration: BoxDecoration(
                              color: AppConfig.primarySoft,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppConfig.line),
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_rounded,
                                    color: AppConfig.primary),
                                SizedBox(height: 6),
                                Text('إضافة صورة',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppConfig.primaryDark)),
                              ],
                            ),
                          ),
                        ),
                      ..._previews.asMap().entries.map((e) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.memory(e.value,
                                      width: 104,
                                      height: 104,
                                      fit: BoxFit.cover),
                                ),
                                Positioned(
                                  top: 4,
                                  left: 4,
                                  child: InkWell(
                                    onTap: () => setState(() {
                                      _images.removeAt(e.key);
                                      _previews.removeAt(e.key);
                                    }),
                                    child: const CircleAvatar(
                                      radius: 12,
                                      backgroundColor: Colors.black54,
                                      child: Icon(Icons.close_rounded,
                                          size: 14, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (AppConfig.allowVideo) ...[
                  const Text('فيديو',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  if (kIsWeb && !AppConfig.allowVideoUploadOnWeb)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppConfig.primarySoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.phone_iphone_rounded,
                              color: AppConfig.primary, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'رفع الفيديو من المتصفح غير متاح، لأن المتصفح لا '
                              'يحوّل ترميز المقطع فلا يعمل عند بعض المستخدمين.\n'
                              'انشر الفيديو من تطبيق الجوال، أو الصق رابط يوتيوب أدناه.',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.7,
                                  color: AppConfig.textStrong),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_processingVideo)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppConfig.primarySoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          const Text('جاري تجهيز الفيديو…',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value:
                                  _videoProgress == 0 ? null : _videoProgress,
                              minHeight: 5,
                              backgroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'يُحوَّل إلى صيغة تعمل على الآيفون وأندرويد والويب',
                            style: TextStyle(
                                fontSize: 12, color: AppConfig.textSoft),
                          ),
                        ],
                      ),
                    )
                  else if (_video == null)
                    OutlinedButton.icon(
                      onPressed: _images.isEmpty ? _pickVideo : null,
                      icon: const Icon(Icons.videocam_rounded),
                      label: Text(_images.isEmpty
                          ? 'اختر فيديو (حتى ${AppConfig.maxVideoMB} ميغا)'
                          : 'احذف الصور أولاً لإضافة فيديو'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        side: const BorderSide(color: AppConfig.line),
                        foregroundColor: AppConfig.primaryDark,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppConfig.primarySoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.movie_rounded,
                              color: AppConfig.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_videoName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () => setState(() {
                              _video = null;
                              _videoName = '';
                            }),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _youtubeController,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      hintText: 'أو الصق رابط فيديو من يوتيوب',
                      prefixIcon: Icon(Icons.link_rounded),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'الفيديو الطويل ارفعه على قناتك في يوتيوب وضع رابطه هنا — '
                    'بلا حد للحجم، ويزيد مشاهدات قناتك.',
                    style: TextStyle(
                        fontSize: 12, color: AppConfig.textSoft, height: 1.6),
                  ),
                ],
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _publishing ? null : _publish,
                child: _publishing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_isEditing ? 'حفظ التعديل' : 'نشر الخبر'),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
//  دخول الإدارة
// ===========================================================================

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Api.adminSignIn(_email.text, _password.text);
      if (mounted) Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = switch (e.code) {
          'invalid-email' => 'صيغة البريد غير صحيحة',
          'user-not-found' ||
          'wrong-password' ||
          'invalid-credential' =>
            'البريد أو كلمة المرور غير صحيحة',
          'too-many-requests' => 'محاولات كثيرة. انتظر قليلاً ثم أعد المحاولة',
          _ => 'تعذّر تسجيل الدخول. حاول مرة أخرى',
        };
      });
      await Api.ensureSignedIn();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('دخول الإدارة')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.all(22),
            shrinkWrap: true,
            children: [
              const Center(child: AppLogo(size: 64)),
              const SizedBox(height: 18),
              const Text(
                'هذه الصفحة لصاحب التطبيق فقط',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppConfig.textSoft),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  hintText: 'البريد الإلكتروني',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: _obscure,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  hintText: 'كلمة المرور',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onSubmitted: (_) => _login(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(color: AppConfig.danger),
                    textAlign: TextAlign.center),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _login,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('دخول'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
//  صفحة الإشعارات
// ===========================================================================

class NotificationsPage extends StatefulWidget {
  final bool isAdmin;
  const NotificationsPage({super.key, required this.isAdmin});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late final DateTime _seenBefore = Notifications.lastSeen;

  @override
  void initState() {
    super.initState();
    // تُقرأ عند الفتح، فتختفي الشارة
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Notifications.markAllSeen();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Api.posts
            .orderBy('createdAt', descending: true)
            .limit(30)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Text('لا توجد إشعارات بعد',
                  style: TextStyle(color: AppConfig.textSoft)),
            );
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final post = Post.fromDoc(docs[i]);
              final isNew =
                  (post.createdAt ?? DateTime(1970)).isAfter(_seenBefore);
              final preview = post.text.isEmpty
                  ? 'خبر مصوّر'
                  : (post.text.length > 90
                      ? '${post.text.substring(0, 90)}…'
                      : post.text);

              return ListTile(
                tileColor: isNew ? AppConfig.primarySoft : AppConfig.surface,
                leading: CircleAvatar(
                  backgroundColor:
                      isNew ? AppConfig.primary : AppConfig.primarySoft,
                  child: Icon(
                    Icons.campaign_rounded,
                    color: isNew ? Colors.white : AppConfig.primary,
                    size: 20,
                  ),
                ),
                title: Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: isNew ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                subtitle: Text(
                  '${post.category} · ${timeAgo(post.createdAt)}',
                  style:
                      const TextStyle(fontSize: 12, color: AppConfig.textSoft),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        PostPage(postId: post.id, isAdmin: widget.isAdmin),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ===========================================================================
//  البلاغات (للأدمن) والمحظورون
// ===========================================================================

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('البلاغات الواردة')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Api.reportsStream(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                    'تعذّر تحميل البلاغات. تأكد من نشر قواعد Firestore.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppConfig.textSoft)),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Text('لا توجد بلاغات',
                  style: TextStyle(color: AppConfig.textSoft)),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data();
              final postId = (data['postId'] ?? '') as String;
              final commentId = (data['commentId'] ?? '') as String;
              final snippet = (data['snippet'] ?? '') as String;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppConfig.danger.withAlpha(30),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                (data['reason'] ?? '') as String,
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppConfig.danger),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              timeAgo(
                                  (data['createdAt'] as Timestamp?)?.toDate()),
                              style: const TextStyle(
                                  fontSize: 11.5, color: AppConfig.textSoft),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'من: ${data['reportedName'] ?? 'غير معروف'}',
                          style: const TextStyle(
                              fontSize: 12.5, color: AppConfig.textSoft),
                        ),
                        const SizedBox(height: 6),
                        Text(snippet.isEmpty ? '(بلا نص)' : snippet,
                            style: const TextStyle(fontSize: 14, height: 1.6)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PostPage(postId: postId, isAdmin: true),
                                ),
                              ),
                              icon: const Icon(Icons.open_in_new_rounded,
                                  size: 17),
                              label: const Text('فتح الخبر'),
                            ),
                            if (commentId.isNotEmpty)
                              TextButton.icon(
                                onPressed: () async {
                                  await Api.deleteComment(postId, commentId);
                                  await d.reference.delete();
                                },
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 17, color: AppConfig.danger),
                                label: const Text('حذف التعليق',
                                    style: TextStyle(color: AppConfig.danger)),
                              ),
                            const Spacer(),
                            TextButton(
                              onPressed: () => d.reference.delete(),
                              child: const Text('تجاهل'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class BlockedPage extends StatefulWidget {
  const BlockedPage({super.key});

  @override
  State<BlockedPage> createState() => _BlockedPageState();
}

class _BlockedPageState extends State<BlockedPage> {
  @override
  Widget build(BuildContext context) {
    final users = Blocked.all.entries.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('المستخدمون المحظورون')),
      body: users.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: Text(
                  'لم تحظر أحداً.\nيمكنك حظر أي شخص من قائمة تعليقه.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppConfig.textSoft, height: 1.8),
                ),
              ),
            )
          : ListView.separated(
              itemCount: users.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) => Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppConfig.primarySoft,
                      child: Text(
                        users[i].value.trim().isEmpty
                            ? '؟'
                            : users[i].value.trim().substring(0, 1),
                        style: const TextStyle(
                            color: AppConfig.primaryDark,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                    title: Text(users[i].value),
                    trailing: TextButton(
                      onPressed: () async {
                        await Blocked.unblock(users[i].key);
                        if (mounted) setState(() {});
                      },
                      child: const Text('إلغاء الحظر'),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

// ===========================================================================
//  عناصر ومساعدات
// ===========================================================================

class _EmptyView extends StatelessWidget {
  final bool isAdmin;
  final bool searching;
  final String category;
  const _EmptyView({
    required this.isAdmin,
    required this.searching,
    this.category = '',
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 90),
        Icon(
          searching ? Icons.search_off_rounded : Icons.article_outlined,
          size: 64,
          color: AppConfig.line,
        ),
        const SizedBox(height: 14),
        Text(
          searching
              ? 'لا نتائج مطابقة لبحثك'
              : category.isNotEmpty
                  ? 'لا توجد أخبار في قسم «$category» بعد'
                  : isAdmin
                      ? 'ابدأ بنشر أول خبر من زر «خبر جديد»'
                      : 'لا توجد أخبار هنا بعد',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppConfig.textSoft, fontSize: 15),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  size: 54, color: AppConfig.textSoft),
              const SizedBox(height: 14),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppConfig.textSoft)),
              const SizedBox(height: 18),
              FilledButton(
                  onPressed: onRetry, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      ),
    );
  }
}

/// حوار إدخال اسم الزائر الظاهر في التعليقات.
Future<String?> _askForName(BuildContext context) async {
  final controller = TextEditingController(text: Api.user?.displayName ?? '');
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('باسم مَن نعرض تعليقك؟'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 30,
        decoration: const InputDecoration(
          hintText: 'اكتب اسمك',
          counterText: '',
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('تراجع')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
          onPressed: () {
            final v = controller.text.trim();
            if (v.isNotEmpty) Navigator.pop(ctx, v);
          },
          child: const Text('حفظ'),
        ),
      ],
    ),
  );
  if (name != null && name.isNotEmpty) {
    await Api.setDisplayName(name);
  }
  return name;
}

/// وقت نسبي بالعربية.
String timeAgo(DateTime? date) {
  if (date == null) return 'الآن';
  final diff = DateTime.now().difference(date);
  if (diff.inSeconds < 60) return 'الآن';
  if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} دقيقة';
  if (diff.inHours < 24) return 'قبل ${diff.inHours} ساعة';
  if (diff.inDays == 1) return 'أمس';
  if (diff.inDays < 30) return 'قبل ${diff.inDays} يوم';
  if (diff.inDays < 365) return 'قبل ${(diff.inDays / 30).floor()} شهر';
  return '${date.year}/${date.month}/${date.day}';
}
