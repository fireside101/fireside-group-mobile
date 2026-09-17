import 'package:flutter/material.dart';

const double kCardRadius = 18;
const double kChamfer = 18;
const double kPillRadius = 999;

/// Chamfered top-right corner, matching the web app's signature card shape.
class ChamferedCardClipper extends CustomClipper<Path> {
  final double chamfer;
  const ChamferedCardClipper({this.chamfer = kChamfer});

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width - chamfer, 0)
      ..lineTo(size.width, chamfer)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Paints only the chamfered outline so a crisp stroke survives ClipPath.
class ChamferedCardBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double chamfer;

  const ChamferedCardBorderPainter({
    required this.color,
    this.strokeWidth = 1,
    this.chamfer = kChamfer,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = ChamferedCardClipper(chamfer: chamfer).getClip(size);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant ChamferedCardBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.chamfer != chamfer;
}

/// Widget that applies the chamfered shape with an optional border stroke.
class ChamferedCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  final Color? borderColor;
  final double borderWidth;

  const ChamferedCard({
    super.key,
    required this.child,
    this.color,
    this.borderColor,
    this.borderWidth = 1,
  });

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: ChamferedCardClipper(),
      child: CustomPaint(
        foregroundPainter: borderColor == null
            ? null
            : ChamferedCardBorderPainter(
                color: borderColor!,
                strokeWidth: borderWidth,
              ),
        child: ColoredBox(
          color: color ?? Colors.transparent,
          child: child,
        ),
      ),
    );
  }
}