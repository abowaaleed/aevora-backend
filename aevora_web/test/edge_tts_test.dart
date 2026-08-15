import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:aevora_web/client/client_voice.dart';

void main() {
  group('edgeVoiceForLang', () {
    test('selects Saudi Arabic voice for Arabic text', () {
      expect(edgeVoiceForLang('ar-SA'), kEdgeArabicVoice);
      expect(edgeVoiceForLang('ar'), kEdgeArabicVoice);
    });

    test('selects English voice for English text', () {
      expect(edgeVoiceForLang('en-US'), kEdgeEnglishVoice);
      expect(edgeVoiceForLang('en-GB'), kEdgeEnglishVoice);
    });
  });

  group('edgeXmlEscape', () {
    test('escapes XML special characters', () {
      expect(edgeXmlEscape('a & b <c> "d" \'e\''),
          'a &amp; b &lt;c&gt; &quot;d&quot; &apos;e&apos;');
    });

    test('leaves plain text untouched', () {
      expect(edgeXmlEscape('مرحباً بك في ايفورا'), 'مرحباً بك في ايفورا');
    });
  });

  group('edgeTextChunks', () {
    test('returns single chunk for short text', () {
      final chunks = edgeTextChunks('مرحباً، كيف حالك؟');
      expect(chunks, ['مرحباً، كيف حالك؟']);
    });

    test('splits long text into bounded chunks at word boundaries', () {
      final long = List.filled(200, 'جملة عربية ممتدة بدون حد').join(' ');
      final chunks = edgeTextChunks(long);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(3000));
      }
      expect(chunks.join(' ').replaceAll(' ', ''), long.replaceAll(' ', ''));
    });

    test('returns empty list for empty text', () {
      expect(edgeTextChunks(''), isEmpty);
      expect(edgeTextChunks('   '), isEmpty);
    });
  });

  group('edgeTimestamp', () {
    test('matches Edge JavaScript Date format', () {
      final ts = edgeTimestamp(DateTime.utc(2026, 8, 15, 12, 34, 56));
      expect(ts, 'Sat Aug 15 2026 12:34:56 GMT+0000 (Coordinated Universal Time)');
    });
  });

  group('edgeSecMsGec', () {
    test('matches reference SHA-256 value for a fixed time', () {
      expect(
        edgeSecMsGec(DateTime.utc(2026, 8, 15, 12, 34, 56)),
        'A46E13B8A30D4FE231DA47723B308B13B11EE8A970979EA4B33E877830F439E0',
      );
    });

    test('produces a 64-char uppercase hex digest', () {
      final gec = edgeSecMsGec(DateTime.now());
      expect(RegExp(r'^[0-9A-F]{64}$').hasMatch(gec), isTrue);
    });
  });

  group('edgeConnectionId', () {
    test('generates 32 lowercase hex characters', () {
      final id = edgeConnectionId();
      expect(id.length, 32);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(id), isTrue);
    });
  });

  group('edgeTtsWsUrl', () {
    test('includes required Edge parameters', () {
      final url = edgeTtsWsUrl(connectionId: 'abc', now: DateTime.utc(2026));
      expect(url, startsWith('wss://speech.platform.bing.com/'));
      expect(url, contains('TrustedClientToken=$kEdgeTtsTrustedClientToken'));
      expect(url, contains('ConnectionId=abc'));
      expect(url, contains('Sec-MS-GEC='));
      expect(url, contains('Sec-MS-GEC-Version=$kEdgeSecMsGecVersion'));
    });
  });

  group('edgeConfigMessage', () {
    test('contains speech.config path and output format', () {
      final msg = edgeConfigMessage(now: DateTime.utc(2026));
      expect(msg, contains('Path:speech.config'));
      expect(msg, contains(kEdgeAudioFormat));
      expect(msg, contains('\r\n\r\n'));
    });
  });

  group('edgeSsmlMessage', () {
    test('embeds voice, escaped text and ssml path', () {
      final msg = edgeSsmlMessage(
        voice: kEdgeArabicVoice,
        text: 'مرحباً <test> & عالم',
        rate: 0.95,
        now: DateTime.utc(2026),
      );
      expect(msg, contains('Path:ssml'));
      expect(msg, contains("<voice name='$kEdgeArabicVoice'>"));
      expect(msg, contains('rate=\'-5%\''));
      expect(msg, contains('مرحباً &lt;test&gt; &amp; عالم'));
    });
  });

  group('edgeAudioFromFrame', () {
    test('strips header length prefix and CRLF delimiter', () {
      final body = Uint8List.fromList(List.generate(10, (i) => 0x40 + i));
      final header = 'Path: audio\r\nX-RequestId: x\r\n\r\n';
      final frame = Uint8List.fromList([
        ...[(header.length >> 8) & 0xFF, header.length & 0xFF],
        ...ascii.encode(header),
        ...body,
      ]);
      expect(edgeAudioFromFrame(frame), body);
    });

    test('returns empty for short frames', () {
      expect(edgeAudioFromFrame(Uint8List(0)), isEmpty);
      expect(edgeAudioFromFrame(Uint8List(1)), isEmpty);
    });
  });

  group('edgeIsTurnEnd', () {
    test('detects turn.end marker', () {
      expect(edgeIsTurnEnd('Path: turn.end'), isTrue);
      expect(edgeIsTurnEnd('Path: turn.start'), isFalse);
      expect(edgeIsTurnEnd(''), isFalse);
    });
  });
}
