import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:eas_face/src/face_engine.dart';
import 'package:eas_face/src/face_math.dart';

void main() {
  test(
    'display threshold uses mapped score with an exact reference boundary',
    () {
      final sample = FaceSample(
        preview: Uint8List(0),
        alignedPreview: Uint8List(0),
        embedding: const [1],
        detection: const FaceDetection(
          x: 0,
          y: 0,
          width: 100,
          height: 100,
          score: 1,
          landmarks: canonicalLandmarks,
        ),
        width: 100,
        height: 100,
        faceCount: 1,
      );
      expect(defaultThreshold, 0.60);
      for (final score in [-1.0, 0.277, 0.399999, 0.4, 0.400001, 0.60, 1.0]) {
        final result = FaceComparison(sample, sample, score, Duration.zero);
        expect(
          result.matches(defaultThreshold),
          score >= recognitionReferenceCosine,
        );
        expect(result.matches(0.80), result.likeness >= 0.80);
      }
    },
  );

  test('display scale is bounded, monotonic, and not a direct percentage', () {
    expect(likenessScore(-1), 0);
    expect(likenessScore(0), 0);
    expect(likenessScore(recognitionReferenceCosine), 0.60);
    expect(likenessScore(1), 1);
    expect(formatLikeness(likenessScore(0.277)), '41.55%');
    var previous = 0.0;
    for (var i = -1000; i <= 1000; i++) {
      final current = likenessScore(i / 1000);
      expect(current, inInclusiveRange(previous, 1.0));
      previous = current;
    }
    expect(() => likenessScore(double.nan), throwsArgumentError);
    expect(() => likenessScore(double.infinity), throwsArgumentError);
  });
}
