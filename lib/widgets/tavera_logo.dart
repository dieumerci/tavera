import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

// ─── TaveraLogo ───────────────────────────────────────────────────────────────
//
// Brand mark for Tavera — a camera aperture ring with a leaf/sprout growing
// from the centre, representing "capture your health".
//
// Usage:
//   TaveraLogo(size: 80)          // accent coloured (default)
//   TaveraLogo(size: 48, mono: true)  // white version for dark overlays

class TaveraLogo extends StatelessWidget {
  final double size;
  final bool mono;

  const TaveraLogo({super.key, this.size = 72, this.mono = false});

  @override
  Widget build(BuildContext context) {
    final color = mono ? Colors.white : AppColors.accent;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _LogoPainter(color: color),
      ),
    );
  }
}

// ─── Painter ──────────────────────────────────────────────────────────────────

class _LogoPainter extends CustomPainter {
  final Color color;
  const _LogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width * 0.46;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.055;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // ── Outer aperture ring ────────────────────────────────────────────────
    // Six arcs with small gaps between them, like a camera iris.
    final bladeCount = 6;
    final gap        = 0.18; // radians gap between blades
    final arcSpan    = (2 * math.pi / bladeCount) - gap;

    for (int i = 0; i < bladeCount; i++) {
      final startAngle = -math.pi / 2 + i * (2 * math.pi / bladeCount);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        startAngle,
        arcSpan,
        false,
        strokePaint,
      );
    }

    // ── Inner dot (viewfinder centre) ──────────────────────────────────────
    canvas.drawCircle(
      Offset(cx, cy),
      size.width * 0.055,
      fillPaint,
    );

    // ── Leaf / sprout ──────────────────────────────────────────────────────
    // A small upward-growing stem with two leaves sprouting left and right.
    final stemTop    = Offset(cx, cy - r * 0.52);
    final stemBottom = Offset(cx, cy + r * 0.10);

    canvas.drawLine(stemBottom, stemTop, strokePaint..strokeWidth = size.width * 0.048);

    // Left leaf — a filled teardrop bezier
    _drawLeaf(canvas, Offset(cx, cy - r * 0.24), size, fillPaint, isLeft: true);
    // Right leaf — mirror
    _drawLeaf(canvas, Offset(cx, cy - r * 0.24), size, fillPaint, isLeft: false);
  }

  void _drawLeaf(
    Canvas canvas,
    Offset base,
    Size size,
    Paint paint, {
    required bool isLeft,
  }) {
    final sign = isLeft ? -1.0 : 1.0;
    final leafW = size.width * 0.22;
    final leafH = size.width * 0.16;

    final path = Path()
      ..moveTo(base.dx, base.dy)
      ..cubicTo(
        base.dx + sign * leafW * 0.8,
        base.dy - leafH * 0.2,
        base.dx + sign * leafW,
        base.dy - leafH,
        base.dx,
        base.dy - leafH * 1.1,
      )
      ..cubicTo(
        base.dx + sign * leafW * 0.1,
        base.dy - leafH * 0.6,
        base.dx,
        base.dy - leafH * 0.1,
        base.dx,
        base.dy,
      )
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.color != color;
}
