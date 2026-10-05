import '../../../../../core/errors/app_message_code.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../../products/presentation/controllers/products_controller.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/validation/field_rules.dart';
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
    // `size` is reported even with `withData: false`, and it is what lets the
    // 5 MB cap be checked before the upload.
    return PickedWorkbook(
      path: path,
      name: file!.name,
      sizeBytes: file.size,
    );
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
    this.schema,
    this.remapping = false,
    this.mappingError,
    this.jobs = const [],
    this.jobsTotal = 0,
    this.loadingMoreJobs = false,
    this.message,
  });

  final ImportStatus status;
  final PickedWorkbook? workbook;
  final ImportPreview? preview;
  final ImportConfirmResult? result;

  /// Backend import schema — the vocabulary and rules the Column Mapping step
  /// renders. Null until fetched (or if the fetch failed), in which case the
  /// panel falls back to the raw `column_mapping` the upload returned rather
  /// than inventing rules it does not have.
  final ImportSchema? schema;

  /// True while a corrected Column Mapping is being re-staged.
  final bool remapping;

  /// Why the last correction failed, or null. Separate from [message] because a
  /// rejected mapping is NOT a failed import — the rows are untouched and the
  /// shopkeeper can simply try again, so it must not knock the flow into its
  /// terminal error state.
  final String? mappingError;

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
        // The schema is fetched ONCE and survives every step of the flow. It is
        // not a per-upload artefact, so dropping it here would re-fetch on each
        // transition and leave the mapping panel empty exactly when it is needed.
        schema: schema,
        remapping: remapping,
        mappingError: mappingError,
        jobs: jobs,
        jobsTotal: jobsTotal,
        loadingMoreJobs: loadingMoreJobs,
        message: message,
      );

  /// This state with only the schema replaced — the schema is fetched
  /// independently of the pick -> preview -> confirm flow.
  ImportState withSchema(ImportSchema? value) => ImportState(
    status: status,
    workbook: workbook,
    preview: preview,
    result: result,
    schema: value,
    remapping: remapping,
    mappingError: mappingError,
    jobs: jobs,
    jobsTotal: jobsTotal,
    loadingMoreJobs: loadingMoreJobs,
    message: message,
  );

  /// This state with the mapping-correction fields replaced.
  ///
  /// Separate from [flow] on purpose: correcting the mapping does not move the
  /// import along its pick -> preview -> confirm path, and must not disturb the
  /// jobs list or the flow status the preview screen is rendering.
  ImportState withMapping({
    bool? remapping,
    String? mappingError,
    bool clearMappingError = false,
    ImportPreview? preview,
  }) => ImportState(
    status: status,
    workbook: workbook,
    preview: preview ?? this.preview,
    result: result,
    schema: schema,
    remapping: remapping ?? this.remapping,
    mappingError: clearMappingError
        ? null
        : (mappingError ?? this.mappingError),
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

  /// Fetch the import schema — the Column Mapping step's ONLY source of
  /// field names, accepted header spellings and validation rules.
  ///
  /// Idempotent and non-blocking: a second call while one is in flight, or a
  /// schema already held, returns immediately. A FAILURE is deliberately
  /// silent here — the mapping panel falls back to the raw `column_mapping`
  /// the upload already returned, which is less informative than the schema
  /// but is never wrong, and a schema outage must not block an import.
  Future<void> loadSchema() async {
    if (state.schema != null) return;
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) return; // not signed in — the flow reports it later
      final schema = await ref
          .read(inventoryImportRepositoryProvider)
          .schema(token);
      // Only apply if nothing arrived meanwhile; the first fetch wins so
      // concurrent calls cannot flip the panel between two payloads.
      if (state.schema == null) state = state.withSchema(schema);
    } catch (_) {
      // Schema is an enhancement over `column_mapping`; the preview still
      // works without it. Never surface this as a flow error.
    }
  }

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
      if (workbook == null) return;
      // Check type and size locally first. The backend enforces both anyway;
      // this just turns a multi-megabyte upload that ends in a rejection into
      // an instant message before a single byte leaves the device.
      final fileProblem = importWorkbook(
        workbook.name,
        bytes: workbook.sizeBytes,
      );
      if (fileProblem != null) {
        _patch(
          (_) => ImportState(status: ImportStatus.error, message: fileProblem),
        );
        return;
      } // user cancelled — stay idle
      _patch(
        (s) => s.flow(status: ImportStatus.uploading, workbook: workbook),
      );
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw ApiException.localized(AppMessageCode.notSignedIn);
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
      if (token == null) throw ApiException.localized(AppMessageCode.notSignedIn);
      final result = await _repo.confirm(shopId, jobId, token);
      _patch(
        (s) => s.flow(status: ImportStatus.done, result: result),
      );
      // DATA CONSISTENCY: the import wrote products and stock server-side, so
      // the ONE local source for products / inventory / prices is now stale.
      // The app is a StatefulShellBranch, so the Products tab is still mounted
      // behind this pushed route and its initState will NOT re-run on the way
      // back - without this the shopkeeper would keep seeing pre-import rows.
      //
      // A QUEUED job is still running server-side; refreshing now would race it
      // and cache pre-import numbers. That case reconciles at the next natural
      // read (screen entry / pull-to-refresh) instead.
      if (!result.queued) {
        unawaited(
          ref.read(productsControllerProvider.notifier).refresh(),
        );
      }
      // The jobs list is carried through `flow()` untouched, so the import
      // history is refreshed here too rather than waiting for the user to
      // reopen the history screen.
      unawaited(loadJobs());
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

  /// Submit a corrected Column Mapping and adopt the re-staged rows.
  ///
  /// Returns true when the backend accepted it. On success the preview is
  /// REPLACED rather than merged: re-validating under a different mapping
  /// changes which rows are valid, so keeping the old counts would show the
  /// shopkeeper a preview that no longer describes what is about to be applied.
  ///
  /// Failure deliberately leaves the flow where it was. A rejected mapping
  /// changed nothing - no row was touched - so it must not knock the import
  /// into its terminal error state and lose the review the shopkeeper was
  /// doing.
  Future<bool> remapColumns(Map<int, String?> assignment) async {
    if (state.remapping) return false;
    final shopId = ref.read(selectedShopProvider)?.id;
    final jobId = state.preview?.meta.id;
    if (shopId == null || jobId == null) return false;

    state = state.withMapping(remapping: true, clearMappingError: true);
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw ApiException.localized(AppMessageCode.notSignedIn);
      // Invert the column-keyed draft into the field-keyed shape the API takes.
      // A column the shopkeeper left unassigned is omitted entirely, which the
      // backend reads as "do not import this field".
      final payload = <String, int?>{
        for (final entry in assignment.entries)
          if (entry.value != null) entry.value!: entry.key,
      };
      final preview = await _repo.remap(shopId, jobId, payload, token);
      state = state.withMapping(remapping: false, preview: preview);
      return true;
    } on ApiException catch (e) {
      state = state.withMapping(
        remapping: false,
        mappingError: _friendly(e, fallback: 'Could not update the mapping.'),
      );
      return false;
    } catch (_) {
      state = state.withMapping(
        remapping: false,
        mappingError: 'Could not update the mapping.',
      );
      return false;
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
      return appMessageEnglish(AppMessageCode.sessionExpired);
    }
    if (e.isForbidden || e.statusCode == 403) {
      return 'You do not have permission to import inventory.';
    }
    if (e.statusCode == null) {
      return appMessageEnglish(AppMessageCode.noInternet);
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
      if (token == null) throw ApiException.localized(AppMessageCode.notSignedIn);
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
      return appMessageEnglish(AppMessageCode.sessionExpired);
    }
    if (e.isForbidden || e.statusCode == 403) {
      return 'You do not have permission to import inventory.';
    }
    if (e.statusCode == null) {
      return appMessageEnglish(AppMessageCode.noInternet);
    }
    return 'Could not download the sample. Please retry.';
  }
}
