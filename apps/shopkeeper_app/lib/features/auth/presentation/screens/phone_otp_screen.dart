import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/router/route_names.dart';
import '../../data/phone_utils.dart';
import '../../domain/phone_otp.dart';
import '../controllers/auth_controller.dart';
import '../widgets/auth_widgets.dart';

/// Phone-OTP sign-in — the SMS twin of the Google flow.
///
/// Two steps on one screen:
///
///   1. phone number → `requestPhoneOtp` (a real SMS is sent by the provider)
///   2. 6-digit code → `verifyPhoneOtp` (Firebase verifies the code, then the
///      resulting ID token is exchanged on the SAME `/firebase-login` endpoint
///      Google uses).
///
/// Nothing here is OTP-specific below the provider: session storage, restore,
/// the startup guard and 401 handling are shared. The screen therefore never
/// navigates on success — the controller reports `authenticated` and the
/// router's redirect takes over, exactly like Google Sign-In.
///
/// Why the code step can be skipped: Android instant verification / an iOS
/// silent APNs push can verify the number without user input. The service
/// reports that as [PhoneOtpRequest.isAutoVerified] and the screen signs in
/// immediately rather than showing a code field nobody can fill.
class PhoneOtpScreen extends ConsumerStatefulWidget {
  const PhoneOtpScreen({super.key});

  static const phoneFieldKey = Key('otp-phone-field');
  static const sendButtonKey = Key('otp-send-button');
  static const codeFieldKey = Key('otp-code-field');
  static const verifyButtonKey = Key('otp-verify-button');
  static const resendButtonKey = Key('otp-resend-button');
  static const changeNumberKey = Key('otp-change-number');
  static const errorKey = Key('otp-error');
  static const unsupportedKey = Key('otp-unsupported');

  @override
  ConsumerState<PhoneOtpScreen> createState() => _PhoneOtpScreenState();
}

class _PhoneOtpScreenState extends ConsumerState<PhoneOtpScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  /// The pending SMS session — null means "still on step 1".
  PhoneOtpRequest? _request;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  bool get _onCodeStep => _request != null;

  Future<void> _sendCode({int? resendToken}) async {
    final phone = normalizeIndianPhone(_phoneController.text);
    // normalizeIndianPhone returns "+91XXXXXXXXXX" only for a valid 10-digit
    // Indian mobile; anything else comes back un-normalised on purpose.
    if (!phone.startsWith('+91') || phone.length != 13) {
      setState(() => _error = 'Enter a valid 10-digit mobile number.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final request = await ref
          .read(authControllerProvider.notifier)
          .requestPhoneOtp(phone, resendToken: resendToken);
      if (!mounted) return;

      // Instant verification: the platform already proved this number, so there
      // is no code to type — sign in immediately and keep the button busy until
      // the router redirect (or an error) lands.
      if (request.isAutoVerified) {
        setState(() {
          _request = null;
          _error = null;
          _busy = true;
        });
        final ok = await ref
            .read(authControllerProvider.notifier)
            .loginWithPhoneOtp(firebaseIdToken: request.autoVerifiedIdToken!);
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = ok
              ? null
              : ref.read(authControllerProvider).errorMessage ??
                  'Phone sign-in could not be completed. Please try again.';
        });
        return;
      }

      setState(() {
        _request = request;
        _busy = false;
      });
    } on PhoneOtpException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not send the code. Please try again.';
        _busy = false;
      });
    }
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from the SMS.');
      return;
    }
    final verificationId = _request?.verificationId;
    if (verificationId == null) {
      setState(() =>
          _error = 'This verification expired. Please request a new code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref.read(authControllerProvider.notifier).verifyPhoneOtp(
          verificationId: verificationId,
          code: code,
        );
    if (!mounted) return;
    // Clear busy even on success: the router is about to replace this screen,
    // and any host that keeps it mounted (previews, widget tests) must not be
    // left with a spinner that never stops.
    setState(() {
      _busy = false;
      _error = ok
          ? null
          : ref.read(authControllerProvider).errorMessage ??
              'The code could not be verified. Please try again.';
    });
  }

  void _changeNumber() {
    setState(() {
      _request = null;
      _codeController.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supported =
        ref.read(authControllerProvider.notifier).isPhoneOtpSupported;
    final isLoading =
        ref.watch(authControllerProvider.select((s) => s.isLoading));

    return Scaffold(
      appBar: AppBar(
        title: Text(appText(context).commonSignInWithPhone),
        leading: IconButton(
          // Accessible name for a text-free control.
          tooltip: appText(context).commonBack2,
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.welcome),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!supported)
                const _UnsupportedNotice()
              else ...[
                Text(
                  _onCodeStep ? 'Enter the code' : 'What is your number?',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  _onCodeStep
                      ? 'We sent a 6-digit code to ${_request!.phoneNumber}.'
                      : 'We will send a one-time code by SMS to verify your '
                          'number.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 24),
                if (!_onCodeStep) ...[
                  _phoneField(),
                  const SizedBox(height: 20),
                  FilledButton(
                    key: PhoneOtpScreen.sendButtonKey,
                    onPressed: _busy ? null : () => _sendCode(),
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(appText(context).commonSendCode),
                  ),
                ] else ...[
                  _codeField(),
                  const SizedBox(height: 20),
                  FilledButton(
                    key: PhoneOtpScreen.verifyButtonKey,
                    onPressed: (_busy || isLoading) ? null : _verify,
                    child: (_busy || isLoading)
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(appText(context).commonVerifyContinue),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        key: PhoneOtpScreen.resendButtonKey,
                        onPressed: _busy
                            ? null
                            : () =>
                                _sendCode(resendToken: _request?.resendToken),
                        child: Text(appText(context).commonResendCode),
                      ),
                      TextButton(
                        key: PhoneOtpScreen.changeNumberKey,
                        onPressed: _busy ? null : _changeNumber,
                        child: Text(appText(context).commonChangeNumber),
                      ),
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  AuthErrorBanner(
                    key: PhoneOtpScreen.errorKey,
                    message: _error!,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _phoneField() => TextField(
        key: PhoneOtpScreen.phoneFieldKey,
        controller: _phoneController,
        keyboardType: TextInputType.phone,
        enabled: !_busy,
        autofocus: true,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          // 12 digits so BOTH common forms work: the bare 10-digit number and
          // the +91 form people paste from their contacts. `normalizeIndianPhone`
          // also accepts a leading trunk 0 (11 digits).
          LengthLimitingTextInputFormatter(12),
        ],
        decoration: InputDecoration(
          labelText: appText(context).commonMobileNumber,
          hintText: appText(context).common99999999992,
          prefixText: '+91 ',
        ),
        onSubmitted: (_) => _sendCode(),
      );

  Widget _codeField() => TextField(
        key: PhoneOtpScreen.codeFieldKey,
        controller: _codeController,
        keyboardType: TextInputType.number,
        enabled: !_busy,
        autofocus: true,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        decoration: InputDecoration(
          labelText: appText(context).common6DigitCode,
          hintText: appText(context).common123456,
        ),
        onSubmitted: (_) => _verify(),
      );
}

/// Shown on platforms that cannot receive an SMS code (desktop/web builds
/// without Phone Auth configured). Google stays available there, so the screen
/// explains the limitation instead of dead-ending.
class _UnsupportedNotice extends StatelessWidget {
  const _UnsupportedNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: PhoneOtpScreen.unsupportedKey,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.phonelink_erase_outlined,
                  color: theme.colorScheme.outline),
              const SizedBox(width: 10),
              Text(
                appText(context).phoneOtpScreenPhoneSignInUnavailable,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            appText(context).phoneOtpScreenThisDeviceCannotReceiveAn,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}