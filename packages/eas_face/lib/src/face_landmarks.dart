import 'package:flutter/material.dart';
import 'face_math.dart';

/// Uses the same centered BoxFit.contain transform as the photo, including
/// letterboxing. Points stay in the oriented preview's pixel coordinates.
class FaceLandmarkOverlay extends StatelessWidget {
  const FaceLandmarkOverlay({
    super.key,
    required this.imageSize,
    required this.points,
    required this.matches,
  });
  final Size imageSize;
  final List<FacePoint> points;
  final bool matches;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = constraints.biggest;
          final fitted = applyBoxFit(BoxFit.contain, imageSize, viewport);
          final rect = Alignment.center.inscribe(
            fitted.destination,
            Offset.zero & viewport,
          );
          return Stack(
            children: [
              for (var i = 0; i < points.length; i++) ...[
                Positioned(
                  left:
                      rect.left +
                      points[i].x / imageSize.width * rect.width -
                      4,
                  top:
                      rect.top +
                      points[i].y / imageSize.height * rect.height -
                      4,
                  child: Container(
                    key: ValueKey('landmark-dot-$i'),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color:
                          matches
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFDC2626),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    ),
  );
}
