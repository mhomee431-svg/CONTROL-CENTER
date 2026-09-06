import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../controllers/auth_controller.dart';
import '../../data/auth_repository.dart';
import '../../data/mock_auth_repository.dart';
import '../../data/phone_utils.dart';

/// OTP verification — handles both LOGIN and REGISTRATION flows
/// (registration is detected via the pending name in auth state).
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.phoneNumber});

  final String phoneNumber;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;
    final phone = widget.phoneNumber.isNotEmpty
        ? widget.phoneNumber
        : (ref.read(authControllerProvider).phoneNumber ?? '');
    final ok = await ref
        .read(authControllerProvider.notifier)
        .submitOtp(phoneNumber: normalizeIndianPhone(phone), otp: _otpController.text.trim());
    if (!mounted) return;
    if (ok) {
      // Router guard lands on /shops or /shop-register automatically.
      context.go('/dashboard');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ref.read(authControllerProvider).errorMessage ??
              'Verification failed'),
        ),
      );
    }
  }

  Future<void> _resend() async {
    final phone = widget.phoneNumber.isNotEmpty
        ? widget.phoneNumber
        : (ref.read(authControllerProvider).phoneNumber ?? '');
    await ref
        .read(authControllerProvider.notifier)
        .sendOtp(normalizeIndianPhone(phone));
    if (!mounted) return;
    if (kUseMockAuth) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Your OTP is: ${MockAuthRepository.mockOtp}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          duration: const Duration(seconds: 8),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new code has been sent')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final isRegistration =
        state.pendingName != null && state.pendingName!.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Verify code')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                isRegistration
                    ? 'Welcome, ${state.pendingName}!'
                    : 'Enter the 6-digit code',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text('Sent to ${widget.phoneNumber.isEmpty ? state.phoneNumber ?? '' : widget.phoneNumber}'),
              // In mock mode the OTP is fixed & shown here permanently, so the
              // test flow never blocks on an SMS that cannot arrive.
              if (kUseMockAuth) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'DEMO CODE: ${MockAuthRepository.mockOtp}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              TextFormField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(letterSpacing: 8),
                decoration:
                    const InputDecoration(hintText: '••••••', counterText: ''),
                validator: (v) =>
                    (v ?? '').trim().length < 4 ? 'Enter the code' : null,
                onFieldSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: state.isLoading ? null : _verify,
                child: state.isLoading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Verify & continue'),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: _resend, child: const Text('Resend code')),
            ],
          ),
        ),
      ),
    );
  }
}
