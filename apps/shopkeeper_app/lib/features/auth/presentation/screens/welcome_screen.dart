import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/state/system_state.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/auth_methods.dart';
import '../../domain/auth_models.dart';
import '../controllers/auth_controller.dart';

/// Primary entry screen for the Shopkeeper App.
///
/// The VISIBLE auth methods are driven by [kEnabledAuthMethods]
/// (see `../../domain/auth_methods.dart`) — screens consult
/// [isAuthMethodEnabledProvider] instead of hardcoding method buttons, so a
/// future method (Phone OTP) becomes UI-visible by adding ONE entry to that
/// list, with no widget changes.
///
/// MVP: Google Sign-In + Firebase Authentication is the only enabled method.
/// On tap the native Google picker opens, Firebase exchanges the credential
/// for an ID token, the token is sent to FastAPI, and the backend either loads
/// the existing shopkeeper or creates one on the first sign-in.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  Future<void> _signInWithGoogle(BuildContext context, WidgetRef ref) async {
    debugPrint('[LOGIN] Continue with Google tapped');
    try {
      final ok =
          await ref.read(authControllerProvider.notifier).signInWithGoogle();
      debugPrint('[LOGIN] signInWithGoogle() -> $ok');
      if (!context.mounted) {
        debugPrint('[LOGIN] context unmounted (router navigated away)');
        return;
      }
      if (!ok) {
        final msg = ref.read(authControllerProvider).errorMessage ??
            'Google sign-in failed. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e, st) {
      debugPrint('[LOGIN] unexpected error: $e\n$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Login failed. Please try again.'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isLoading =
        ref.watch(authControllerProvider.select((s) => s.isLoading));
    // Session-expired notice: a mid-session 401 signs the shopkeeper out and
    // lands them HERE silently. Saying why ("your session expired", not "login
    // failed") turns an alarming dead end into an expected, explainable stop.
    final sessionExpired =
        ref.watch(authControllerProvider.select((s) => s.systemState)) ==
            SystemState.sessionExpired;
    final h = MediaQuery.of(context).size.height;

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 32),
                  Text('HyperLocal',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: AppTheme.brandSeed,
                      )),
                  const SizedBox(height: 2),
                  Text('Shopkeeper App',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                  const SizedBox(height: 24),
                  if (sessionExpired) ...[
                    _SessionExpiredNotice(spec: SystemStateSpec.of(
                      SystemState.sessionExpired,
                    )),
                    const SizedBox(height: 20),
                  ],
                  _StorefrontIllustration(height: h * 0.26),
                  const SizedBox(height: 28),
                  Text('Welcome Back',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
                  const SizedBox(height: 10),
                  Text('Manage your shop, products and inventory',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.outline,
                        height: 1.4,
                      )),
                  const SizedBox(height: 36),
                  // Auth-method switch (auth_methods.dart): the Google button
                  // renders only while its method is enabled, so a future
                  // method becomes visible by adding ONE list entry — no
                  // widget changes.
                  if (ref.watch(isAuthMethodEnabledProvider(
                    AuthMethod.googleFirebase,
                  )))
                    _GoogleSignInButton(
                      isLoading: isLoading,
                      onPressed: isLoading
                          ? null
                          : () => _signInWithGoogle(context, ref),
                    ),
                  const SizedBox(height: 22),
                  Text(
                    'By continuing, you agree to our Terms & Privacy Policy.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Why the shopkeeper is back on this screen: their session expired mid-work.
///
/// The copy comes from the shared [SystemStateSpec] — one wording for the
/// "Session expired" state everywhere in the app.
class _SessionExpiredNotice extends StatelessWidget {
  const _SessionExpiredNotice({required this.spec});

  final SystemStateSpec spec;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(spec.icon, size: 22, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spec.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: scheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  spec.message,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onErrorContainer,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Google's official "G" mark drawn with the four brand colours so we don't
/// need an external asset.
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo({this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF4285F4);
    const red = Color(0xFFEA4335);
    const yellow = Color(0xFFFBBC05);
    const green = Color(0xFF34A853);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GoogleGPainter(blue, red, yellow, green),
      ),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  _GoogleGPainter(this.blue, this.red, this.yellow, this.green);

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
    canvas.drawLine(Offset(w * 0.06, h * 0.5), Offset(w * 0.30, h * 0.5), bluePaint);

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
    canvas.drawLine(Offset(w * 0.50, h * 0.50), Offset(w * 0.94, h * 0.50), greenPaint);
  }

  @override
  bool shouldRepaint(covariant _GoogleGPainter oldDelegate) => false;
}

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({required this.isLoading, this.onPressed});

  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F1F1F),
          side: const BorderSide(color: Color(0xFFDADCE0)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 1,
          shadowColor: Colors.black26,
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
                  const _GoogleLogo(size: 20),
                  const SizedBox(width: 12),
                  Text('Continue with Google',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: const Color(0xFF1F1F1F),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          )),
                ],
              ),
      ),
    );
  }
}

class _StorefrontIllustration extends StatelessWidget {
  const _StorefrontIllustration({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _StorefrontPainter(
          roof: AppTheme.brandSeed,
          wall: scheme.primaryContainer,
          door: scheme.primary,
          window: scheme.secondary,
          awning: scheme.tertiary,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _StorefrontPainter extends CustomPainter {
  _StorefrontPainter({
    required this.roof,
    required this.wall,
    required this.door,
    required this.window,
    required this.awning,
  });

  final Color roof, wall, door, window, awning;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    final groundPaint = Paint()..color = wall.withValues(alpha: 0.4);
    canvas.drawRect(Rect.fromLTWH(0, h * 0.85, w, h * 0.15), groundPaint);

    final wallPaint = Paint()..color = wall;
    canvas.drawRect(Rect.fromLTWH(cx - w * 0.28, h * 0.40, w * 0.56, h * 0.45), wallPaint);

    final roofPaint = Paint()..color = roof;
    final roofPath = Path()
      ..moveTo(cx - w * 0.34, h * 0.40)
      ..lineTo(cx, h * 0.22)
      ..lineTo(cx + w * 0.34, h * 0.40)
      ..close();
    canvas.drawPath(roofPath, roofPaint);

    final awningPaint = Paint()..color = awning;
    canvas.drawRect(Rect.fromLTWH(cx - w * 0.16, h * 0.50, w * 0.32, h * 0.05), awningPaint);

    final doorPaint = Paint()..color = door;
    final doorRect = Rect.fromLTWH(cx - w * 0.08, h * 0.62, w * 0.16, h * 0.23);
    canvas.drawRect(doorRect, doorPaint);
    final knobPaint = Paint()..color = Colors.amber.shade700;
    canvas.drawCircle(Offset(cx + w * 0.04, h * 0.74), w * 0.012, knobPaint);

    final windowPaint = Paint()..color = window;
    final winW = w * 0.09;
    final winH = h * 0.10;
    canvas.drawRect(Rect.fromLTWH(cx - w * 0.20, h * 0.55, winW, winH), windowPaint);
    canvas.drawRect(Rect.fromLTWH(cx + w * 0.11, h * 0.55, winW, winH), windowPaint);

    final signPaint = Paint()..color = roof;
    canvas.drawRect(Rect.fromLTWH(cx - w * 0.10, h * 0.43, w * 0.20, h * 0.06), signPaint);
  }

  @override
  bool shouldRepaint(covariant _StorefrontPainter oldDelegate) => false;
}
