import 'dart:typed_data';

/// Experimental achromatic auxiliary view, independent of comparison scores.
/// Input and output are raw 0..255 BGR/CHW; the source is never mutated.
/// This reduces chroma variation, not occlusion, folds or security-pattern loss.
Float32List documentLuminanceTensor(Float32List source) {
  if (source.isEmpty || source.length % 3 != 0) {
    throw ArgumentError('Expected a nonempty three-channel tensor');
  }
  final pixels = source.length ~/ 3;
  final luminance = Float64List(pixels);
  final histogram = List<int>.filled(256, 0);
  var count = 0;
  for (var i = 0; i < pixels; i++) {
    final b = source[i], g = source[pixels + i], r = source[2 * pixels + i];
    if (![b, g, r].every((v) => v.isFinite && v >= 0 && v <= 255)) {
      throw ArgumentError('Expected finite raw pixel values in 0..255');
    }
    final y = 0.114 * b + 0.587 * g + 0.299 * r;
    luminance[i] = y;
    // Exclude alignment padding and clipped white pixels from tone statistics.
    if (y > 0 && y < 255) {
      histogram[y.round()]++;
      count++;
    }
  }
  int percentile(double fraction) {
    final target = (count * fraction).ceil();
    var seen = 0;
    for (var i = 0; i < histogram.length; i++) {
      seen += histogram[i];
      if (seen >= target) return i;
    }
    return 255;
  }

  var gain = 1.0, offset = 0.0;
  if (count >= 32) {
    final low = percentile(.05), high = percentile(.95);
    // Avoid amplifying nearly flat regions/noise. Bound both tone adjustments.
    if (high - low >= 16) {
      gain = (192 / (high - low)).clamp(.8, 1.5).toDouble();
      offset = (128 - gain * (low + high) / 2).clamp(-24, 24).toDouble();
    }
  }
  final result = Float32List(source.length);
  for (var i = 0; i < pixels; i++) {
    final y = luminance[i];
    // Preserve true black and white; no invented detail in clipped regions.
    final value =
        y <= 0 || y >= 255
            ? y.clamp(0, 255).toDouble()
            : (y * gain + offset).clamp(0, 255).roundToDouble();
    result[i] = result[pixels + i] = result[2 * pixels + i] = value;
  }
  return result;
}
