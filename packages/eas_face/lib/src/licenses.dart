import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;

void registerSdkLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    for (final entry
        in const {
          'YuNet': 'face_detection_yunet.LICENSE',
          'Intel Open Model Zoo': 'open_model_zoo.LICENSE',
          'ONNX Runtime': 'onnxruntime.LICENSE',
          'flutter_onnxruntime': 'flutter_onnxruntime.LICENSE',
        }.entries) {
      yield LicenseEntryWithLineBreaks(
        [entry.key],
        await rootBundle.loadString(
          'packages/eas_face/licenses/${entry.value}',
        ),
      );
    }
  });
}
