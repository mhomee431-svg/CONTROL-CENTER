import 'dart:typed_data';

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
    this.jobsTotal = 0,
    this.loadingMoreJobs = false,
    this.message,
  });

  final ImportStatus status;
  final PickedWorkbook? workbook;
  final ImportPreview? preview;
  final ImportConfirmResult? result;

  /// The import jobs loaded SO FAR (newest first).
  final List<ImportJob> jobs;

  /// How many import jobs the shop has in total, per the SERVER's count across
  /// every page — not the number currently held.
  final int jobsTotal;

  /// True while the next page of jobs is in flight.
  final bool loadingMoreJobs;

  /// Error copy when [status] is [ImportStatus.error].
  final String? message;

  /// True when the server holds jobs this list has not fetched yet.
  bool get jobsHasMore => jobs.length < jobsTotal;

  /// Jobs still behind the page break — the count the footer offers.
  int get jobsHidden => jobsTotal - jobs.length;

  /// This state with the upload → preview → confirm flow fields replaced.
  ///
  /// The jobs list and its pagination counters are carried through UNTOUCHED:
  /// a step of the import flow must never silently reset how much history is
  /// loaded, which would hide "Load more" the moment an upload starts.
  ImportState flow({
    required ImportStatus status,
    PickedWorkbook? workbook,
    ImportPreview? preview,
    ImportConfirmResult? result,
    String? message,
  }) =>
      ImportState(
        status: status,
        workbook: workbook ?? this.workbook,
        preview: preview ?? this.preview,
        result: result ?? this.result,
        jobs: jobs,
        jobsTotal: jobsTotal,
        loadingMoreJobs: loadingMoreJobs,
        message: message,
      );

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
        (s) => s.flow(status: ImportStatus.uploading, workbook: workbook),
      );
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final preview = await _repo.upload(shopId, workbook, token);
      _patch(
        (s) => s.flow(status: ImportStatus.preview, preview: preview),
      );
    } on ApiException catch (e) {
      _patch(
        (s) => s.flow(
          status: ImportStatus.error,
          message: _friendly(e, fallback: 'Upload failed. Please retry.'),
        ),
      );
    } catch (_) {
      _patch(
        (s) => s.flow(
          status: ImportStatus.error,
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
    _patch((s) => s.flow(status: ImportStatus.confirming));
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final result = await _repo.confirm(shopId, jobId, token);
      _patch(
        (s) => s.flow(status: ImportStatus.done, result: result),
      );
    } on ApiException catch (e) {
      _patch(
        (s) => s.flow(
          status: ImportStatus.error,
          message: _friendly(e, fallback: 'Could not apply the import.'),
        ),
      );
    } catch (_) {
      _patch(
        (s) => s.flow(
          status: ImportStatus.error,
          message: 'Could not apply the import.',
        ),
      );
    }
  }

  /// Loads the FIRST page of the shop's import jobs.
  ///
  /// Always restarts at offset 0 and replaces the rows, so a refresh can never
  /// stack a previous page set under the current one.
  Future<void> loadJobs() async {
    final shopId = ref.read(selectedShopProvider)?.id;
    if (shopId == null) return;
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) return;
      final page = await _repo.listJobs(shopId, token);
      _patch(
        (s) => ImportState(
          status: s.status,
          workbook: s.workbook,
          preview: s.preview,
          result: s.result,
          jobs: page.jobs,
          jobsTotal: page.total,
          loadingMoreJobs: s.loadingMoreJobs,
        ),
      );
    } on ApiException {
      // Recent-jobs list is auxiliary — never block the main flow.
    } catch (_) {
      // Same — non-critical.
    }
  }

  /// Fetches the NEXT page of import jobs and appends it.
  ///
  /// Paginated by the BACKEND: the offset is the number already held, so each
  /// page is one bounded round trip. A no-op when nothing is left (so a footer
  /// tap at the end cannot loop), and a failed page keeps the jobs already on
  /// screen — the history must never blank because of one dropped request.
  Future<void> loadMoreJobs() async {
    final shopId = ref.read(selectedShopProvider)?.id;
    if (shopId == null) return;
    if (!state.jobsHasMore || state.loadingMoreJobs) return;
    _patch((s) => ImportState(
          status: s.status,
          workbook: s.workbook,
          preview: s.preview,
          result: s.result,
          jobs: s.jobs,
          jobsTotal: s.jobsTotal,
          loadingMoreJobs: true,
        ));
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) return;
      final page = await _repo.listJobs(
        shopId,
        token,
        offset: state.jobs.length,
      );
      // De-duplicate by id: a new job started while paging shifts the offset
      // window, and the same row could otherwise be appended twice.
      final seen = state.jobs.map((j) => j.id).toSet();
      _patch((s) => ImportState(
            status: s.status,
            workbook: s.workbook,
            preview: s.preview,
            result: s.result,
            jobs: [...s.jobs, ...page.jobs.where((j) => !seen.contains(j.id))],
            jobsTotal: page.total,
            loadingMoreJobs: false,
          ));
    } catch (_) {
      _patch((s) => ImportState(
            status: s.status,
            workbook: s.workbook,
            preview: s.preview,
            result: s.result,
            jobs: s.jobs,
            jobsTotal: s.jobsTotal,
            loadingMoreJobs: false,
          ));
    }
  }

  /// Back to the pick step (keeps recent jobs visible).
  ///
  /// The flow's own fields are cleared; the job history and its pagination
  /// counters are kept, so starting a new upload does not make the loaded
  /// history look complete when it is not.
  void resetFlow() {
    state = ImportState(
      status: ImportStatus.idle,
      jobs: state.jobs,
      jobsTotal: state.jobsTotal,
    );
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

/// Contract for writing a generated workbook to the device (injectable for
/// tests — the platform dialog is unavailable in widget tests).
abstract class WorkbookSaveService {
  /// Offers [bytes] to the shopkeeper as [fileName]. Returns `false` when the
  /// dialog was dismissed without saving (not an error).
  Future<bool> saveWorkbook(String fileName, Uint8List bytes);
}

/// Production saver backed by the file_picker plugin (SAF on Android —
/// the bytes are written by the plugin, no storage permission required).
class PlatformWorkbookSaver implements WorkbookSaveService {
  const PlatformWorkbookSaver();

  @override
  Future<bool> saveWorkbook(String fileName, Uint8List bytes) async {
    final path = await FilePicker.platform.saveFile(
      fileName: fileName,
      bytes: bytes,
    );
    return path != null && path.isNotEmpty;
  }
}

final workbookSaveProvider = Provider<WorkbookSaveService>(
  (ref) => const PlatformWorkbookSaver(),
);

/// Download Sample state — kept separate from the pick → preview → confirm
/// flow because the template never touches inventory.
class SampleDownloadState {
  const SampleDownloadState({this.inProgress = false, this.message});

  final bool inProgress;

  /// Set once an attempt finishes. `null` means "nothing to report"
  /// (idle, in progress, or the shopkeeper dismissed the save dialog).
  final String? message;
}

final sampleDownloadProvider =
    NotifierProvider<SampleDownloadController, SampleDownloadState>(
      SampleDownloadController.new,
    );

/// Fetches the sample workbook and hands it to the platform save dialog.
class SampleDownloadController extends Notifier<SampleDownloadState> {
  @override
  SampleDownloadState build() => const SampleDownloadState();

  /// Download Sample (Import Center). Never throws — the outcome is reported
  /// through [SampleDownloadState.message].
  Future<void> download() async {
    if (state.inProgress) return;
    final shopId = ref.read(selectedShopProvider)?.id;
    if (shopId == null) {
      state = const SampleDownloadState(
        message: 'Select a shop first.',
      );
      return;
    }
    state = const SampleDownloadState(inProgress: true);
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final bytes = await ref
          .read(inventoryImportRepositoryProvider)
          .downloadSample(shopId, token);
      final saved = await ref
          .read(workbookSaveProvider)
          .saveWorkbook(sampleWorkbookFileName, bytes);
      state = SampleDownloadState(
        message: saved ? 'Sample workbook saved' : null, // dismissed = silent
      );
    } on ApiException catch (e) {
      state = SampleDownloadState(
        message: _sampleFailure(e),
      );
    } catch (_) {
      state = const SampleDownloadState(
        message: 'Could not download the sample. Please retry.',
      );
    }
  }

  /// Called by the screen once the outcome snackbar has been shown, so a
  /// rebuild never re-shows it.
  void clearMessage() {
    if (state.message != null) state = const SampleDownloadState();
  }

  String _sampleFailure(ApiException e) {
    if (e.isUnauthorized || e.statusCode == 401) {
      return 'Your session has expired. Please sign in again.';
    }
    if (e.isForbidden || e.statusCode == 403) {
      return 'You do not have permission to import inventory.';
    }
    if (e.statusCode == null) {
      return 'No internet connection. Check your network and retry.';
    }
    return 'Could not download the sample. Please retry.';
  }
}
