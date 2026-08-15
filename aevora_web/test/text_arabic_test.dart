import 'package:aevora_web/client/text_arabic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('deshapeArabic', () {
    test('تحويل حروف العرض إلى حروف أساسية', () {
      expect(deshapeArabic('ﻋﺮﺽ'), 'عرض');
      expect(deshapeArabic('ﺃﺳﻌﺎﺭ'), 'أسعار');
      expect(deshapeArabic('ﻟﻠﺘﻮﺭﻳﺪﺍﺕ'), 'للتوريدات');
      expect(deshapeArabic('ﺍﻟﻤﺴﺘﻘﺒﻞ'), 'المستقبل');
    });

    test('لام-ألف مرتبطة', () {
      expect(deshapeArabic('ﻻ'), 'لا');
      expect(deshapeArabic('ﺍﻻ'), 'الا');
    });

    test('النص بدون أشكال عرض يبقى كما هو', () {
      expect(deshapeArabic('مرحبا'), 'مرحبا');
      expect(deshapeArabic('Hello 123'), 'Hello 123');
    });
  });

  group('visualToLogical — سطر عربي (ترتيب بصري معكوس)', () {
    test('سطر عربي خالص مع شرطة', () {
      const visual = 'ﺕﺍﺪﻳﺭﻮﺘﻠﻟ ﻞﺒﻘﺘﺴﻤﻟﺍ ﺔﻛﺮﺷ - ﺭﺎﻌﺳﺃ ﺽﺮﻋ';
      expect(visualToLogical(visual), 'عرض أسعار - شركة المستقبل للتوريدات');
    });

    test('سطر بأرقام 500', () {
      // الترتيب البصري الحقيقي (حسب موضع X): ريال, 500, :, أزرق, حبر, قلم
      const visual = 'ﻝﺎﻳﺭ 500 : ﻕﺭﺯﺃ ﺮﺒﺣ ﻢﻠﻗ';
      expect(visualToLogical(visual), 'قلم حبر أزرق : 500 ريال');
    });

    test('سطر بعملة عشرية 15.5', () {
      const visual = 'ﻝﺎﻳﺭ 15.5 : ﺔﻗﺭﻭ 20 ﺔﺳﺍﺮﻛ';
      expect(visualToLogical(visual), 'كراسة 20 ورقة : 15.5 ريال');
    });

    test('سطر بمبلغ كبير 515.5', () {
      const visual = 'ﻝﺎﻳﺭ 515.5 : ﻲﻠﻜﻟﺍ ﻉﻮﻤﺠﻤﻟﺍ';
      expect(visualToLogical(visual), 'المجموع الكلي : 515.5 ريال');
    });

    test('سطر بتاريخ', () {
      const visual = '2024/05/12 : ﺭﺍﺪﺻﻹﺍ ﺦﻳﺭﺎﺗ';
      expect(visualToLogical(visual), 'تاريخ الإصدار : 2024/05/12');
    });
  });

  group('visualToLogical — سطر لاتيني أو مختلط', () {
    test('نص إنجليزي يبقى كما هو', () {
      expect(visualToLogical('Total: 500 SAR'), 'Total: 500 SAR');
      expect(visualToLogical('Invoice #123 dated 2024/05/12'),
          'Invoice #123 dated 2024/05/12');
    });

    test('سطر لاتيني مع فقرة عربية', () {
      const visual = 'Invoice 12 مقر';
      expect(visualToLogical(visual), 'Invoice رقم 12');
    });
  });
}
