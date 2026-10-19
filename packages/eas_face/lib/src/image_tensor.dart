import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// OpenCV-style half-pixel bilinear resize, edge replication, uint8 rounding.
/// Write BGR/NCHW directly with bottom/right zero padding. In particular, small
/// printed portraits must not shift sampling by half a source scale interval.
Float32List resizedBgrTensor(
  img.Image source,
  int width,
  int height,
  int size,
) {
  if (width <= 0 || height <= 0 || width > size || height > size) {
    throw ArgumentError('Invalid resized tensor dimensions');
  }
  final result = Float32List(3 * size * size);
  final xs = List<double>.generate(
    width,
    (x) =>
        ((x + 0.5) * source.width / width - 0.5)
            .clamp(0, source.width - 1)
            .toDouble(),
  );
  for (var y = 0; y < height; y++) {
    final sy =
        ((y + 0.5) * source.height / height - 0.5)
            .clamp(0, source.height - 1)
            .toDouble();
    final y0 = sy.floor(), y1 = (y0 + 1).clamp(0, source.height - 1);
    final fy = sy - y0;
    for (var x = 0; x < width; x++) {
      final sx = xs[x],
          x0 = sx.floor(),
          x1 = (sx.floor() + 1).clamp(0, source.width - 1);
      final fx = sx - x0;
      final a = source.getPixel(x0, y0), b = source.getPixel(x1, y0);
      final c = source.getPixel(x0, y1), d = source.getPixel(x1, y1);
      double blend(num aa, num bb, num cc, num dd) =>
          ((aa * (1 - fx) + bb * fx) * (1 - fy) +
                  (cc * (1 - fx) + dd * fx) * fy)
              .roundToDouble();
      final index = y * size + x;
      result[index] = blend(a.b, b.b, c.b, d.b);
      result[size * size + index] = blend(a.g, b.g, c.g, d.g);
      result[2 * size * size + index] = blend(a.r, b.r, c.r, d.r);
    }
  }
  return result;
}
