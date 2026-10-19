# Third-party notices

## MiniFASNetV2 + MiniFASNetV1SE / Silent-Face-Anti-Spoofing

- Upstream: https://github.com/minivision-ai/Silent-Face-Anti-Spoofing
- Pinned commit: `b6d5f04ad78778917853b25c778acef6d5626d15`
- Copyright 2020 Minivision; Apache License 2.0, included in `licenses/minifasnet.LICENSE`.
- Original weights: `resources/anti_spoof_models/2.7_80x80_MiniFASNetV2.pth` and `resources/anti_spoof_models/4_0_0_80x80_MiniFASNetV1SE.pth`.
- Modified artifact: exported FP32 ONNX opset 17 / IR 8, fixed [1,3,80,80] input, logits output. No quantization or retraining.
- `lib/src/liveness_preprocessing.dart` adapts the scale-2.7 and scale-4.0, inclusive-coordinate boundary-shifting crop from `src/generate_patches.py`, and uses BGR 0..255 float32 input as in `src/data_io/functional.py`. Resize is implemented in Dart using half-pixel bilinear sampling and rounding to uint8; OpenCV's integer rounding may differ by one intensity unit.
- This package requires agreement of both models using the minimum live score, rather than upstream averaging. Upstream accuracy claims do not transfer to this integration.
- Source and exported file SHA-256 values are in `MODEL_MANIFEST.json` and `MODEL_CONTEXT_MANIFEST.json`.

## Existing dependencies

`eas_face` owns the YuNet and Intel 0095 model notices. `flutter_onnxruntime` and ONNX Runtime are existing MIT dependencies. The extension reuses that runtime; it does not redistribute PyTorch in the application. PyTorch is only a development-time conversion tool.
