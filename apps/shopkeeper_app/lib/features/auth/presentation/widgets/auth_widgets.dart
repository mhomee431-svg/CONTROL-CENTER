import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../domain/auth_methods.dart';
import '../../domain/auth_models.dart';

/// ── SHARED AUTHENTICATION WIDGETS ────────────────────────────────────────
///
/// The Welcome, Sign-in and Phone-OTP screens offer the same methods, so the
/// buttons, the "or" separator and the failure banner live here: one wording,
/// one look, one place to change. Screen-specific composition (which methods
/// are visible, what happens on success) stays in the screens.
///
/// Every label comes from [AuthMethodActionLabel] so a method can never be
/// called two different things in two screens.

/// Google's official "G" mark drawn with the four brand colours so the app
/// needs no external asset.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    const blue = AppColors.googleBlue;
    const red = AppColors.googleRed;
    const yellow = AppColors.googleYellow;
    const green = AppColors.googleGreen;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: GoogleGPainter(blue, red, yellow, green),
      ),
    );
  }
}

/// Primary Google action. Shows a spinner instead of the label while
/// [isLoading], and is disabled then, so one tap cannot start two exchanges.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.isLoading,
    this.onPressed,
  });

  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: isLoading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        // Height is a *minimum*, so the label can grow with the system font
        // scale instead of clipping inside a fixed box (see TextScalePolicy).
        minimumSize: const Size.fromHeight(52),
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.googleInk,
        side: const BorderSide(color: AppColors.googleBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 1,
        shadowColor: AppShadows.inkStrong,
      ),
      child: isLoading
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const GoogleLogo(size: 20),
                const SizedBox(width: 12),
                Text(
                  AuthMethod.googleFirebase.actionLabel,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.googleInk,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                ),
              ],
            ),
    );
  }
}

/// Primary Phone-OTP action — the entry point to `/phone-otp`.
class PhoneSignInButton extends StatelessWidget {
  const PhoneSignInButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        // Height is a *minimum*, so the label can grow with the system font
        // scale instead of clipping inside a fixed box (see TextScalePolicy).
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sms_outlined, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Text(
            AuthMethod.phoneOtp.actionLabel,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

/// "─── or ───" separator between two authentication methods.
class AuthMethodDivider extends StatelessWidget {
  const AuthMethodDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: Divider(color: scheme.outlineVariant)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: TextStyle(color: scheme.outline, fontSize: 12),
          ),
        ),
        Expanded(child: Divider(color: scheme.outlineVariant)),
      ],
    );
  }
}

/// Inline, readable failure banner.
///
/// The message is always the controller/provider-derived sentence (or a copy
/// string chosen by the screen) — never a raw exception or status code.
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Google's four-colour "G" mark, painted — see [GoogleLogo].
class GoogleGPainter extends CustomPainter {
  GoogleGPainter(this.blue, this.red, this.yellow, this.green);

  final Color blue, red, yellow, green;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = w * 0.16;

    final bluePaint = Paint()
      ..color = blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(
        Offset(w * 0.06, h * 0.5), Offset(w * 0.30, h * 0.5), bluePaint);

    final redPaint = Paint()
      ..color = red
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromLTWH(w * 0.06, h * 0.06, w * 0.88, h * 0.88);
    canvas.drawArc(rect, -0.9, 1.2, false, redPaint);

    final yellowPaint = Paint()
      ..color = yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0.9, 1.2, false, yellowPaint);

    final greenPaint = Paint()
      ..color = green
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(w * 0.50, h * 0.50), Offset(w * 0.94, h * 0.50), greenPaint);
  }

  @override
  bool shouldRepaint(covariant GoogleGPainter oldDelegate) => false;
}