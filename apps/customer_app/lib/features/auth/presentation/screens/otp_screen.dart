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
  ConsumerState<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends ConsumerState<OtpVerificationScreen> {
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  Timer? _resendTimer;
  int _resendCountdown = 30;
  int _attemptCount = 0;
  static const int _maxAttempts = 5;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    _otpController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendCountdown = 30;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_resendCountdown <= 0) {
        timer.cancel();
        setState(() {});
      } else {
        setState(() => _resendCountdown--);
      }
    });
  }

  Future<void> _handleVerifyOtp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_attemptCount >= _maxAttempts) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Too many incorrect attempts. Please request a new OTP.'),
        ),
      );
      return;
    }

    _attemptCount++;
    final success = await ref
        .read(authControllerProvider.notifier)
        .verifyOtp(
          phoneNumber: widget.phoneNumber,
          otpCode: _otpController.text,
          isNewUser: widget.isNewUser,
        );

    if (success && mounted) {
      context.go('/');
    }
  }

  Future<void> _handleResendOtp() async {
    if (_resendCountdown > 0) return;
    final success = await ref
        .read(authControllerProvider.notifier)
        .sendOtp(widget.phoneNumber);
    if (success && mounted) {
      _attemptCount = 0;
      _startResendTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP resent successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next.status == AuthStatus.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage ?? 'Verification failed')),
        );
      }
    });

    final title = widget.isNewUser
        ? 'Verify your number'
        : 'Verify OTP';

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
                  'Enter the 6-digit code sent to +91 ${widget.phoneNumber}',
                  style: const TextStyle(fontSize: 16, color: AppColors.textMuted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                TextFormField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    labelText: 'OTP',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                  validator: (value) =>
                      value != null && value.length == 6 ? null : 'Enter the 6-digit OTP',
                ),
                const SizedBox(height: AppSpacing.md),
                ElevatedButton(
                  onPressed: authState.status == AuthStatus.loading ? null : _handleVerifyOtp,
                  child: authState.status == AuthStatus.loading
                      ? const CircularProgressIndicator.adaptive()
                      : const Text('Verify & Login'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextButton(
                  onPressed: _resendCountdown > 0 || authState.status == AuthStatus.loading
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