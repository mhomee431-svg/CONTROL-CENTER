import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../controllers/auth_controller.dart';
import '../../../../core/theme/app_theme.dart';

class OtpVerificationScreen extends ConsumerStatefulWidget {
  final String phoneNumber;
  const OtpVerificationScreen({super.key, required this.phoneNumber});

  @override
  ConsumerState<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends ConsumerState<OtpVerificationScreen> {
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  Timer? _resendTimer;
  int _resendCountdown = 30;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  void _startResendTimer() {
    _resendCountdown = 30;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown <= 0) {
        timer.cancel();
        if (mounted) setState(() {});
      } else {
        setState(() => _resendCountdown--);
      }
    });
  }

  void _handleVerifyOtp() async {
    if (_formKey.currentState!.validate()) {
      final success = await ref
          .read(authControllerProvider.notifier)
          .verifyOtp(widget.phoneNumber, _otpController.text);
      if (success && mounted) {
        context.go('/');
      }
    }
  }

  void _handleResendOtp() async {
    if (_resendCountdown > 0) return;
    final success = await ref
        .read(authControllerProvider.notifier)
        .sendOtp(widget.phoneNumber);
    if (success && mounted) {
      _startResendTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP resent successfully')),
      );
    }
  }

  @override
  void dispose() {
    _otpController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next.status == AuthStatus.error) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.errorMessage!)));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Verify OTP')),
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