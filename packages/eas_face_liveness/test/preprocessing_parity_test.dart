import 'dart:convert';
import 'dart:io';
import 'package:eas_face/eas_face.dart';
import 'package:eas_face_liveness/src/liveness_preprocessing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test(
    'both crop scales: 115,200 tensor values agree with upstream OpenCV within 1/255',
    () {
      final image = img.Image(width: 640, height: 480);
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          image.setPixelRgb(
            x,
            y,
            (x * 3 + y) % 256,
            (x + y * 2) % 256,
            (x * 2 + y * 3) % 256,
          );
        }
      }
      final cases =
          jsonDecode(
                File('test/fixtures/preprocessing.json').readAsStringSync(),
              )
              as List;
      for (final c in cases) {
        final b = (c['box'] as List).cast<num>();
        final face = FaceDetection(
          x: b[0].toDouble(),
          y: b[1].toDouble(),
          width: b[2].toDouble(),
          height: b[3].toDouble(),
          score: 1,
          landmarks: [],
        );
        final tensor =
            c['scale'] == 4.0
                ? prepareLivenessContextInput((image, face))
                : prepareLivenessInput((image, face));
        final expected = (c['bgrChw'] as List).cast<num>();
        double error = 0;
        for (var i = 0; i < tensor.length; i++) {
          final diff = (tensor[i] - expected[i]).abs();
          expect(diff, lessThanOrEqualTo(1), reason: 'box=$b index=$i');
          error += diff;
        }
      // OpenCV's integer path and Dart round half-values differently.
      // Both scales retain the per-element <=1 contract above; new crops
      // exercise more half-value ties, bounded by half an intensity on average.
      expect(error / tensor.length, lessThan(.5));
      }
    },
  );
}
