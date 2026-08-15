import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aevora_web/client/text_files.dart';

Uint8List _buildDocx(String bodyXml) {
  final archive = Archive()
    ..addFile(ArchiveFile.bytes('[Content_Types].xml', utf8.encode('''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
</Types>
''')))
    ..addFile(ArchiveFile.bytes('_rels/.rels', utf8.encode('''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>
''')))
    ..addFile(ArchiveFile.bytes('word/document.xml', utf8.encode(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>'
      '$bodyXml'
      '</w:body>'
      '</w:document>',
    )));
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  group('docxToText', () {
    test('يستخرج الفقرات والجداول مع الترتيب العربي الصحيح', () async {
      final docx = _buildDocx('''
        <w:p><w:r><w:t>قلم حبر أزرق : 500 ريال</w:t></w:r></w:p>
        <w:p><w:r><w:t>السطر الثاني</w:t></w:r></w:p>
        <w:tbl>
          <w:tr><w:tc><w:p><w:r><w:t>عمود 1</w:t></w:r></w:p></w:tc>
                 <w:tc><w:p><w:r><w:t>عمود 2</w:t></w:r></w:p></w:tc></w:tr>
        </w:tbl>
      ''');
      final text = await docxToText(docx);
      expect(text, contains('قلم حبر أزرق : 500 ريال'));
      expect(text, contains('السطر الثاني'));
      expect(text, contains('عمود 1'));
      expect(text, contains('عمود 2'));
      expect(text.indexOf('السطر الثاني') < text.indexOf('عمود 1'), isTrue);
    });

    test('يلتقط كلمة بعدها مسافة (تجاهل الفراغات المكررة)', () async {
      final docx = _buildDocx(
          '<w:p><w:r><w:t xml:space="preserve">  كلمة  </w:t></w:r></w:p>');
      final text = await docxToText(docx);
      expect(text.trim(), 'كلمة');
    });
  });

  group('decodeTextFile', () {
    test('UTF-8 مع BOM', () {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('مرحبا')];
      expect(decodeTextFile(bytes), 'مرحبا');
    });

    test('UTF-16LE مع BOM (Notepad ويندوز)', () {
      final bytes = [0xFF, 0xFE, ...utf8.encode('abc').expand((b) => [b, 0])];
      expect(decodeTextFile(bytes), 'abc');
    });

    test('Windows-1256 العربية', () {
      // "أسعار" = 0xC3 0xD3 0xDA 0xC7 0xD1 في cp1256
      final bytes = [0xC3, 0xD3, 0xDA, 0xC7, 0xD1];
      expect(decodeTextFile(bytes), 'أسعار');
    });

    test('نص عادي UTF-8 بلا BOM', () {
      expect(decodeTextFile(utf8.encode('نص بلا ترخيص')).contains('نص'), isTrue);
    });
  });
}
