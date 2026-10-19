import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:eas_face/src/image_tensor.dart';

void main() {
  test('downsampling uses pixel centers and keeps BGR plus zero padding', () {
    final source = img.Image(width: 4, height: 2);
    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 4; x++) {
        source.setPixelRgb(x, y, x * 20, y * 80, 100);
      }
    }
    final tensor = resizedBgrTensor(source, 2, 1, 2);
    // Pixel centers sample source x=0.5,2.5 and y=0.5, not x=0,2/y=0.
    expect(tensor.toList(), [100, 100, 0, 0, 40, 40, 0, 0, 10, 50, 0, 0]);
  });
  test('upscaling replicates border pixels', () {
    final source = img.Image(width: 2, height: 1);
    source.setPixelRgb(0, 0, 0, 0, 0);
    source.setPixelRgb(1, 0, 80, 80, 80);
    final tensor = resizedBgrTensor(source, 4, 1, 4);
    expect(tensor.take(4).toList(), [0, 20, 60, 80]);
  });
}
