import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/token_store.dart';
import '../../data/import_repository.dart';
import '../../domain/import_models.dart';

/// Contract for picking a local .xlsx workbook (injectable for tests).
abstract class WorkbookPickerService {
  Future<PickedWorkbook?> pick();
}

/// Production picker backed by the file_picker plugin (SAF on Android —
/// no storage permission required).
class PlatformWorkbookPicker implements WorkbookPickerService {
  const PlatformWorkbookPicker();

  @override
  Future<PickedWorkbook?> pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: false,
    );
    final file = result?.files.single;
    final path = file?.path;
    if (path == null || path.isEmpty) return null;
    return PickedWorkbook(path: path, name: file!.name);
  }
}

final workbookPickerProvider = Provider<WorkbookPickerService>(
  (ref) => const PlatformWorkbookPicker(),
);

/// Lifecycle of the import screen: pick → uploading → preview → confirming
/// → done, with recent jobs surfaced alongside.
enum ImportStatus { idle, uploading, preview, confirming, done, error }

class ImportState {
  const ImportState({
    required this.status,
    this.workbook,
    this.preview,
    this.result,
    this.jobs = const [],
    this.message,
  });

  final ImportStatus status;
  final PickedWorkbook? workbook;
  final ImportPreview? preview;
  final ImportConfirmResult? result;
  final List<ImportJob> jobs;

  /// Error copy when [status] is [ImportStatus.error].
  final String? message;

  factory ImportState.idle() => const ImportState(status: ImportStatus.idle);
}

final importControllerProvider =
    NotifierProvider<InventoryImportController, ImportState>(
      InventoryImportController.new,
    );

/// Drives the whole upload → preview → confirm flow for one shop.
class InventoryImportController extends Notifier<ImportState> {
  @override
  ImportState build() => ImportState.idle();

  @override
  set state(ImportState value) => super.state = value;

  InventoryImportRepository get _repo =>
      ref.read(inventoryImportRepositoryProvider);

  void _patch(ImportState Function(ImportState) updater) =>
      state = updater(state);

  /// Opens the file picker and uploads the selected workbook. On success
  /// the state moves to `preview`; on failure an error message is set.
  Future<void> pickAndUpload() async {
    final shopId = ref.read(selectedShopProvider)?.id;
    if (shopId == null) {
      _patch(
        (_) => const ImportState(
          status: ImportStatus.error,
          message: 'No shop selected',
        ),
      );
      return;
    }
    try {
      final workbook = await ref.read(workbookPickerProvider).pick();
      if (workbook == null) return; // user cancelled — stay idle
      _patch(
        (s) => ImportState(
          status: ImportStatus.uploading,
          workbook: workbook,
          jobs: s.jobs,
        ),
      );
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final preview = await _repo.upload(shopId, workbook, token);
      _patch(
        (s) => ImportState(
          status: ImportStatus.preview,
          workbook: s.workbook,
          preview: preview,
          jobs: s.jobs,
        ),
      );
    } on ApiException catch (e) {
      _patch(
        (s) => ImportState(
          status: ImportStatus.error,
          workbook: s.workbook,
          jobs: s.jobs,
          message: _friendly(e, fallback: 'Upload failed. Please retry.'),
        ),
      );
    } catch (_) {
      _patch(
        (s) => ImportState(
          status: ImportStatus.error,
          workbook: s.workbook,
          jobs: s.jobs,
          message: 'Upload failed. Please retry.',
        ),
      );
    }
  }

  /// Confirms the staged job (applies rows to inventory).
  Future<void> confirm() async {
    final shopId = ref.read(selectedShopProvider)?.id;
    final jobId = state.preview?.meta.id;
    if (shopId == null || jobId == null) return;
    _patch(
      (s) => ImportState(
        status: ImportStatus.confirming,
        workbook: s.workbook,
        preview: s.preview,
        jobs: s.jobs,
      ),
    );
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final result = await _repo.confirm(shopId, jobId, token);
      _patch(
        (s) => ImportState(
          status: ImportStatus.done,
          workbook: s.workbook,
          preview: s.preview,
          result: result,
          jobs: s.jobs,
        ),
      );
    } on ApiException catch (e) {
      _patch(
        (s) => ImportState(
          status: ImportStatus.error,
          workbook: s.workbook,
          preview: s.preview,
          jobs: s.jobs,
          message: _friendly(e, fallback: 'Could not apply the import.'),
        ),
      );
    } catch (_) {
      _patch(
        (s) => ImportState(
          status: ImportStatus.error,
          workbook: s.workbook,
          preview: s.preview,
          jobs: s.jobs,
          message: 'Could not apply the import.',
        ),
      );
    }
  }

  /// Loads the shop's recent import jobs (surfaced at the bottom).
  Future<void> loadJobs() async {
    final shopId = ref.read(selectedShopProvider)?.id;
    if (shopId == null) return;
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) return;
      final jobs = await _repo.listJobs(shopId, token);
      _patch(
        (s) => ImportState(
          status: s.status,
          workbook: s.workbook,
          preview: s.preview,
          result: s.result,
          jobs: jobs,
        ),
      );
    } on ApiException {
      // Recent-jobs list is auxiliary — never block the main flow.
    } catch (_) {
      // Same — non-critical.
    }
  }

  /// Back to the pick step (keeps recent jobs visible).
  void resetFlow() {
    final jobs = state.jobs;
    state = ImportState(status: ImportStatus.idle, jobs: jobs);
  }

  /// Clears ALL cached import state (called on logout).
  void reset() => state = ImportState.idle();

  /// Technical exceptions → shopkeeper-friendly copy.
  String _friendly(ApiException e, {required String fallback}) {
    if (e.isUnauthorized || e.statusCode == 401) {
      return 'Your session has expired. Please sign in again.';
    }
    if (e.isForbidden || e.statusCode == 403) {
      return 'You do not have permission to import inventory.';
    }
    if (e.statusCode == null) {
      return 'No internet connection. Check your network and retry.';
    }
    final message = e.message;
    if (message.isNotEmpty &&
        message != 'Network error' &&
        message.length < 160) {
      return message;
    }
    return fallback;
  }
}
