import 'dart:math' as math;

import 'package:flutter/material.dart';

enum LunaState { idle, listening, thinking, speaking }

/// Шар-луна: свечение и анимация показывают, что сейчас делает Луна.
class MoonOrb extends StatefulWidget {
  const MoonOrb({super.key, required this.state, this.size = 96, this.onTap});

  final LunaState state;
  final double size;
  final VoidCallback? onTap;

  @override
  State<MoonOrb> createState() => _MoonOrbState();
}

class _MoonOrbState extends State<MoonOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: widget.onTap != null,
      label: 'Луна: ${_stateLabel(widget.state)}',
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            size: Size.square(widget.size),
            painter: _OrbPainter(_c.value, widget.state),
          ),
        ),
      ),
    );
  }
}

String _stateLabel(LunaState s) => switch (s) {
  LunaState.idle => 'ждёт',
  LunaState.listening => 'слушает',
  LunaState.thinking => 'думает',
  LunaState.speaking => 'говорит',
};

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.t, this.state);

  final double t;
  final LunaState state;

  static const _craters = [(-0.32, -0.08, 0.18), (0.26, 0.32, 0.12), (0.3, -0.36, 0.08)];

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.33;
    final wave = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    final color = switch (state) {
      LunaState.idle => const Color(0xFF8E9BC7),
      LunaState.listening => const Color(0xFF4DD0E1),
      LunaState.thinking => const Color(0xFFB39DDB),
      LunaState.speaking => const Color(0xFFFFCC80),
    };
    final strength = state == LunaState.idle ? 0.25 : 1.0;

    // Свечение
    final glowR = r * (1.3 + 0.18 * wave * strength);
    canvas.drawCircle(
      c,
      glowR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.55 * (0.6 + 0.4 * strength)),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: glowR)),
    );

    // Сама луна
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.4),
          colors: [Color(0xFFF7F5EA), Color(0xFFB9BED3)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    final crater = Paint()..color = const Color(0x24000000);
    for (final (dx, dy, cr) in _craters) {
      canvas.drawCircle(c + Offset(dx * r, dy * r), cr * r, crater);
    }

    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    switch (state) {
      case LunaState.thinking:
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r * 1.18),
          t * 2 * math.pi,
          math.pi * 0.65,
          false,
          ring,
        );
      case LunaState.listening:
        canvas.drawCircle(
          c,
          r * (1.1 + 0.25 * t),
          ring..color = color.withValues(alpha: 1 - t),
        );
      case LunaState.speaking:
      case LunaState.idle:
        break;
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.t != t || old.state != state;
}
