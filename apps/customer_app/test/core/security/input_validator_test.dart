import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/security/input_validator.dart';

void main() {
  group('Input Validation Tests', () {
    test('validateEmail accurately validates emails', () {
      expect(InputValidator.validateEmail('invalid-email'), isNotNull);
      expect(InputValidator.validateEmail('user@domain.com'), isNull);
    });

    test('sanitizeQuery strips harmful HTML tags', () {
      const dangerousInput = '<script>alert("xss")</script> Smartphone';
      final clean = InputValidator.sanitizeQuery(dangerousInput);
      expect(clean, equals('scriptalert("xss")/script Smartphone'));
    });
  });
}
