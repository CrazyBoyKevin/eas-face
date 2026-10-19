import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:eas_face/src/document_photometric.dart';

Float32List bgr(List<List<double>> pixels) => Float32List.fromList([
  for (var channel = 0; channel < 3; channel++)
    for (final pixel in pixels) pixel[channel],
]);

void main() {
  test(
    'BGR channel weights produce neutral output without mutating source',
    () {
      final source = bgr([
        [255, 0, 0],
        [0, 255, 0],
        [0, 0, 255],
      ]);
      final before = source.toList();
      final result = documentLuminanceTensor(source);
      expect(result.toList(), [29, 150, 76, 29, 150, 76, 29, 150, 76]);
      expect(source.toList(), before);
      expect(identical(source, result), isFalse);
    },
  );

  test('black alignment padding and clipped white remain unchanged', () {
    final source = bgr([
      for (var i = 0; i < 40; i++) [0, 0, 0],
      for (var i = 0; i < 40; i++) [255, 255, 255],
    ]);
    expect(documentLuminanceTensor(source).toList(), source.toList());
  });

  test('flat pixels are desaturated without amplifying noise', () {
    final source = bgr(List.generate(64, (i) => [50, 100, 150]));
    expect(documentLuminanceTensor(source).every((v) => v == 109), isTrue);
  });

  test('dark ramp has bounded gain and offset and preserves ordering', () {
    final pixels = List.generate(100, (i) {
      final level = 20.0 + i;
      return [level, level, level];
    });
    final output = documentLuminanceTensor(bgr(pixels));
    // 5th/95th percentiles = 24/114; gain capped at 1.5, offset at 24.
    expect(output[0], 54);
    expect(output[99], 203);
    for (var i = 1; i < 100; i++) {
      expect(output[i], greaterThanOrEqualTo(output[i - 1]));
      expect(output[i] - output[i - 1], lessThanOrEqualTo(2));
    }
    expect(output.every((v) => v >= 0 && v <= 255 && v.isFinite), isTrue);
  });

  test('padding does not bias luminance statistics', () {
    final ramp = List.generate(100, (i) => List.filled(3, 20.0 + i));
    final plain = documentLuminanceTensor(bgr(ramp));
    final padded = documentLuminanceTensor(
      bgr([
        ...List.generate(500, (_) => [0, 0, 0]),
        ...ramp,
      ]),
    );
    expect(padded.sublist(500, 600), plain.sublist(0, 100));
  });

  test('output clips safely for saturated colored pixels', () {
    final source = bgr([
      ...List.generate(100, (i) => List.filled(3, 50.0 + i)),
      [0, 255, 255],
    ]);
    final output = documentLuminanceTensor(source);
    expect(output[100], 255);
    expect(output[201], 255);
    expect(output[302], 255);
  });

  test('malformed and invalid tensors fail explicitly', () {
    for (final values in [
      <double>[],
      [1.0, 2.0],
      [double.nan, 0.0, 0.0],
      [double.infinity, 0.0, 0.0],
      [-1.0, 0.0, 0.0],
      [256.0, 0.0, 0.0],
    ]) {
      expect(
        () => documentLuminanceTensor(Float32List.fromList(values)),
        throwsArgumentError,
      );
    }
  });
}
