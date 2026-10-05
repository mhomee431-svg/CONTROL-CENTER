import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/security/input_validator.dart';
import 'package:hyperlocal_app/core/validation/validators.dart';

void main() {
  group('PhoneValidator - one Indian-mobile rule', () {
    test('accepts real Indian mobiles', () {
      for (final n in ['9876543210', '6123456789', '9999999999']) {
        expect(PhoneValidator.isValid(n), isTrue, reason: n);
        expect(PhoneValidator.validate(n), isNull, reason: n);
      }
    });

    test('tolerates the formatting a human actually types', () {
      for (final n in [' 98765 43210 ', '98765-43210', '+91 98765 43210']) {
        expect(PhoneValidator.isValid(n), isTrue, reason: n);
      }
    });

    test('rejects landlines and impossible prefixes', () {
      // 0/1/2/3/4/5 are not allocated Indian mobile ranges. The OLD shared
      // rule `^[+?]?[0-9]{10,12}$` accepted every one of these.
      for (final n in [
        '1234567890',
        '0123456789',
        '5000000000',
        '1111111111',
      ]) {
        expect(PhoneValidator.isValid(n), isFalse, reason: n);
      }
    });

    test('rejects wrong lengths', () {
      expect(PhoneValidator.isValid('987654321'), isFalse);
      expect(PhoneValidator.isValid('98765432101'), isFalse);
      expect(PhoneValidator.isValid('abcdefghij'), isFalse);
      expect(PhoneValidator.isValid(null), isFalse);
    });

    test('empty is REQUIRED, not a format error', () {
      expect(PhoneValidator.validate(''), PhoneValidator.requiredMessage);
      expect(PhoneValidator.validate(null), PhoneValidator.requiredMessage);
    });

    test('isValid and validate never disagree', () {
      for (final n in ['9876543210', '1234567890', 'abc']) {
        expect(
          PhoneValidator.isValid(n),
          PhoneValidator.validate(n) == null,
          reason: n,
        );
      }
    });
  });

  group('EmailValidator', () {
    test('accepts ordinary addresses', () {
      for (final e in [
        'user@example.com',
        'first.last+tag@sub.example.co.in',
        'a_b-c%d@mail-server.io',
      ]) {
        expect(EmailValidator.isValid(e), isTrue, reason: e);
      }
    });

    test('accepts long TLDs the old {2,4} cap rejected', () {
      // The previous `_emailRegExp` used `[\w-]{2,4}$` and rejected these.
      // Note the subdomain: `a@museum` is a single-label domain and IS
      // rejected — a missing dot in the domain is a different problem from a
      // long TLD, and conflating them here would have hidden the real one.
      for (final e in ['a@shop.museum', 'a@go.travel', 'a@site.photography']) {
        expect(EmailValidator.isValid(e), isTrue, reason: e);
      }
    });

    test('rejects a single-label domain', () {
      expect(EmailValidator.isValid('a@localhost'), isFalse);
      expect(EmailValidator.isValid('a@museum'), isFalse);
    });

    test('rejects malformed addresses', () {
      for (final e in [
        'plainaddress',
        '@nolocal.com',
        'user@',
        'user@localhost',
        'a@b..c',
        'user@@example.com',
        'user name@example.com',
        'user@.com',
      ]) {
        expect(EmailValidator.isValid(e), isFalse, reason: e);
      }
    });

    test('an absurdly long address is rejected before the regex', () {
      expect(EmailValidator.isValid('${'a' * 300}@example.com'), isFalse);
    });

    test('optional email: blank passes, garbage does not', () {
      expect(EmailValidator.validateOptional(''), isNull);
      expect(EmailValidator.validateOptional(null), isNull);
      expect(EmailValidator.validateOptional('   '), isNull);
      expect(EmailValidator.validateOptional('abc'), isNotNull);
      expect(EmailValidator.validateOptional('a@b.com'), isNull);
    });
  });
  group('SearchValidator', () {
    test('empty is valid - the submit button owns that decision', () {
      expect(SearchValidator.isValid(''), isTrue);
      expect(SearchValidator.isValid(null), isTrue);
      expect(SearchValidator.validate(''), isNull);
    });

    test('caps length', () {
      expect(SearchValidator.isValid('a' * 100), isTrue);
      expect(SearchValidator.isValid('a' * 101), isFalse);
      expect(
        SearchValidator.validate('a' * 101),
        SearchValidator.tooLongMessage,
      );
    });

    test('sanitize strips XSS vectors and control characters', () {
      expect(
        SearchValidator.sanitize('<script>alert(1)</script>'),
        isNot(contains('<')),
      );
      expect(SearchValidator.sanitize('a b'), 'a b');
      expect(SearchValidator.sanitize('  hi   there  '), 'hi there');
    });

    test('sanitize truncates rather than rejecting', () {
      expect(
        SearchValidator.sanitize('a' * 250).length,
        SearchValidator.maxLength,
      );
    });
  });

  group('PincodeValidator', () {
    test('accepts real PIN codes', () {
      expect(PincodeValidator.isValid('560001'), isTrue);
      expect(PincodeValidator.isValid('110001'), isTrue);
      expect(PincodeValidator.isValid('560 001'), isTrue);
    });

    test('rejects wrong length and a leading zero', () {
      expect(PincodeValidator.isValid('56000'), isFalse);
      expect(PincodeValidator.isValid('5600012'), isFalse);
      expect(PincodeValidator.isValid('012345'), isFalse);
      expect(PincodeValidator.isValid('abcdef'), isFalse);
      expect(PincodeValidator.isValid(null), isFalse);
    });

    test('empty is required', () {
      expect(PincodeValidator.validate(''), PincodeValidator.requiredMessage);
    });
  });

  group('NameValidator', () {
    test('accepts Indian and international names', () {
      for (final n in [
        'Rahul Sharma',
        "O'Brien",
        'Anne-Marie',
        'José',
        'Müller',
        'राहुल',
      ]) {
        expect(NameValidator.isValid(n), isTrue, reason: n);
      }
    });

    test('rejects digits, symbols and empty input', () {
      for (final n in ['Rahul123', '<script>', 'a', '', '   ']) {
        expect(NameValidator.isValid(n), isFalse, reason: '"$n"');
      }
      expect(NameValidator.validate(''), NameValidator.requiredMessage);
      expect(NameValidator.validate('a'), NameValidator.tooShortMessage);
    });

    test('enforces the length bounds', () {
      expect(NameValidator.isValid('a' * NameValidator.maxLength), isTrue);
      expect(
        NameValidator.isValid('a' * (NameValidator.maxLength + 1)),
        isFalse,
      );
    });
  });

  group('AddressValidator', () {
    test('accepts a real address and is loose about content', () {
      // No content rule: rural and multilingual addresses have no fixed shape.
      expect(AddressValidator.isValid('12, MG Road, Bengaluru 560001'), isTrue);
      expect(AddressValidator.isValid('घर नंबर 5, गांव - रामपुर'), isTrue);
    });

    test('rejects an empty or too-short address', () {
      expect(AddressValidator.isValid(''), isFalse);
      expect(AddressValidator.isValid('abc'), isFalse);
      expect(AddressValidator.validate(''), AddressValidator.requiredMessage);
    });

    test('rejects a runaway paste', () {
      expect(AddressValidator.isValid('a' * 500), isFalse);
      expect(
        AddressValidator.validate('a' * 500),
        AddressValidator.tooLongMessage,
      );
    });
  });

  group('the legacy facade no longer disagrees with the shared rules', () {
    test('InputValidator.validatePhone delegates to PhoneValidator', () {
      for (final n in <String?>['9876543210', '1234567890', '', null, 'abc']) {
        expect(
          InputValidator.validatePhone(n),
          PhoneValidator.validate(n),
          reason: '$n',
        );
      }
    });

    test('the old loose phone rule is gone', () {
      // Would have passed the pre-consolidation `^[+?]?[0-9]{10,12}$`.
      expect(InputValidator.validatePhone('1234567890'), isNotNull);
    });

    test('validateEmail and sanitizeQuery delegate too', () {
      expect(
        InputValidator.validateEmail('a@shop.museum'),
        EmailValidator.validate('a@shop.museum'),
      );
      expect(
        InputValidator.validateSearchQuery('a' * 101),
        SearchValidator.validate('a' * 101),
      );
      expect(
        InputValidator.sanitizeQuery('<b>x</b>'),
        SearchValidator.sanitize('<b>x</b>'),
      );
    });
  });
}
