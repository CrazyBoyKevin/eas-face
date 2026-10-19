# Third-party resources

| Resource | Version/source | Included license |
| --- | --- | --- |
| YuNet | OpenCV Zoo `47534e27c9851bb1128ccc0102f1145e27f23f98`, 2023mar | `licenses/face_detection_yunet.LICENSE` (MIT) |
| Intel face-reidentification-retail-0095 | Open Model Zoo 2023.0 FP32 IR, converted to ONNX opset 17 | `licenses/open_model_zoo.LICENSE` (Apache-2.0) |
| ONNX Runtime | Native runtime supplied by `flutter_onnxruntime@1.9.0` | `licenses/onnxruntime.LICENSE` (MIT) |
| flutter_onnxruntime | pub `1.9.0` | `licenses/flutter_onnxruntime.LICENSE` |

Sources: https://github.com/opencv/opencv_zoo/tree/47534e27c9851bb1128ccc0102f1145e27f23f98/models,
https://github.com/microsoft/onnxruntime,
https://github.com/masicai/flutter_onnxruntime.
Preserve these notices when redistributing the included resources. These are upstream declarations, not an independent assessment of training-data rights. Other Dart dependencies retain their own licenses in their packages.

Intel source manifest: https://github.com/openvinotoolkit/open_model_zoo/blob/2023.0.0/models/intel/face-reidentification-retail-0095/model.yml

Modification notice (2026-10-14): original Intel FP32 XML/BIN converted locally to ONNX using openvino2onnx 1.1.0; weights remain FP32, with no training or quantization. Model SHA-256: `d351ea020acbbd3992b69edc673a0e667623e697745b6c1a23e67085cf90e929`. Conversion sources and checksums are in `tool/prepare_intel_model.py`. The recognizer alignment uses the normalized reference landmarks and RMS scale convention of Intel's Apache-2.0 face recognition demo (Copyright 2018–2024 Intel Corporation), independently implemented in Dart.
