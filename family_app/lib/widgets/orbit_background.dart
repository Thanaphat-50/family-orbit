import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class OrbitBackground
    extends StatelessWidget {
  final Widget child;

  const OrbitBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // =============================================
        // Gradient Background
        // =============================================

        Positioned.fill(
          child: DecoratedBox(
            decoration:
                BoxDecoration(
              gradient:
                  LinearGradient(
                begin:
                    Alignment.topLeft,
                end:
                    Alignment.bottomRight,
                colors: [
                  AppColors.softPrimary,
                  AppColors.background,
                  AppColors.softWarm,
                ],
              ),
            ),
          ),
        ),

        // =============================================
        // Orbit Art
        // =============================================

        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter:
                  _OrbitPainter(),
            ),
          ),
        ),

        // =============================================
        // Content
        // =============================================

        child,
      ],
    );
  }
}

// =======================================================
// วาด Orbit Background
// =======================================================

class _OrbitPainter
    extends CustomPainter {
  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final orbitPaint = Paint()
      ..color =
          AppColors.primary
              .withValues(
        alpha: 0.08,
      )
      ..style =
          PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final orbitPaint2 = Paint()
      ..color =
          AppColors.sky
              .withValues(
        alpha: 0.10,
      )
      ..style =
          PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final primaryDot = Paint()
      ..color =
          AppColors.primary
              .withValues(
        alpha: 0.18,
      );

    final skyDot = Paint()
      ..color =
          AppColors.sky
              .withValues(
        alpha: 0.22,
      );

    final warmDot = Paint()
      ..color =
          AppColors.warm
              .withValues(
        alpha: 0.20,
      );

    // วงใหญ่ด้านขวาบน
    canvas.drawCircle(
      Offset(
        size.width * 0.88,
        size.height * 0.12,
      ),
      125,
      orbitPaint,
    );

    canvas.drawCircle(
      Offset(
        size.width * 0.88,
        size.height * 0.12,
      ),
      82,
      orbitPaint2,
    );

    // วงด้านซ้ายกลาง
    canvas.drawCircle(
      Offset(
        size.width * 0.04,
        size.height * 0.48,
      ),
      95,
      orbitPaint,
    );

    // จุดสมาชิก
    canvas.drawCircle(
      Offset(
        size.width * 0.72,
        size.height * 0.07,
      ),
      8,
      primaryDot,
    );

    canvas.drawCircle(
      Offset(
        size.width * 0.94,
        size.height * 0.20,
      ),
      12,
      skyDot,
    );

    canvas.drawCircle(
      Offset(
        size.width * 0.15,
        size.height * 0.38,
      ),
      10,
      warmDot,
    );

    canvas.drawCircle(
      Offset(
        size.width * 0.10,
        size.height * 0.72,
      ),
      6,
      primaryDot,
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) {
    return false;
  }
}

// =======================================================
// โลโก้แอป
// =======================================================

class AppLogo
    extends StatelessWidget {
  final double size;

  const AppLogo({
    super.key,
    this.size = 92,
  });

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius =
        BorderRadius.circular(
      size * 0.26,
    );

    return SizedBox(
      width: size + 30,
      height: size + 30,
      child: Center(
        child: Container(
          width: size,
          height: size,
          decoration:
              BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color:
                    const Color(
                  0xFFB04FD8,
                ).withValues(
                  alpha: 0.30,
                ),
                blurRadius: 28,
                offset:
                    const Offset(
                  0,
                  12,
                ),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Image.asset(
              'assets/branding/app_icon.png',
              width: size,
              height: size,
              filterQuality:
                  FilterQuality.medium,
            ),
          ),
        ),
      ),
    );
  }
}
