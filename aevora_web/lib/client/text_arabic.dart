library;

/// أدوات معالجة النص العربي المُستخرج من ملفات PDF.
///
/// كثير من مولّدات PDF تخزّن النص العربي بترتيب «بصري» (معكوس): الحروف داخل
/// الكلمة معكوسة، وترتيب الكلمات معكوس، وقد تكون حروف «عرض/ارتباط» (Presentation
/// Forms) بدل الحروف الأساسية. هذا الملف يرمّم النص إلى الترتيب المنطقي الصحيح
/// القابل للقراءة والبحث، دون أي اعتماد على خوادم خارجية.

/// هل يحتوي النص على أي حروف عربية (أساسية أو أشكال عرض)؟
bool containsArabic(String text) {
  for (final r in text.runes) {
    if (_isArabicRune(r)) return true;
  }
  return false;
}

bool _isArabicRune(int r) {
  if (r >= 0x0600 && r <= 0x06FF) return true; // عربي أساسي
  if (r >= 0x0750 && r <= 0x077F) return true; // امتدادات عربية
  if (r >= 0x08A0 && r <= 0x08FF) return true; // امتدادات عربية حديثة
  if (r >= 0xFB50 && r <= 0xFDFF) return true; // أشكال عرض - أ
  if (r >= 0xFE70 && r <= 0xFEFF) return true; // أشكال عرض - ب
  return false;
}

bool _isLatinLetter(int r) =>
    (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A) || (r >= 0xC0 && r <= 0x24F);

bool _isDigitRune(int r) =>
    (r >= 0x30 && r <= 0x39) || // ASCII
    (r >= 0x0660 && r <= 0x0669) || // أرقام عربية
    (r >= 0x06F0 && r <= 0x06F9) || // أرقام فارسية
    (r >= 0xFF10 && r <= 0xFF19); // أرقام بعرض كامل

/// حرف داخل «الترميز المنطقي» يجب ألا يُعكس (حروف لاتينية وأرقام وعلامات رقمية).
bool _isLtrCore(int r) => _isLatinLetter(r) || _isDigitRune(r);

bool _isSymbolRune(int r) =>
    r == 0x2E || // .
    r == 0x2C || // ,
    r == 0x2F || // /
    r == 0x2D || // -
    r == 0x3A || // :
    r == 0x5F || // _
    r == 0x25 || // %
    r == 0x2B || // +
    r == 0x40 || // @
    r == 0x23 || // #
    r == 0x24 || // $
    r == 0x5C || // \
    r == 0x7C; // |

/// يعكس الترتيب البصري (المعكوس) إلى الترتيب المنطقي العربي الصحيح.
///
/// المنطق: عكس كامل التسلسل، ثم إعادة عكس كل «مجموعة» لاتينية/رقمية (أرقام،
/// تواريخ، أسعار) حتى لا تبقى معكوسة، ثم تحويل حروف العرض إلى الحروف الأساسية.
String visualToLogical(String visual) {
  if (!containsArabic(visual)) return visual;

  var rtl = 0;
  var ltr = 0;
  for (final r in visual.runes) {
    if (_isArabicRune(r)) {
      rtl++;
    } else if (_isLatinLetter(r)) {
      ltr++;
    }
  }

  if (rtl >= ltr) {
    // الخط عربي في الغالب: عكس كامل الخط ثم إصلاح المجموعات اللاتينية/الرقمية.
    return deshapeArabic(_fixLtrRuns(String.fromCharCodes(visual.runes.toList().reversed)));
  }

  // خط لاتيني في الغالب مع فقرات عربية: نعكس كل فقرة عربية على حدة.
  return deshapeArabic(_fixRtlSegments(visual));
}

/// إصلاح «المجموعات» اللاتينية/الرقمية المعكوسة داخل نص أصبح بالترتيب المنطقي.
///
/// مثال: «قلم:005 ريال» ← «قلم:500 ريال»، و«21/50/4202» ← «2024/05/12».
String _fixLtrRuns(String s) {
  final runes = s.runes.toList();
  final out = <int>[];
  var i = 0;
  while (i < runes.length) {
    if (_isLtrCore(runes[i])) {
      var j = i;
      while (j < runes.length) {
        final c = runes[j];
        if (_isLtrCore(c)) {
          j++;
        } else if (_isSymbolRune(c) &&
            j - 1 >= i &&
            _isLtrCore(runes[j - 1]) &&
            j + 1 < runes.length &&
            _isLtrCore(runes[j + 1])) {
          j++; // رمز محصور بين رقمين/حروف لاتينية (مثل '/' في التاريخ)
        } else {
          break;
        }
      }
      for (var k = j - 1; k >= i; k--) {
        out.add(runes[k]);
      }
      i = j;
    } else {
      out.add(runes[i]);
      i++;
    }
  }
  return String.fromCharCodes(out);
}

/// عكس الفقرات العربية داخل سطر لاتيني، مع إبقاء النص اللاتيني على حاله.
String _fixRtlSegments(String s) {
  final out = StringBuffer();
  var run = <int>[];
  var runHasArabic = false;

  void flush() {
    if (run.isNotEmpty) {
      if (runHasArabic) {
        // إبقاء مسافة الفصل البادئة في مكانها حتى لا تلتصق الكلمات ببعضها.
        var lead = 0;
        while (lead < run.length && (run[lead] == 0x20 || run[lead] == 0x09)) {
          lead++;
        }
        final inner = run.sublist(lead);
        if (inner.isEmpty) {
          out.write(String.fromCharCodes(run));
        } else {
          if (lead > 0) out.write(' ');
          out.write(_fixLtrRuns(String.fromCharCodes(inner.reversed)));
        }
      } else {
        out.write(String.fromCharCodes(run));
      }
      run = <int>[];
      runHasArabic = false;
    }
  }

  for (final r in s.runes) {
    if (_isArabicRune(r)) {
      run.add(r);
      runHasArabic = true;
    } else if (_isDigitRune(r) || _isSymbolRune(r) || r == 0x20) {
      run.add(r); // أرقام وعلامات ومسافات تلحق بالفقرة المجاورة
    } else if (_isLatinLetter(r) || r == 0x0A || r == 0x0D || r == 0x09) {
      flush();
      out.writeCharCode(r);
    } else {
      run.add(r);
    }
  }
  flush();
  return out.toString();
}

/// تحويل حروف «العرض/الارتباط» (Presentation Forms) إلى الحروف العربية الأساسية.
///
/// مثل: ﻋﺮﺽ ← عرض، وﻟﻠﺘﻮﺭﻳﺪﺍﺕ ← للتوريدات.
String deshapeArabic(String text) {
  final runes = text.runes.toList();
  final out = StringBuffer();
  var i = 0;
  while (i < runes.length) {
    final r = runes[i];
    final lig = _ligatureToBase[r];
    if (lig != null) {
      for (final base in lig) {
        out.writeCharCode(base);
      }
    } else {
      out.writeCharCode(_presentationToBase[r] ?? r);
    }
    i++;
  }
  return out.toString();
}

/// حروف العرض ← الحروف الأساسية (مولّدة من Unicode Decomposition).
const Map<int, int> _presentationToBase = {
  0xFB50: 0x671, 0xFB51: 0x671, 0xFBAE: 0x6D2, 0xFBAF: 0x6D2, 0xFBB0: 0x6D3, 0xFBB1: 0x6D3,
  0xFBE8: 0x649, 0xFBE9: 0x649, 0xFE80: 0x621, 0xFE81: 0x622, 0xFE82: 0x622, 0xFE83: 0x623,
  0xFE84: 0x623, 0xFE85: 0x624, 0xFE86: 0x624, 0xFE87: 0x625, 0xFE88: 0x625, 0xFE89: 0x626,
  0xFE8A: 0x626, 0xFE8B: 0x626, 0xFE8C: 0x626, 0xFE8D: 0x627, 0xFE8E: 0x627, 0xFE8F: 0x628,
  0xFE90: 0x628, 0xFE91: 0x628, 0xFE92: 0x628, 0xFE93: 0x629, 0xFE94: 0x629, 0xFE95: 0x62A,
  0xFE96: 0x62A, 0xFE97: 0x62A, 0xFE98: 0x62A, 0xFE99: 0x62B, 0xFE9A: 0x62B, 0xFE9B: 0x62B,
  0xFE9C: 0x62B, 0xFE9D: 0x62C, 0xFE9E: 0x62C, 0xFE9F: 0x62C, 0xFEA0: 0x62C, 0xFEA1: 0x62D,
  0xFEA2: 0x62D, 0xFEA3: 0x62D, 0xFEA4: 0x62D, 0xFEA5: 0x62E, 0xFEA6: 0x62E, 0xFEA7: 0x62E,
  0xFEA8: 0x62E, 0xFEA9: 0x62F, 0xFEAA: 0x62F, 0xFEAB: 0x630, 0xFEAC: 0x630, 0xFEAD: 0x631,
  0xFEAE: 0x631, 0xFEAF: 0x632, 0xFEB0: 0x632, 0xFEB1: 0x633, 0xFEB2: 0x633, 0xFEB3: 0x633,
  0xFEB4: 0x633, 0xFEB5: 0x634, 0xFEB6: 0x634, 0xFEB7: 0x634, 0xFEB8: 0x634, 0xFEB9: 0x635,
  0xFEBA: 0x635, 0xFEBB: 0x635, 0xFEBC: 0x635, 0xFEBD: 0x636, 0xFEBE: 0x636, 0xFEBF: 0x636,
  0xFEC0: 0x636, 0xFEC1: 0x637, 0xFEC2: 0x637, 0xFEC3: 0x637, 0xFEC4: 0x637, 0xFEC5: 0x638,
  0xFEC6: 0x638, 0xFEC7: 0x638, 0xFEC8: 0x638, 0xFEC9: 0x639, 0xFECA: 0x639, 0xFECB: 0x639,
  0xFECC: 0x639, 0xFECD: 0x63A, 0xFECE: 0x63A, 0xFECF: 0x63A, 0xFED0: 0x63A, 0xFED1: 0x641,
  0xFED2: 0x641, 0xFED3: 0x641, 0xFED4: 0x641, 0xFED5: 0x642, 0xFED6: 0x642, 0xFED7: 0x642,
  0xFED8: 0x642, 0xFED9: 0x643, 0xFEDA: 0x643, 0xFEDB: 0x643, 0xFEDC: 0x643, 0xFEDD: 0x644,
  0xFEDE: 0x644, 0xFEDF: 0x644, 0xFEE0: 0x644, 0xFEE1: 0x645, 0xFEE2: 0x645, 0xFEE3: 0x645,
  0xFEE4: 0x645, 0xFEE5: 0x646, 0xFEE6: 0x646, 0xFEE7: 0x646, 0xFEE8: 0x646, 0xFEE9: 0x647,
  0xFEEA: 0x647, 0xFEEB: 0x647, 0xFEEC: 0x647, 0xFEED: 0x648, 0xFEEE: 0x648, 0xFEEF: 0x649,
  0xFEF0: 0x649, 0xFEF1: 0x64A, 0xFEF2: 0x64A, 0xFEF3: 0x64A, 0xFEF4: 0x64A,
};

/// أحرف مرتبطة (مثل لا، آ، أ، إ ولواحق الكلمات) ← حروفها الأساسية.
const Map<int, List<int>> _ligatureToBase = {
  0xFBE0: [0x627, 0x649],
  0xFBE1: [0x627, 0x649],
  0xFBE2: [0x627, 0x648],
  0xFBE3: [0x627, 0x648],
  0xFBE4: [0x648, 0x62C],
  0xFBE5: [0x648, 0x62C],
  0xFBE6: [0x648, 0x62D],
  0xFBE7: [0x648, 0x62D],
  0xFBE8: [0x64A, 0x649],
  0xFBE9: [0x64A, 0x649],
  0xFBEA: [0x626, 0x627],
  0xFBEB: [0x626, 0x627],
  0xFBEE: [0x626, 0x648],
  0xFBEF: [0x626, 0x648],
  0xFBF9: [0x626, 0x649],
  0xFBFA: [0x626, 0x649],
  0xFBFB: [0x626, 0x649],
  0xFEF5: [0x644, 0x622], // لآ
  0xFEF6: [0x644, 0x622],
  0xFEF7: [0x644, 0x623], // لأ
  0xFEF8: [0x644, 0x623],
  0xFEF9: [0x644, 0x625], // لإ
  0xFEFA: [0x644, 0x625],
  0xFEFB: [0x644, 0x627], // لا
  0xFEFC: [0x644, 0x627],
};
