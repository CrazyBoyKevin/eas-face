import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:eas_face/src/face_math.dart';
import 'package:eas_face/src/document_tolerance.dart';

void main() {
  double error(List<FacePoint> points) => List.generate(5, (i) {
    final dx = points[i].x - canonicalLandmarks[i].x;
    final dy = points[i].y - canonicalLandmarks[i].y;
    return dx * dx + dy * dy;
  }).reduce((a, b) => a + b);

  test(
    'bounded correction improves mild horizontal stretch without forcing template',
    () {
      final center = canonicalLandmarks.fold(0.0, (s, p) => s + p.x) / 5;
      final stretched =
          canonicalLandmarks
              .map((p) => FacePoint(center + (p.x - center) * 1.15, p.y))
              .toList();
      final correction = fitDocumentCorrection(stretched)!;
      final mapped = stretched.map(correction.apply).toList();
      expect(error(mapped), lessThan(error(stretched)));
      expect(error(mapped), greaterThan(0.01));
      for (final p in stretched) {
        final actual = correction.inverse(correction.apply(p));
        expect(actual.x, closeTo(p.x, 1e-9));
        expect(actual.y, closeTo(p.y, 1e-9));
      }
    },
  );
  test(
    'identity, degenerate and extreme landmarks do not trigger deformation',
    () {
      expect(fitDocumentCorrection(canonicalLandmarks), isNull);
      expect(
        fitDocumentCorrection(List.filled(5, const FacePoint(3, 5))),
        isNull,
      );
      expect(fitDocumentCorrection(const [FacePoint(0, 0)]), isNull);
      expect(
        fitDocumentCorrection([
          const FacePoint(double.nan, 0),
          ...canonicalLandmarks.skip(1),
        ]),
        isNull,
      );
      expect(
        fitDocumentCorrection(
          canonicalLandmarks.map((p) => FacePoint(p.x * 4, p.y)).toList(),
        ),
        isNull,
      );
      expect(
        fitDocumentCorrection(
          canonicalLandmarks.map((p) => FacePoint(p.x + 30, p.y)).toList(),
        ),
        isNull,
      );
      expect(
        fitDocumentCorrection(
          canonicalLandmarks.map((p) => FacePoint(128 - p.x, p.y)).toList(),
        ),
        isNull,
      );
    },
  );
  test('residual inverse agrees with an independent two-equation solution', () {
    const correction = DocumentCorrection(1.1, .1, -.05, .9, 3, -2);
    final q = correction.apply(const FacePoint(10, 20));
    expect(q.x, closeTo(16, 1e-12));
    expect(q.y, closeTo(15.5, 1e-12));
    final p = correction.inverse(q);
    expect(p.x, closeTo(10, 1e-12));
    expect(p.y, closeTo(20, 1e-12));
  });
  test(
    'feature pooling has equal unit weights regardless of vector magnitudes',
    () {
      final result = poolDocumentFeatures([100, 0], [0, 2]);
      expect(result[0], closeTo(1 / math.sqrt(2), 1e-12));
      expect(result[1], closeTo(1 / math.sqrt(2), 1e-12));
      expect(poolDocumentFeatures([0, 2], [100, 0]), result);
      expect(poolDocumentFeatures([1, 0], [2, 0]), [1, 0]);
    },
  );
  test(
    'invalid feature outputs propagate instead of silently accepting a score',
    () {
      for (final other in <List<double>>[
        [],
        [0],
        [0, 0],
        [double.nan, 0],
        [-1, 0],
      ]) {
        expect(() => poolDocumentFeatures([1, 0], other), throwsStateError);
      }
    },
  );
}
