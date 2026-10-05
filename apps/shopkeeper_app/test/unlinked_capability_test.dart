import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/errors/app_message_code.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_endpoints.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/media_upload_service.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/media/data/media_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/pos/data/pos_repository.dart';

/// UNLINKED-BUT-COMPLETE CODE — pinned so it cannot rot while it waits for its
/// UI.
///
/// A repository method no screen calls yet is not dead code; it is a finished
/// capability parked for a later feature. But parked AND UNTESTED is how
/// working code quietly becomes broken: the backend renames a field, the model
/// stops parsing, and nothing notices until the screen finally appears.
///
/// These are exercised through their REAL implementations ([ApiMediaRepository],
/// [ApiPosRepository]) rather than a fake, so what gets pinned is the actual
/// request path and the actual envelope parsing.
void main() {
  group('MediaRepository.readUrl — authorized short-lived read URL', () {
    test('asks the backend for the key and parses the object', () async {
      final api = FakeApiClient({
        'key': 'products/10/photo.jpg',
        'url': 'https://cdn.example.com/signed/abc',
        'category': 'PRODUCT_IMAGE',
        'size': 2048,
        'content_type': 'image/jpeg',
      });
      final repo = ApiMediaRepository(
        MediaUploadService(apiClient: api, dio: Dio()),
        _FakeTokenStore('tok-123'),
      );

      final object = await repo.readUrl(key: 'products/10/photo.jpg');

      expect(api.lastGetPath, ApiEndpoints.mediaUrl);
      // The key travels as a query parameter, never interpolated into a path.
      expect(api.lastGetQuery, {'key': 'products/10/photo.jpg'});
      expect(api.lastGetToken, 'tok-123');
      expect(object.key, 'products/10/photo.jpg');
      expect(object.url, 'https://cdn.example.com/signed/abc');
      expect(object.size, 2048);
      expect(object.contentType, 'image/jpeg');
    });

    test('a signed-out store fails BEFORE any request leaves the app', () async {
      final api = FakeApiClient({'key': 'k', 'url': 'u'});
      final repo = ApiMediaRepository(
        MediaUploadService(apiClient: api, dio: Dio()),
        _FakeTokenStore(null),
      );

      // The auth seam: with no token the call must never go out, or the app
      // spends a round trip to learn what it already knows.
      await expectLater(
        repo.readUrl(key: 'k'),
        throwsA(
          // `ApiException.localized` carries the code in `messageCode` (and
          // renders the English copy into `message`); `errorCode` is the
          // SERVER's own code and is null for a client-side refusal.
          isA<ApiException>()
              .having((e) => e.messageCode, 'messageCode',
                  AppMessageCode.notSignedIn)
              .having((e) => e.message, 'message', isNotEmpty),
        ),
      );
      expect(api.lastGetPath, isNull, reason: 'no request may be attempted');
    });
  });

  group('PosRepository.getIntegration — single integration read', () {
    test('reads the integration by id and parses it', () async {
      final api = FakeApiClient({
        'id': 4,
        'shop_id': 10,
        'provider_code': 'PETPOOCH',
        'provider_name': 'Pet Food Store',
        'sync_enabled': true,
        'sync_interval_minutes': 60,
        'status': 'CONNECTED',
      });
      final repo = ApiPosRepository(api);

      final integration = await repo.getIntegration(4, 'tok');

      expect(api.lastGetPath, ApiEndpoints.posIntegration(4));
      expect(api.lastGetToken, 'tok');
      expect(integration.id, 4);
      expect(integration.shopId, 10);
      expect(integration.providerCode, 'PETPOOCH');
      expect(integration.providerName, 'Pet Food Store');
      expect(integration.syncEnabled, isTrue);
      expect(integration.syncIntervalMinutes, 60);
      expect(integration.status, 'CONNECTED');
    });

    test('the id is scoped into the path, not the query', () async {
      final api = FakeApiClient({'id': 9});
      await ApiPosRepository(api).getIntegration(9, 'tok');
      expect(api.lastGetPath, contains('/9'));
      expect(api.lastGetPath, isNot(contains('shop_id')));
    });
  });
}

/// Minimal [ApiClient] double: repositories only call these six verbs, so
/// recording the last request is enough to pin the contract.
class FakeApiClient implements ApiClient {
  FakeApiClient(this.response);

  final Map<String, dynamic> response;
  String? lastGetPath;
  Map<String, dynamic>? lastGetQuery;
  String? lastPatchPath;
  Object? lastPatchBody;
  String? lastGetToken;

  @override
  Dio get dio => throw UnimplementedError('not used by repositories in tests');

  @override
  void Function(ApiException error)? get onUnauthorized => null;

  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? query, String? token}) async {
    lastGetPath = path;
    lastGetQuery = query;
    lastGetToken = token;
    return response;
  }

  @override
  Future<dynamic> post(String path, {Object? body, String? token}) async =>
      response;

  @override
  Future<dynamic> patch(String path, {Object? body, String? token}) async {
    lastPatchPath = path;
    lastPatchBody = body;
    return response;
  }

  @override
  Future<dynamic> put(String path, {Object? body, String? token}) async =>
      response;

  @override
  Future<dynamic> delete(String path, {String? token}) async => response;

  @override
  Future<dynamic> postMultipart(
    String path, {
    required FormData form,
    String? token,
  }) async =>
      response;

  @override
  Future<void> postFormToExternal(String url, {required FormData form}) async {}
}

/// A [TokenStore] with one real answer, so the repository's own auth seam is
/// genuinely exercised rather than stubbed out above it.
class _FakeTokenStore implements TokenStore {
  _FakeTokenStore(this._accessToken);

  final String? _accessToken;

  @override
  Future<String?> readAccessToken() async => _accessToken;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<String?> readSessionId() async => null;

  @override
  Future<String?> readBusinessId() async => null;

  @override
  Future<String?> readUserId() async => null;

  @override
  Future<bool> isLoggedIn() async => _accessToken != null;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {}

  @override
  Future<void> saveSessionId(String sessionId) async {}

  @override
  Future<void> saveBusinessId(String businessId) async {}

  @override
  Future<void> saveUserId(String userId) async {}

  @override
  Future<void> setLoggedIn(bool value) async {}

  @override
  Future<void> clearAll() async {}
}
