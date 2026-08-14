/// واجهة طبقة التخزين المحلية الموحّدة:
/// - على المتصفح: IndexedDB عبر `storage_web.dart`.
/// - على الجوال (iOS/Android): SharedPreferences عبر `storage_stub.dart`.
library;

export 'blob_types.dart';
export 'storage_stub.dart'
    if (dart.library.js_interop) 'storage_web.dart';
