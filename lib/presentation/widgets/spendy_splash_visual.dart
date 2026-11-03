import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A receipt slips into a wallet; the wordmark follows. All artwork is vector.
class SpendySplashVisual extends StatelessWidget {
  final double progress;
  const SpendySplashVisual({super.key, required this.progress});
  @override
  Widget build(BuildContext context) {
    final reveal = Curves.easeOutCubic.transform(
      ((progress - .55) / .45).clamp(0.0, 1.0),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: SizedBox(
            width: 180,
            height: 180,
            child: CustomPaint(
              painter: SpendyWalletPainter(progress: progress),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Opacity(
          opacity: reveal,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - reveal)),
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'SPENDY',
                semanticsLabel: 'Spendy',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 5,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared vector artwork for the animated splash and exported launcher icons.
class SpendyWalletPainter extends CustomPainter {
  final double progress;
  final bool centered;
  final bool glow;
  const SpendyWalletPainter({
    this.progress = 1,
    this.centered = false,
    this.glow = true,
  });
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 180, size.height / 180);
    if (centered) canvas.translate(-2.5, -27);
    final enter = Curves.easeOutCubic.transform(
      (progress / .35).clamp(0.0, 1.0),
    );
    final tuck = Curves.easeInOutCubic.transform(
      ((progress - .2) / .45).clamp(0.0, 1.0),
    );
    final snap = ((progress - .65) / .25).clamp(0.0, 1.0);
    final pulse = math.sin(snap * math.pi) * .035;
    canvas.translate(90, 110);
    canvas.scale(1 + pulse);
    canvas.translate(-90, -110);
    final glowPaint = Paint()
      ..color = const Color(0xFF9558FF).withValues(alpha: .18 * enter)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
    if (glow) canvas.drawCircle(const Offset(90, 111), 53, glowPaint);
    // Back pocket, visible behind the moving receipt.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(31, 79 + 12 * (1 - enter), 118, 76),
        const Radius.circular(19),
      ),
      Paint()..color = const Color(0xFF6D28D9).withValues(alpha: enter),
    );
    canvas.save();
    canvas.clipRect(const Rect.fromLTWH(0, 0, 180, 150));
    canvas.translate(90, 35 + tuck * 73);
    canvas.rotate(-.10 * (1 - tuck));
    final paper = Path()
      ..moveTo(-27, -24)
      ..lineTo(27, -24)
      ..lineTo(27, 48);
    for (var i = 0; i < 6; i++) {
      paper.lineTo(27 - i * 9.0 - 4.5, 43);
      paper.lineTo(27 - (i + 1) * 9.0, 48);
    }
    paper.lineTo(-27, -24);
    paper.close();
    canvas.drawPath(
      paper,
      Paint()..color = Colors.white.withValues(alpha: enter),
    );
    final ink = Paint()
      ..color = const Color(0xFF7C3AED).withValues(alpha: enter)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(-15, -9), const Offset(9, -9), ink);
    for (var i = 0; i < 3; i++) {
      canvas.drawLine(
        Offset(-15, 4 + i * 11.0),
        Offset(i == 2 ? 4 : 15, 4 + i * 11.0),
        ink..color = const Color(0xFFC4B5FD).withValues(alpha: enter),
      );
    }
    canvas.restore();
    // The front covers the receipt as it slides down into the wallet.
    final front = Rect.fromLTWH(31, 95 + 10 * (1 - enter), 118, 60);
    canvas.drawRRect(
      RRect.fromRectAndRadius(front, const Radius.circular(17)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFB182FF), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(front)
        ..color = Colors.white.withValues(alpha: enter),
    );
    canvas.drawLine(
      const Offset(45, 106),
      const Offset(126, 106),
      Paint()
        ..color = Colors.white.withValues(alpha: .25 * enter)
        ..strokeWidth = 1.5,
    );
    final clasp = Rect.fromLTWH(121 - 4 * snap, 112, 37, 26);
    canvas.drawRRect(
      RRect.fromRectAndRadius(clasp, const Radius.circular(9)),
      Paint()..color = const Color(0xFFEDE4FF).withValues(alpha: enter),
    );
    canvas.drawCircle(
      Offset(136 - 4 * snap, 125),
      3.5,
      Paint()..color = const Color(0xFF6D28D9).withValues(alpha: enter),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(SpendyWalletPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.centered != centered ||
      oldDelegate.glow != glow;
}
