import 'package:hyperlocal_shared_models/hyperlocal_shared_models.dart';
import 'package:test/test.dart';

void main() {
  group('ApiEnvelope', () {
    test('parses a success envelope', () {
      final e = ApiEnvelope.fromJson({
        'success': true,
        'message': 'Success',
        'data': {'id': 7},
      });
      expect(e.success, isTrue);
      expect(e.isError, isFalse);
      expect(e.message, 'Success');
      expect(e.errorCode, isNull);
      expect(e.dataAs<Map<String, dynamic>>()?['id'], 7);
    });

    test('parses an error envelope', () {
      final e = ApiEnvelope.fromJson({
        'success': false,
        'message': 'Shop not found',
        'error_code': 'SHOP_NOT_FOUND',
        'data': null,
      });
      expect(e.success, isFalse);
      expect(e.isError, isTrue);
      expect(e.errorCode, 'SHOP_NOT_FOUND');
      expect(e.data, isNull);
    });

    test('rejects non-object payloads', () {
      expect(() => ApiEnvelope.fromJson([1, 2]), throwsArgumentError);
    });
  });

  group('PaginatedEnvelope', () {
    test('parses paginated_response() shape', () {
      final p = PaginatedEnvelope.fromJson({
        'success': true,
        'message': 'Success',
        'data': {
          'items': [
            {'id': 1},
            {'id': 2},
          ],
          'pagination': {
            'total': 100,
            'page': 1,
            'limit': 20,
            'pages': 5,
            'has_next': true,
            'has_prev': false,
          },
        },
      });
      expect(p.success, isTrue);
      expect(p.items.length, 2);
      expect(p.pagination!.total, 100);
      expect(p.pagination!.pages, 5);
      expect(p.pagination!.hasNext, isTrue);
      expect(p.pagination!.hasPrev, isFalse);
    });
  });
}
