import 'package:flutter_test/flutter_test.dart';
import 'package:customshield/models/access_key.dart';

void main() {
  group('AccessKey', () {
    test('parses pulsar://', () {
      final key = AccessKey.parse(
        'pulsar://deadbeefcafebabe@203.0.113.10:51820/?id=aabbccdd',
      );
      expect(key.serverIp, '203.0.113.10');
      expect(key.port, 51820);
      expect(key.secretKey, 'deadbeefcafebabe');
      expect(key.connectionId, 'aabbccdd');
      expect(key.displayUrl, contains('pulsar://'));
    });

    test('parses legacy cs://', () {
      final key = AccessKey.parse(
        'cs://deadbeefcafebabe@203.0.113.10:51820/?id=aabbccdd',
      );
      expect(key.serverIp, '203.0.113.10');
      expect(key.displayUrl, startsWith('pulsar://'));
    });

    test('rejects empty secret', () {
      expect(
        () => AccessKey.parse('pulsar://1.2.3.4:51820/'),
        throwsFormatException,
      );
    });
  });
}
