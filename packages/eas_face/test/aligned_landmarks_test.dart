import 'dart:typed_data';
import 'dart:convert';
import 'package:eas_face/eas_face.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sample = FaceSample(
    preview: Uint8List(0),
    alignedPreview: Uint8List(0),
    embedding: const [],
    detection: const FaceDetection(
      x: 20,
      y: 25,
      width: 60,
      height: 70,
      score: 0.99,
      landmarks: [
        FacePoint(30, 40),
        FacePoint(70, 42),
        FacePoint(52, 61),
        FacePoint(36, 80),
        FacePoint(66, 79),
      ],
    ),
    width: 200,
    height: 150,
    faceCount: 1,
  );

  test('JSON exports summary and only the source face box and five points', () {
    final result = FaceComparison(
      sample,
      sample,
      0.5,
      const Duration(microseconds: 123456),
    );
    final text = result.toJsonString(threshold: 0.9);
    final data = jsonDecode(text) as Map;
    expect(text, contains('"thresholdPercent": 90.00'));
    expect(text, contains('"elapsedMs": 123.46'));
    expect(text, contains('"x": 20,'));
    expect(text, isNot(contains('"x": 20.00')));
    expect(data, jsonDecode(jsonEncode(result.toJson(threshold: 0.9))));
    expect(data['passed'], false);
    expect(data['thresholdPercent'], 90);
    expect(data['elapsedMs'], 123.46);
    expect(data['likenessPercent'], 66.67);
    expect(result.toJson(threshold: 0.6)['passed'], true);
    expect(
      data.keys,
      unorderedEquals([
        'likenessPercent',
        'thresholdPercent',
        'passed',
        'elapsedMs',
        'first',
        'second',
      ]),
    );
    for (final side in ['first', 'second']) {
      expect(data[side].keys, unorderedEquals(['faceBox', 'landmarks']));
      expect(data[side]['faceBox'], {
        'x': 20,
        'y': 25,
        'width': 60,
        'height': 70,
      });
      expect(data[side]['landmarks'].length, 5);
      expect(data[side]['landmarks'][0], {
        'name': 'imageLeftEye',
        'x': 30,
        'y': 40,
      });
      for (final point in data[side]['landmarks']) {
        expect(point.keys, unorderedEquals(['name', 'x', 'y']));
        expect(point['x'], isA<int>());
        expect(point['y'], isA<int>());
      }
    }
  });

  test('JSON rounding does not change the decision near the threshold', () {
    final result = FaceComparison(sample, sample, 0.399999, Duration.zero);
    final data = result.toJson();
    expect(data['likenessPercent'], 60.00);
    expect(data['passed'], false);
    expect(result.cosine, 0.399999);
    expect(result.toJsonString(), contains('"elapsedMs": 0.00'));
  });

  test('result exposes actual crop points rather than alignment template', () {
    // Independent NumPy SVD Procrustes solution, with Intel RMS scaling.
    const expected = [
      FacePoint(38.82134317819057, 57.44597341443885),
      FacePoint(87.30680233692505, 59.867971983086946),
      FacePoint(65.48947440244822, 82.89953212431804),
      FacePoint(46.096413754114415, 105.93097882967434),
      FacePoint(82.46036632832187, 104.7171436484817),
    ];
    final result = FaceComparison(sample, sample, 1, Duration.zero);
    for (final face in [result.first, result.second]) {
      expect(face.alignedWidth, 128);
      expect(face.alignedHeight, 128);
      final points = face.alignedLandmarks;
      expect(points.length, 5);
      for (var i = 0; i < 5; i++) {
        expect(points[i].x, closeTo(expected[i].x, 1e-8));
        expect(points[i].y, closeTo(expected[i].y, 1e-8));
      }
    }
  });

  test(
    'crop points are read-only and leave original coordinates unchanged',
    () {
      expect(
        () => sample.alignedLandmarks[0] = const FacePoint(0, 0),
        throwsUnsupportedError,
      );
      expect(sample.detection.landmarks.first.x, 30);
      expect(sample.detection.landmarks.first.y, 40);
      expect(sample.width, 200);
      expect(sample.height, 150);
    },
  );
}
