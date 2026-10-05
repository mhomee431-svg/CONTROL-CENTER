import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/form_keyboard.dart';
import '../../../../core/theme/app_theme.dart';
import '../controllers/auth_controller.dart';
import '../controllers/post_login_destination.dart';

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

  /// A 6-digit OTP is exactly six digits.
  ///
  /// Named rather than repeated as a literal because the length is load-bearing in
  /// three places (the field cap, the auto-submit trigger and the validator), and
  /// a `6` in one of them drifting from the others is a silent bug.
  static const int _otpLength = 6;

  /// Guards against a second verification while one is already in flight.
  ///
  /// `onChanged` fires on EVERY keystroke, so reaching the sixth digit starts a
  /// request; without this guard a customer who backspaces and retypes a digit
  /// would start another one. That is not merely wasteful — `_handleVerifyOtp`
  /// increments `_attemptCount`, so a fast typist could burn every attempt on a
  /// single code and get locked out by their own corrections.
  bool _verifying = false;

  Future<void> _handleVerifyOtp() async {
    if (_verifying) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _verifying = true;
    _otpFocus.unfocus();

    if (_attemptCount >= _maxAttempts) {
      _verifying = false;
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
    try {
      await _authController.verifyOtp(
        phoneNumber: widget.phoneNumber,
        otpCode: _otpController.text,
        isNewUser: widget.isNewUser,
        name: widget.name,
      );
    } finally {
      // Release the guard whatever happened. Leaving it set would make every
      // later retry a silent no-op, and the customer would be stuck tapping
      // Verify with no response and no error.
      _verifying = false;
    }
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

        // `go` (not `push`) so the auth screens are not left on the stack for
        // Back to return to. Which page that lands on depends on where the
        // customer was BEFORE sign-in: a guest who tapped "Sign in" from their
        // saved items goes back to their saved items, not to Home.
        final destination = ref
            .read(postLoginDestinationProvider.notifier)
            .take();
        context.go(destination ?? '/');
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
        // The OTP field is the only thing on this screen that takes the keyboard,
        // so a tap on the surrounding space is almost always meant to dismiss
        // it. Without this the only exits are the IME key and the system back
        // gesture, which makes the empty space look inert.
        child: FormKeyboard.dismissOnBackgroundTap(
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
                    maxLength: _otpLength,
                    textAlign: TextAlign.center,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    // OTP IS NOT AN ORDINARY TEXT FORM, and the usual next/done
                    // wiring would be actively wrong here:
                    //
                    //  * There is exactly ONE field, so `next` has nowhere to go and
                    //    `done` would just close the keyboard — leaving a
                    //    half-entered code with no feedback.
                    //  * A 6-digit OTP is one atomic value, not a step in a form.
                    //    The moment the sixth digit lands, the form is complete,
                    //    so the key becomes VERIFY rather than dismiss. That is what
                    //    `done` therefore VERIFIES a complete code instead of
                    //    merely dismissing, and only dismisses when incomplete.
                    //  * `done` still closes the keyboard on the way, so the
                    //    customer is not trapped with the IME up.
                    textInputAction: TextInputAction.done,
                    onEditingComplete: () {
                      // Submit only once the code is actually complete; otherwise
                      // this is just a way to dismiss the keyboard.
                      if (_otpController.text.length == _otpLength) {
                        _handleVerifyOtp();
                      } else {
                        _otpFocus.unfocus();
                      }
                    },
                    scrollPadding: FormKeyboard.scrollPaddingFor(context),
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
      ),
    );
  }
}
