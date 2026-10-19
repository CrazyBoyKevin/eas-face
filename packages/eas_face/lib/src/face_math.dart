import 'dart:math' as math;

class FacePoint {
  const FacePoint(this.x, this.y);
  final double x;
  final double y;
}

class FaceDetection {
  const FaceDetection({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.score,
    required this.landmarks,
  });
  final double x, y, width, height, score;
  final List<FacePoint> landmarks;
}

const alignedFaceSize = 128;

const canonicalLandmarks = <FacePoint>[
  FacePoint(30.2946 / 96 * 128, 51.6963 / 112 * 128),
  FacePoint(65.5318 / 96 * 128, 51.5014 / 112 * 128),
  FacePoint(48.0252 / 96 * 128, 71.7366 / 112 * 128),
  FacePoint(33.5493 / 96 * 128, 92.3655 / 112 * 128),
  FacePoint(62.7299 / 96 * 128, 92.2041 / 112 * 128),
];

/// Intel 0095 uses the ratio of centered RMS spreads for alignment scale.
/// Match its demo's Procrustes convention, preserving rotation without shear.
SimilarityTransform fitRecognitionAlignment(List<FacePoint> source) {
  final rotation = fitSimilarity(source);
  double sx = 0, sy = 0, dx = 0, dy = 0;
  for (var i = 0; i < source.length; i++) {
    sx += source[i].x;
    sy += source[i].y;
    dx += canonicalLandmarks[i].x;
    dy += canonicalLandmarks[i].y;
  }
  sx /= source.length;
  sy /= source.length;
  dx /= source.length;
  dy /= source.length;
  double sourceSpread = 0, targetSpread = 0;
  for (var i = 0; i < source.length; i++) {
    sourceSpread +=
        math.pow(source[i].x - sx, 2) + math.pow(source[i].y - sy, 2);
    targetSpread +=
        math.pow(canonicalLandmarks[i].x - dx, 2) +
        math.pow(canonicalLandmarks[i].y - dy, 2);
  }
  final factor =
      math.sqrt(targetSpread / sourceSpread) /
      math.sqrt(rotation.a * rotation.a + rotation.b * rotation.b);
  final a = rotation.a * factor, b = rotation.b * factor;
  return SimilarityTransform(a, b, dx - a * sx + b * sy, dy - b * sx - a * sy);
}

/// Map a resized detection (including a cropped region) to source pixels.
FaceDetection mapFaceDetection(
  FaceDetection face, {
  required double scaleX,
  required double scaleY,
  double offsetX = 0,
  double offsetY = 0,
}) => FaceDetection(
  x: face.x * scaleX + offsetX,
  y: face.y * scaleY + offsetY,
  width: face.width * scaleX,
  height: face.height * scaleY,
  score: face.score,
  landmarks:
      face.landmarks
          .map((p) => FacePoint(p.x * scaleX + offsetX, p.y * scaleY + offsetY))
          .toList(),
);

/// Least-squares similarity transform: x' = a*x-b*y+tx, y' = b*x+a*y+ty.
/// Rotation + uniform scale + translation, without reflection or shear.
class SimilarityTransform {
  const SimilarityTransform(this.a, this.b, this.tx, this.ty);
  final double a, b, tx, ty;
  FacePoint apply(FacePoint p) =>
      FacePoint(a * p.x - b * p.y + tx, b * p.x + a * p.y + ty);
  FacePoint inverse(FacePoint p) {
    final d = a * a + b * b;
    if (d < 1e-12) throw const FormatException('人脸关键点无法对齐');
    final x = p.x - tx, y = p.y - ty;
    return FacePoint((a * x + b * y) / d, (-b * x + a * y) / d);
  }
}

SimilarityTransform fitSimilarity(
  List<FacePoint> source, [
  List<FacePoint> target = canonicalLandmarks,
]) {
  if (source.length != target.length || source.length < 2) {
    throw ArgumentError('At least two corresponding landmarks are required');
  }
  double sx = 0, sy = 0, dx = 0, dy = 0;
  for (var i = 0; i < source.length; i++) {
    sx += source[i].x;
    sy += source[i].y;
    dx += target[i].x;
    dy += target[i].y;
  }
  sx /= source.length;
  sy /= source.length;
  dx /= source.length;
  dy /= source.length;
  double denominator = 0, real = 0, imaginary = 0;
  for (var i = 0; i < source.length; i++) {
    final x = source[i].x - sx, y = source[i].y - sy;
    final u = target[i].x - dx, v = target[i].y - dy;
    denominator += x * x + y * y;
    real += x * u + y * v;
    imaginary += x * v - y * u;
  }
  if (!denominator.isFinite || denominator < 1e-8) {
    throw const FormatException('人脸关键点不完整，请换一张正面照片');
  }
  final a = real / denominator, b = imaginary / denominator;
  if (!a.isFinite || !b.isFinite || a * a + b * b < 1e-12) {
    throw const FormatException('人脸关键点无法对齐');
  }
  return SimilarityTransform(a, b, dx - a * sx + b * sy, dy - b * sx - a * sy);
}

double cosineSimilarity(List<double> a, List<double> b) {
  if (a.isEmpty || a.length != b.length) {
    throw ArgumentError('Invalid embeddings');
  }
  double dot = 0, aa = 0, bb = 0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    aa += a[i] * a[i];
    bb += b[i] * b[i];
  }
  if (!dot.isFinite ||
      !aa.isFinite ||
      !bb.isFinite ||
      aa < 1e-12 ||
      bb < 1e-12) {
    throw const FormatException('人脸特征无效，请更换照片');
  }
  return (dot / math.sqrt(aa * bb)).clamp(-1.0, 1.0);
}

double intersectionOverUnion(FaceDetection a, FaceDetection b) {
  final w = math.max(
    0.0,
    math.min(a.x + a.width, b.x + b.width) - math.max(a.x, b.x),
  );
  final h = math.max(
    0.0,
    math.min(a.y + a.height, b.y + b.height) - math.max(a.y, b.y),
  );
  final intersection = w * h;
  final union = a.width * a.height + b.width * b.height - intersection;
  return union > 0 ? intersection / union : 0;
}

List<FaceDetection> nonMaxSuppression(
  List<FaceDetection> faces, {
  double iouThreshold = 0.3,
}) {
  final sorted = List<FaceDetection>.of(faces)
    ..sort((a, b) => b.score.compareTo(a.score));
  final kept = <FaceDetection>[];
  for (final face in sorted.take(5000)) {
    if (kept.every(
      (other) => intersectionOverUnion(face, other) <= iouThreshold,
    )) {
      kept.add(face);
    }
  }
  return kept;
}

/// YuNet 2023 fixed-size NCHW input, decoded in resized-image coordinates.
List<FaceDetection> decodeYuNet(
  Map<String, List<double>> outputs, {
  int size = 640,
  double scoreThreshold = 0.8,
}) {
  final faces = <FaceDetection>[];
  for (final stride in [8, 16, 32]) {
    final cols = size ~/ stride;
    final cls = outputs['cls_$stride']!, obj = outputs['obj_$stride']!;
    final box = outputs['bbox_$stride']!, kps = outputs['kps_$stride']!;
    if (cls.length != cols * cols ||
        obj.length != cls.length ||
        box.length != cls.length * 4 ||
        kps.length != cls.length * 10) {
      throw StateError('Unexpected YuNet output shape');
    }
    for (var i = 0; i < cls.length; i++) {
      final score = math.sqrt(cls[i].clamp(0.0, 1.0) * obj[i].clamp(0.0, 1.0));
      if (!score.isFinite || score < scoreThreshold) continue;
      final row = i ~/ cols, col = i % cols;
      final cx = (col + box[i * 4]) * stride,
          cy = (row + box[i * 4 + 1]) * stride;
      final w = math.exp(box[i * 4 + 2]) * stride,
          h = math.exp(box[i * 4 + 3]) * stride;
      final landmarks = List.generate(
        5,
        (n) => FacePoint(
          (col + kps[i * 10 + n * 2]) * stride,
          (row + kps[i * 10 + n * 2 + 1]) * stride,
        ),
      );
      if (![
            cx,
            cy,
            w,
            h,
            ...landmarks.expand((p) => [p.x, p.y]),
          ].every((v) => v.isFinite) ||
          w <= 0 ||
          h <= 0) {
        continue;
      }
      faces.add(
        FaceDetection(
          x: cx - w / 2,
          y: cy - h / 2,
          width: w,
          height: h,
          score: score,
          landmarks: landmarks,
        ),
      );
    }
  }
  return nonMaxSuppression(faces);
}
