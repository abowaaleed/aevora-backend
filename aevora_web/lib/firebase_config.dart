/// إعدادات مشروع Firebase لتطبيق ايفورا.
///
/// ضع هنا قيم مشروعك من Firebase Console:
/// 1) console.firebase.google.com → أنشئ مشروعاً → أضف تطبيق Web.
/// 2) انسخ قيم الإعدادات من إعدادات المشروع (Project settings → Your apps).
/// 3) فعّل تسجيل الدخول عبر Google في Authentication → Sign-in method.
/// 4) أضف نطاق الموقع إلى Authorized domains (مثال: abowaaleed.github.io).
/// 5) فعّل Firestore وأدخل القواعد الآمنة لكل مستخدم.
///
/// الملف يعمل كنمط "بدون خادم": إن تركت القيم النموذجية تبقى ايفورا محلية
/// 100% كما كانت، وحين تضع قيماً حقيقية تُفعَّل المصادقة والمزامنة تلقائياً.
class FirebaseConfig {
  FirebaseConfig._();

  static const String apiKey = 'AIzaSyAdsTsSUaTCTA_XydCIKb6FVg3iEg7fx_Q';
  static const String authDomain = 'aevora-1f64f.firebaseapp.com';
  static const String projectId = 'aevora-1f64f';
  static const String storageBucket = 'aevora-1f64f.firebasestorage.app';
  static const String messagingSenderId = '981343794141';
  static const String appId = '1:981343794141:web:275b3bbe146b079c253c34';
}

/// هل أُدخلت إعدادات Firebase الحقيقية؟ (نعم تعني تفعيل الحسابات والمزامنة)
bool get isFirebaseConfigured =>
    FirebaseConfig.apiKey != 'YOUR_WEB_API_KEY' &&
    FirebaseConfig.appId != 'YOUR_WEB_APP_ID' &&
    FirebaseConfig.projectId != 'YOUR_PROJECT_ID';
