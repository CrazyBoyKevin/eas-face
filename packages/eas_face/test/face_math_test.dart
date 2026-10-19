import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:eas_face/src/face_math.dart';

FaceDetection box(double x, double y, double w, double h, double score) =>
    FaceDetection(
      x: x,
      y: y,
      width: w,
      height: h,
      score: score,
      landmarks: const [],
    );

void main() {
  test(
    'crop landmarks map back to source pixels with rounded resize scales',
    () {
      final mapped = mapFaceDetection(
        const FaceDetection(
          x: 10,
          y: 20,
          width: 30,
          height: 40,
          score: 0.9,
          landmarks: [
            FacePoint(15, 25),
            FacePoint(30, 25),
            FacePoint(22, 35),
            FacePoint(16, 45),
            FacePoint(29, 45),
          ],
        ),
        scaleX: 2,
        scaleY: 3,
        offsetX: 100,
        offsetY: 200,
      );
      expect(
        [mapped.x, mapped.y, mapped.width, mapped.height],
        [120, 260, 60, 120],
      );
      expect([mapped.landmarks.first.x, mapped.landmarks.first.y], [130, 275]);
      expect([mapped.landmarks.last.x, mapped.landmarks.last.y], [158, 335]);
      expect(mapped.score, 0.9);
    },
  );
  test('cosine is scale independent, symmetric and covers negative values', () {
    expect(cosineSimilarity([1, 2, 3], [2, 4, 6]), closeTo(1, 1e-12));
    expect(cosineSimilarity([1, 0], [0, 1]), 0);
    expect(cosineSimilarity([1, 0], [-1, 0]), -1);
    expect(
      cosineSimilarity([1, 2], [3, 4]),
      closeTo(cosineSimilarity([3, 4], [1, 2]), 1e-12),
    );
  });
  test(
    'cosine rejects invalid vectors instead of returning a misleading score',
    () {
      expect(() => cosineSimilarity([], []), throwsArgumentError);
      expect(() => cosineSimilarity([1], [1, 2]), throwsArgumentError);
      expect(() => cosineSimilarity([0, 0], [1, 2]), throwsFormatException);
      expect(
        () => cosineSimilarity([double.nan, 1], [1, 2]),
        throwsFormatException,
      );
    },
  );
  test('alignment recovers a known rotation, scale and translation', () {
    final known = SimilarityTransform(
      1.8 * math.cos(0.3),
      1.8 * math.sin(0.3),
      120,
      -40,
    );
    final source = canonicalLandmarks.map(known.apply).toList();
    final alignment = fitSimilarity(source);
    for (var i = 0; i < 5; i++) {
      final result = alignment.apply(source[i]);
      expect(result.x, closeTo(canonicalLandmarks[i].x, 1e-8));
      expect(result.y, closeTo(canonicalLandmarks[i].y, 1e-8));
      final inverse = alignment.inverse(result);
      expect(inverse.x, closeTo(source[i].x, 1e-8));
      expect(inverse.y, closeTo(source[i].y, 1e-8));
    }
  });
  test('alignment rejects coincident landmarks', () {
    expect(
      () => fitSimilarity(List.filled(5, const FacePoint(10, 10))),
      throwsFormatException,
    );
  });
  test('NMS suppresses duplicate detections but preserves another face', () {
    final faces = nonMaxSuppression([
      box(0, 0, 100, 100, 0.8),
      box(2, 2, 100, 100, 0.95),
      box(200, 0, 100, 100, 0.9),
    ]);
    expect(faces.length, 2);
    expect(faces.first.score, 0.95);
    expect(intersectionOverUnion(faces[0], faces[1]), 0);
  });
  test('YuNet decoder respects stride, score, bbox and five landmarks', () {
    final outputs = <String, List<double>>{};
    for (final stride in [8, 16, 32]) {
      final n = (640 ~/ stride) * (640 ~/ stride);
      outputs['cls_$stride'] = List.filled(n, 0);
      outputs['obj_$stride'] = List.filled(n, 0);
      outputs['bbox_$stride'] = List.filled(n * 4, 0);
      outputs['kps_$stride'] = List.filled(n * 10, 0);
    }
    const index = 2 * 80 + 3;
    outputs['cls_8']![index] = 1;
    outputs['obj_8']![index] = 0.81;
    outputs['bbox_8']![index * 4] = 0.5;
    outputs['bbox_8']![index * 4 + 1] = 0.5;
    outputs['bbox_8']![index * 4 + 2] = math.log(10);
    outputs['bbox_8']![index * 4 + 3] = math.log(12);
    final face = decodeYuNet(outputs).single;
    expect(face.score, closeTo(0.9, 1e-9));
    expect(face.x, closeTo(28 - 40, 1e-9));
    expect(face.y, closeTo(20 - 48, 1e-9));
    expect(face.landmarks.length, 5);
    expect(face.landmarks[0].x, 24);
    expect(face.landmarks[0].y, 16);
    expect(decodeYuNet(outputs, scoreThreshold: 0.95), isEmpty);
  });
}
