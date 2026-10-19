import 'dart:math' as math;
import 'dart:typed_data';
import 'package:eas_face/eas_face.dart';
import 'package:image/image.dart' as img;

/// Adapted from Minivision's Apache-2.0 CropImage (see THIRD_PARTY_NOTICES).
/// Retains 2.7x context, shifts the crop at edges, uses inclusive coordinates.
/// BGR, float32, 0..255, NCHW: upstream to_tensor deliberately does NOT /255.
Float32List prepareLivenessInput((img.Image, FaceDetection) input) {
  return _prepare(input, 2.7);
}

Float32List prepareLivenessContextInput((img.Image, FaceDetection) input) {
  return _prepare(input, 4.0);
}

/// Available source context before upstream crop scaling is clamped.
/// This is a framing check, not evidence that the face is live.
double availableLivenessContext(img.Image image, FaceDetection face) =>
    math.min((image.width - 1) / face.width, (image.height - 1) / face.height);

Float32List _prepare((img.Image, FaceDetection) input, double requestedScale) {
  final (image, face) = input;
  final values = [face.x, face.y, face.width, face.height];
  if (image.width < 2 ||
      image.height < 2 ||
      values.any((v) => !v.isFinite) ||
      math.min(face.width, face.height) < 80 ||
      face.x < 0 ||
      face.y < 0 ||
      face.x + face.width > image.width ||
      face.y + face.height > image.height) {
    throw const FormatException('活体检测需要画面内完整、宽高至少 80 像素的人脸');
  }
  final scale = math.min(requestedScale, availableLivenessContext(image, face));
  final width = face.width * scale, height = face.height * scale;
  var left = face.x + (face.width - width) / 2;
  var top = face.y + (face.height - height) / 2;
  var right = left + width, bottom = top + height;
  if (left < 0) {
    right -= left;
    left = 0;
  }
  if (top < 0) {
    bottom -= top;
    top = 0;
  }
  if (right > image.width - 1) {
    left -= right - image.width + 1;
    right = image.width - 1.0;
  }
  if (bottom > image.height - 1) {
    top -= bottom - image.height + 1;
    bottom = image.height - 1.0;
  }
  final x0 = left.toInt(), y0 = top.toInt();
  final cw = right.toInt() - x0 + 1, ch = bottom.toInt() - y0 + 1;
  final tensor = Float32List(3 * 80 * 80);
  // OpenCV INTER_LINEAR half-pixel centers, rounded to uint8. Sampling only
  // 80x80 pixels avoids allocating/resizing the entire camera image.
  for (var y = 0; y < 80; y++) {
    final fy = ((y + .5) * ch / 80 - .5).clamp(0.0, ch - 1.0);
    final iy = fy.floor(), dy = fy - fy.floor();
    for (var x = 0; x < 80; x++) {
      final fx = ((x + .5) * cw / 80 - .5).clamp(0.0, cw - 1.0);
      final ix = fx.floor(), dx = fx - fx.floor();
      final p00 = image.getPixel(x0 + ix, y0 + iy);
      final p10 = image.getPixel(x0 + math.min(ix + 1, cw - 1), y0 + iy);
      final p01 = image.getPixel(x0 + ix, y0 + math.min(iy + 1, ch - 1));
      final p11 = image.getPixel(
        x0 + math.min(ix + 1, cw - 1),
        y0 + math.min(iy + 1, ch - 1),
      );
      for (var c = 0; c < 3; c++) {
        final channel = 2 - c;
        final v =
            p00[channel] * (1 - dx) * (1 - dy) +
            p10[channel] * dx * (1 - dy) +
            p01[channel] * (1 - dx) * dy +
            p11[channel] * dx * dy;
        tensor[c * 6400 + y * 80 + x] = v.roundToDouble();
      }
    }
  }
  return tensor;
}
