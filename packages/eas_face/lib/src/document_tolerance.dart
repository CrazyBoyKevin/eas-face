import 'dart:math' as math;
import 'face_math.dart';

/// A bounded residual warp in the standard 128px aligned image coordinates.
/// Used only for an auxiliary embedding; public thumbnails/points stay standard.
class DocumentCorrection {
  const DocumentCorrection(this.a, this.b, this.c, this.d, this.tx, this.ty);
  final double a, b, c, d, tx, ty;

  FacePoint apply(FacePoint p) =>
      FacePoint(a * p.x + b * p.y + tx, c * p.x + d * p.y + ty);

  FacePoint inverse(FacePoint p) {
    final determinant = a * d - b * c;
    final x = p.x - tx, y = p.y - ty;
    return FacePoint(
      (d * x - b * y) / determinant,
      (-c * x + a * y) / determinant,
    );
  }
}

/// Ridge-regularized affine residual, biased toward preserving face geometry.
/// No reference image or pair score is used to select the correction.
DocumentCorrection? fitDocumentCorrection(List<FacePoint> alignedPoints) {
  if (alignedPoints.length != 5 ||
      alignedPoints.any((p) => !p.x.isFinite || !p.y.isFinite)) {
    return null;
  }
  final sx = alignedPoints.fold(0.0, (v, p) => v + p.x) / 5;
  final sy = alignedPoints.fold(0.0, (v, p) => v + p.y) / 5;
  final tx = canonicalLandmarks.fold(0.0, (v, p) => v + p.x) / 5;
  final ty = canonicalLandmarks.fold(0.0, (v, p) => v + p.y) / 5;
  // 30px identity prior, independent of the pair's similarity score.
  const ridge = 30.0 * 30.0;
  double xx = 0, xy = 0, yy = 0;
  double ux = ridge, uy = 0, vx = 0, vy = ridge;
  for (var i = 0; i < 5; i++) {
    final x = alignedPoints[i].x - sx, y = alignedPoints[i].y - sy;
    final u = canonicalLandmarks[i].x - tx;
    final v = canonicalLandmarks[i].y - ty;
    xx += x * x;
    xy += x * y;
    yy += y * y;
    ux += x * u;
    uy += y * u;
    vx += x * v;
    vy += y * v;
  }
  if (xx * yy - xy * xy <= 1e-6) return null;
  xx += ridge;
  yy += ridge;
  final denominator = xx * yy - xy * xy;
  final a = (yy * ux - xy * uy) / denominator;
  final b = (xx * uy - xy * ux) / denominator;
  final c = (yy * vx - xy * vy) / denominator;
  final d = (xx * vy - xy * vx) / denominator;
  final determinant = a * d - b * c;
  // Bound both singular values; reject reflections and extreme deformation.
  final trace = a * a + b * b + c * c + d * d;
  final disc = math.sqrt(
    math.max(0.0, trace * trace - 4 * determinant * determinant),
  );
  final minScale = math.sqrt(math.max(0.0, (trace - disc) / 2));
  final maxScale = math.sqrt(math.max(0.0, (trace + disc) / 2));
  if (!determinant.isFinite ||
      determinant <= 0 ||
      minScale < 0.8 ||
      maxScale > 1.25) {
    return null;
  }
  final correction = DocumentCorrection(
    a,
    b,
    c,
    d,
    tx - a * sx - b * sy,
    ty - c * sx - d * sy,
  );
  double maxShift = 0;
  for (final p in alignedPoints) {
    final q = correction.apply(p);
    maxShift = math.max(
      maxShift,
      math.sqrt((q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y)),
    );
  }
  // Do not resample identity-like corrections or move points over 8 crop pixels.
  if (maxShift < 0.05 || maxShift > 8) return null;
  return correction;
}

/// Equal-weight unit-feature pooling, never maximum-score selection.
List<double> poolDocumentFeatures(
  List<double> standard,
  List<double> auxiliary,
) {
  if (standard.isEmpty || standard.length != auxiliary.length) {
    throw StateError('Document feature dimensions differ');
  }
  List<double> normalized(List<double> values) {
    final norm = math.sqrt(values.fold(0.0, (s, v) => s + v * v));
    if (!norm.isFinite || norm <= 1e-12 || values.any((v) => !v.isFinite)) {
      throw StateError('Invalid document feature vector');
    }
    return values.map((v) => v / norm).toList();
  }

  final first = normalized(standard), second = normalized(auxiliary);
  final sum = List<double>.generate(first.length, (i) => first[i] + second[i]);
  return normalized(sum);
}
