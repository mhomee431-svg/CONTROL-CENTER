import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../controllers/auth_controller.dart';

/// OTP verification screen with countdown, resend, and error handling.
class OtpVerificationScreen extends ConsumerStatefulWidget {
  final String phoneNumber;
  final String? name;
  final bool isNewUser;

  const OtpVerificationScreen({
    super.key,
    required this.phoneNumber,
    this.name,
    this.isNewUser = false,
  });

  @override
  ConsumerState<OtpVerificationScreen> createState() =>
      _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends ConsumerState<OtpVerificationScreen> {
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _otpFocus = FocusNode();
  Timer? _resendTimer;
  int _resendCountdown = _resendSeconds;
  int _attemptCount = 0;
  static const int _maxAttempts = 5;

  /// Firebase throttles resends; the UI mirrors that with a full-minute
  /// countdown before "Resend OTP" becomes tappable again.
  static const int _resendSeconds = 60;

  late final AuthController _authController;

  /// Set once the state listener observes a successful login — a logged-in
  /// customer's screen teardown must NOT cancel the freshly created session.
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _authController = ref.read(authControllerProvider.notifier);
    _startResendTimer();
  }

  @override
  void dispose() {
    // Backing out = cancelled flow: drop the pending Firebase verification and
    // any error state so nothing can complete in the background.
    if (!_loggedIn) {
      _authController.cancelOtpVerification();
    }
    _otpController.dispose();
    _otpFocus.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    _resendCountdown = _resendSeconds;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCountdown <= 1) {
        timer.cancel();
        setState(() => _resendCountdown = 0);
      } else {
        setState(() => _resendCountdown--);
      }
    });
  }

  /// A code that expired can never succeed — let the customer resend at once
  /// instead of staring at a countdown.
  void _allowImmediateResend() {
    _resendTimer?.cancel();
    setState(() => _resendCountdown = 0);
  }

  Future<void> _handleVerifyOtp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _otpFocus.unfocus();

    if (_attemptCount >= _maxAttempts) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Too many incorrect attempts. Please request a new OTP.',
          ),
        ),
      );
      return;
    }

    _attemptCount++;
    // Success/failure handling lives in the state listener below (single
    // navigation point + recovery affordances).
    await _authController.verifyOtp(
      phoneNumber: widget.phoneNumber,
      otpCode: _otpController.text,
      isNewUser: widget.isNewUser,
      name: widget.name,
    );
  }

  Future<void> _handleResendOtp() async {
    if (_resendCountdown > 0) return;
    final success = await _authController.sendOtp(widget.phoneNumber);
    if (success && mounted) {
      _attemptCount = 0;
      _otpController.clear();
      setState(_startResendTimer);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('A new OTP has been sent.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next.status == AuthStatus.authenticated) {
        // Single navigation point — also covers platform auto-verification,
        // which authenticates without the customer typing a code.
        _loggedIn = true;
        context.go('/');
        return;
      }
      if (next.status != AuthStatus.error) return;

      switch (next.errorKind) {
        case AuthErrorKind.invalidOtp:
          // Wrong code: clear the field so the customer can retype it.
          _otpController.clear();
          _otpFocus.requestFocus();
          break;
        case AuthErrorKind.expiredOtp:
        case AuthErrorKind.sessionExpired:
          // The code can never succeed — offer a resend immediately.
          _allowImmediateResend();
          break;
        default:
          // Message-only recovery: the banner (below) explains what to do.
          break;
      }
    });

    // Friendly, already-sanitised message (never a raw Firebase error).
    final errorText = authState.status == AuthStatus.error
        ? authState.errorMessage
        : null;

    final title = widget.isNewUser ? 'Verify your number' : 'Verify OTP';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Enter the 6-digit code sent to ${widget.phoneNumber}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                TextFormField(
                  controller: _otpController,
                  focusNode: _otpFocus,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  style: const TextStyle(
                    fontSize: 24,
                    letterSpacing: 8,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    labelText: 'OTP',
                    border: const OutlineInputBorder(),
                    counterText: '',
                    errorText: errorText,
                    errorMaxLines: 3,
                  ),
                  validator: (value) => value != null && value.length == 6
                      ? null
                      : 'Enter the 6-digit OTP',
                ),
                const SizedBox(height: AppSpacing.md),
                ElevatedButton(
                  onPressed: authState.status == AuthStatus.loading
                      ? null
                      : _handleVerifyOtp,
                  child: authState.status == AuthStatus.loading
                      ? const CircularProgressIndicator.adaptive()
                      : const Text('Verify & Login'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextButton(
                  onPressed:
                      _resendCountdown > 0 ||
                          authState.status == AuthStatus.loading
                      ? null
                      : _handleResendOtp,
                  child: Text(
                    _resendCountdown > 0
                        ? 'Resend OTP in ${_resendCountdown}s'
                        : 'Resend OTP',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
