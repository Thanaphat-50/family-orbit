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

        const Positioned.fill(
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
                  Color(0xFFF3F5FF),
                  Color(0xFFF8FAFF),
                  Color(0xFFFFFBF6),
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
// Logo ของ Family Orbit
// =======================================================

class FamilyOrbitLogo
    extends StatelessWidget {
  final double size;

  const FamilyOrbitLogo({
    super.key,
    this.size = 92,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 30,
      height: size + 30,
      child: Stack(
        alignment:
            Alignment.center,
        children: [
          // Orbit
          Container(
            width: size + 20,
            height: size * 0.72,
            decoration:
                BoxDecoration(
              borderRadius:
                  BorderRadius.circular(
                999,
              ),
              border:
                  Border.all(
                color:
                    AppColors.primary
                        .withValues(
                  alpha: 0.18,
                ),
                width: 2,
              ),
            ),
          ),

          // Main icon
          Container(
            width: size,
            height: size,
            decoration:
                BoxDecoration(
              gradient:
                  const LinearGradient(
                begin:
                    Alignment.topLeft,
                end:
                    Alignment.bottomRight,
                colors: [
                  AppColors.primary,
                  Color(0xFF7479FF),
                ],
              ),

              borderRadius:
                  BorderRadius.circular(
                size * 0.31,
              ),

              boxShadow: [
                BoxShadow(
                  color:
                      AppColors.primary
                          .withValues(
                    alpha: 0.25,
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

            child: Icon(
              Icons.family_restroom,
              color: Colors.white,
              size: size * 0.52,
            ),
          ),

          // Orbit dot
          Positioned(
            right: 2,
            top: 38,
            child: Container(
              width: 15,
              height: 15,
              decoration:
                  const BoxDecoration(
                color:
                    AppColors.sky,
                shape:
                    BoxShape.circle,
              ),
            ),
          ),

          Positioned(
            left: 6,
            bottom: 27,
            child: Container(
              width: 11,
              height: 11,
              decoration:
                  const BoxDecoration(
                color:
                    AppColors.warm,
                shape:
                    BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}