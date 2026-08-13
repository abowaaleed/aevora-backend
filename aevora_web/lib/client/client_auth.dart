import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_config.dart';

/// طبقة المصادقة: دخول بحساب Google عبر Firebase Auth (من المتصفح مباشرة).
/// الجلسة تُحفظ تلقائياً في المتصفح فلا يُعاد تسجيل الدخول عند كل زيارة.
Future<void> initFirebase() async {
  if (!isFirebaseConfigured) return;
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: FirebaseConfig.apiKey,
        authDomain: FirebaseConfig.authDomain,
        projectId: FirebaseConfig.projectId,
        storageBucket: FirebaseConfig.storageBucket,
        messagingSenderId: FirebaseConfig.messagingSenderId,
        appId: FirebaseConfig.appId,
      ),
    );
  }
  // حفظ الجلسة محلياً (السلوك الافتراضي على الويب) ليظل المستخدم مسجلاً.
  await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
}

bool get isAuthEnabled => isFirebaseConfigured;

bool get isSignedIn =>
    isAuthEnabled && FirebaseAuth.instance.currentUser != null;

String? get currentUserId => isSignedIn ? FirebaseAuth.instance.currentUser!.uid : null;

String? get currentEmail => isSignedIn ? FirebaseAuth.instance.currentUser!.email : null;

String? get currentDisplayName =>
    isSignedIn ? FirebaseAuth.instance.currentUser!.displayName : null;

/// تيار حالة الجلسة (يُعاد بناؤه عند كل تغيّر دخول/خروج).
Stream<User?> authStateStream() {
  if (!isAuthEnabled) return const Stream.empty();
  return FirebaseAuth.instance.authStateChanges();
}

/// تسجيل الدخول بحساب Google عبر نافذة منبثقة (يعمل من المتصفح مباشرة).
Future<User?> signInWithGoogle() async {
  if (!isAuthEnabled) return null;
  final provider = GoogleAuthProvider();
  final cred = await FirebaseAuth.instance.signInWithPopup(provider);
  return cred.user;
}

/// تسجيل الخروج (تبقى البيانات المحلية لكنها تتوقف عن المزامنة).
Future<void> signOut() async {
  if (isAuthEnabled && Firebase.apps.isNotEmpty) {
    await FirebaseAuth.instance.signOut();
  }
}
