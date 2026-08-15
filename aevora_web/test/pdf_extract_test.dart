import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:aevora_web/client/client_rag.dart';

/// توليد PDF عربي فعلي (بنفس ترميز الأسعار الحقيقي) والتحقق من أن
/// الاستخراج الذكي يعيد بناء النص بترتيب القراءة الصحيح.
Uint8List _buildArabicPdf() {
  final fontBytes = File('/System/Library/Fonts/Supplemental/Tahoma.ttf')
      .readAsBytesSync();

  final doc = PdfDocument();
  final page = doc.pages.add();
  final font = PdfTrueTypeFont(fontBytes, 18);

  final lines = <String>[
    'عرض أسعار - شركة المستقبل للتوريدات',
    'قلم حبر أزرق : 500 ريال',
    'كراسة 20 ورقة : 15.5 ريال',
    'المجموع الكلي : 515.5 ريال',
    'تاريخ الإصدار : 2024/05/12',
  ];
  var y = 40.0;
  for (final line in lines) {
    page.graphics.drawString(
      line,
      font,
      bounds: Rect.fromLTWH(0, y, page.size.width, 30),
      format: PdfStringFormat(
        textDirection: PdfTextDirection.rightToLeft,
        alignment: PdfTextAlignment.right,
      ),
    );
    y += 35;
  }

  return Uint8List.fromList(doc.saveSync());
}

void main() {
  test('استخراج PDF عربي يعيد بناء الترتيب الصحيح سطراً بسطر', () async {
    final bytes = _buildArabicPdf();
    final text = await extractText('عرض_اسعار.pdf', bytes);

    final expected = [
      'عرض أسعار - شركة المستقبل للتوريدات',
      'قلم حبر أزرق : 500 ريال',
      'كراسة 20 ورقة : 15.5 ريال',
      'المجموع الكلي : 515.5 ريال',
      'تاريخ الإصدار : 2024/05/12',
    ];

    for (final line in expected) {
      expect(text, contains(line), reason: 'المفقود: «$line»\nالنص الفعلي:\n$text');
    }
  });

  test('استخراج PDF إنجليزي لا يتغير', () async {
    final doc = PdfDocument();
    final page = doc.pages.add();
    final font = PdfStandardFont(PdfFontFamily.helvetica, 14);
    page.graphics.drawString('Hello World - Invoice #123', font,
        bounds: const Rect.fromLTWH(0, 40, 500, 30));
    final bytes = doc.saveSync();
    doc.dispose();

    final text = await extractText('invoice.pdf', bytes);
    expect(text, contains('Hello World - Invoice #123'));
  });

  test('PDF متعدد الصفحات: عربية في صفحة وإنجليزية في أخرى', () async {
    final fontBytes = File('/System/Library/Fonts/Supplemental/Tahoma.ttf')
        .readAsBytesSync();

    final doc = PdfDocument();
    final arabicFont = PdfTrueTypeFont(fontBytes, 18);
    final latinFont = PdfStandardFont(PdfFontFamily.helvetica, 14);

    final page1 = doc.pages.add();
    page1.graphics.drawString(
      'عرض أسعار - شركة المستقبل للتوريدات',
      arabicFont,
      bounds: const Rect.fromLTWH(0, 40, 500, 30),
      format: PdfStringFormat(
        textDirection: PdfTextDirection.rightToLeft,
        alignment: PdfTextAlignment.right,
      ),
    );

    final page2 = doc.pages.add();
    page2.graphics.drawString(
      'Prices valid until 2024/05/12',
      latinFont,
      bounds: const Rect.fromLTWH(0, 40, 500, 30),
    );

    final bytes = Uint8List.fromList(doc.saveSync());
    doc.dispose();

    final text = await extractText('multi.pdf', bytes);
    expect(text, contains('عرض أسعار - شركة المستقبل للتوريدات'));
    expect(text, contains('Prices valid until 2024/05/12'));
  });
}
