# eas_face_liveness

English | [简体中文](README.zh-CN.md)

**On-device passive face anti-spoofing for Flutter Android and iOS.**

An extension to `eas_face` that adds frame-level anti-spoofing, temporal
confirmation, and joint identity/liveness verification. It uses MiniFASNetV2 and
MiniFASNetV1SE locally, without uploading images or calling a cloud service.

**Version 0.1.1 is an unpublished development build.** It currently depends on a
sibling checkout of `eas_face 0.2.0` through a path dependency. The base SDK is
available on pub.dev; this extension is not.

## Contents

- [Known limitations](#known-limitations)
- [Requirements and package structure](#requirements-and-package-structure)
- [Installation](#installation)
- [Joint verification](#joint-verification)
- [Constructor parameters and methods](#constructor-parameters-and-methods)
- [Result fields](#result-fields)
- [Statuses](#statuses)
- [JSON output](#json-output)
- [Temporal confirmation](#temporal-confirmation)
- [Frame-level inference](#frame-level-inference)
- [Camera integration and performance](#camera-integration-and-performance)
- [Models, validation, and licenses](#models-validation-and-licenses)

## Known limitations

During device testing on October 16, 2026, the previous single-model version was
reported to accept a magnified static portrait displayed on another screen. That
version cannot be treated as a reliable liveness gate.

Version 0.1.1 adds a second model with a wider crop. The two models use 2.7x and 4x
face context respectively. `liveScore` is the **lower** of their two scores, so a
high score from one model cannot average away a rejection by the other. The
initial threshold remains 0.90; `modelScores` exposes both outputs for evaluation.

The joint verifier returns `insufficientContext` if the source image cannot
provide at least 2.7x face context. This is an input-quality constraint, **not
screen detection**. The 4x crop is still limited by the image boundaries using
the upstream crop policy. Low-level `evaluateFrame` preserves that boundary
behavior; its caller must check `availableLivenessContext` separately.

This is a candidate improvement, not a demonstrated fix for the reported replay
attack. Re-evaluate live users, printed portraits, and screen replays at different
sizes, brightness levels, and distances. More consecutive frames or a higher
threshold alone do not establish replay resistance.

## Requirements and package structure

| Requirement | Value |
| --- | --- |
| Flutter | 3.29.0 or later |
| Dart | >=3.7.0 and <4.0.0 |
| Android | API 24 or later |
| iOS | 16.0 or later |
| Frame input | Upright, unmirrored `package:image` `Image` from the current camera |
| Face input | Complete face, at least 80 pixels wide and high |

| Package | Responsibility | Models |
| --- | --- | --- |
| `eas_face` | Face detection, five landmarks, and identity comparison | YuNet + Intel 0095 |
| `eas_face_liveness` | Anti-spoofing, temporal confirmation, and joint verification | MiniFASNetV2 + MiniFASNetV1SE |

Both packages use `flutter_onnxruntime 1.9.0`; no second inference runtime is added.
Applications using only `eas_face` do not include the liveness models.

The two additional ONNX files total **3,486,238 bytes (3.49 MB / 3.32 MiB)**.
This is raw model size, not the final APK/IPA installation-size increase.

## Installation

Keep the source packages side by side:

```text
packages/
  eas_face/
  eas_face_liveness/
```

In the application:

```yaml
dependencies:
  eas_face_liveness:
    path: packages/eas_face_liveness
  image: ^4.5.4
```

```sh
flutter pub get
```

Camera capture, permissions, orientation, and pixel-format conversion are handled
by the host application. Do not pass encoded image bytes where a decoded camera
`Image` is expected.

## Joint verification

Keep one verifier for the capture session. The following controller illustrates
the lifecycle; call `process` serially for fresh frames from your camera pipeline.

```dart
import 'dart:typed_data';
import 'package:eas_face_liveness/eas_face_liveness.dart';
import 'package:image/image.dart' as img;

class CameraVerifier {
  final _verifier = LiveFaceVerifier();

  Future<void> initialize() => _verifier.initialize();

  Future<LiveFaceVerification> process(
    Uint8List referencePhoto,
    img.Image cameraFrame,
  ) => _verifier.verifyFrame(referencePhoto, cameraFrame);

  void reset() => _verifier.reset();

  // Call only after pending processing has finished.
  Future<void> close() => _verifier.close();
}
```

Read `result.passed` for the joint result and `result.toJson()` for structured
output. A single high anti-spoof score does not immediately pass verification.

- The passport/reference photo participates only in identity comparison, not
  liveness detection.
- Supply fresh original camera pixels, not an aligned thumbnail, screenshot,
  document photograph, or color-corrected recognition image.
- The joint verifier requires one face in the reference and one in the camera
  frame. Multiple detected faces reset confirmation.
- The base SDK's optional all-face comparison behavior is unchanged.
- Reset on pause, camera or reference changes, and navigation away. Clear the UI's
  old success state: a result is a snapshot, not a continuously valid credential.
- The verifier takes ownership of supplied engines. Do not concurrently use or
  separately close those engines.

## Constructor parameters and methods

### `LiveFaceVerifier`

| Parameter | Default | Meaning |
| --- | --- | --- |
| `faceEngine` | New `FaceEngine()` | Identity engine; may be supplied by the host. |
| `livenessEngine` | New `FaceLivenessEngine()` | Anti-spoofing engine. |
| `session` | New `PassiveLivenessSession()` | Temporal confirmation policy. |
| `matchThreshold` | `0.60` | Identity display-score threshold; separate from the liveness threshold. |

| Method | Returns | Purpose |
| --- | --- | --- |
| `initialize()` | `Future<void>` | Preload four models: detector, recognizer, and two anti-spoof models. |
| `verifyFrame(reference, frame)` | `Future<LiveFaceVerification>` | Process one frame and update temporal confirmation. |
| `reset()` | `void` | Clear accumulated evidence and invalidate in-flight results. |
| `close()` | `Future<void>` | Release both engines; the verifier cannot be reused after closing. |

## Result fields

### `LiveFaceVerification`

| Property | Type | Meaning |
| --- | --- | --- |
| `passed` | `bool` | Identity match and temporal liveness requirements both pass. |
| `status` | `LiveVerificationStatus` | Current state, listed below. |
| `search` | `FaceSearchResult` | Base SDK candidates and comparison results. |
| `liveness` | `LivenessFrameResult?` | Frame-level scores and timing; null when inference was skipped. |
| `decision` | `LivenessDecision?` | Temporal state, accepted frame count, and observation duration. |
| `elapsed` | `Duration` | Complete processing time for this frame, excluding host capture/conversion. |

### `LivenessFrameResult`

| Property | Type | Meaning |
| --- | --- | --- |
| `liveScore` | `double` | Minimum of the two model scores, in the range 0-1. |
| `modelScores` | `Map<String, double>` | Individual `texture2_7` and `context4` model scores. |
| `face` | `FaceDetection` | Face box in the original camera image. |
| `preprocessTime` | `Duration` | Crop, resize, and tensor preparation time. |
| `inferenceTime` | `Duration` | Tensor creation, native inference, output reading, and score calculation. |
| `elapsed` | `Duration` | Frame-level anti-spoof processing; may include first-time model loading. |

### `LivenessDecision`

| Property | Type | Meaning |
| --- | --- | --- |
| `status` | `LivenessStatus` | `collecting`, `live`, or `rejected`. |
| `acceptedFrames` | `int` | Frames accepted in the current confirmation sequence. |
| `observationTime` | `Duration` | Time spanned by the current sequence. |
| `passed` | `bool` | Temporal liveness passed; identity still needs a separate check when using this low-level type. |

## Statuses

| `LiveVerificationStatus` | Meaning | Joint `passed` |
| --- | --- | --- |
| `noFace` | No camera face detected. | `false` |
| `multipleFaces` | More than one face in the reference or camera image. | `false` |
| `unusableFace` | A face was detected but no usable recognition sample could be extracted. | `false` |
| `insufficientContext` | Image cannot provide at least 2.7x context around the face. | `false` |
| `identityMismatch` | Identity comparison did not pass. | `false` |
| `collecting` | Gathering evidence, or reset occurred during processing. | `false` |
| `spoofSuspected` | Current frame's anti-spoof score is below threshold. | `false` |
| `live` | Joint identity and temporal liveness verification passed. | `true` |

Invalid input or runtime failures throw exceptions and clear confirmation.
The caller must clear any old success state; errors must never be treated as a
successful verification.

## JSON output

Pass `result.toJson()` to `jsonEncode`. Scores and timings are rounded to two
decimal places; coordinates are integers. JSON numbers do not retain trailing
zeroes as a formatting requirement.

| JSON field | Type | Meaning |
| --- | --- | --- |
| `passed` | boolean | Joint result; use this for the final decision. |
| `status` | string | Status name from the table above. |
| `elapsedMs` | number | Complete SDK processing time for this frame. |
| `observationMs` | number | Current temporal confirmation span. |
| `acceptedFrames` | integer | Number of accepted frames in the sequence. |
| `comparison` | object/null | Base SDK identity JSON, including scores, threshold, boxes, and five landmarks. |
| `liveness` | object/null | Frame-level anti-spoof data. |
| `liveness.liveScore` | number | Minimum model score; not a calibrated probability of a live person. |
| `liveness.modelScores` | object | `texture2_7` and `context4` scores. |
| `liveness.preprocessMs` | number | Preprocessing time. |
| `liveness.inferenceMs` | number | Inference and output-processing time. |
| `liveness.elapsedMs` | number | Total frame-level anti-spoof time. |
| `liveness.faceBox` | object | Integer `x`, `y`, `width`, and `height` in original camera pixels. |

Coordinates use the top-left origin. `comparison.passed` represents identity
matching only; it is not the joint decision.

## Temporal confirmation

```dart
final verifier = LiveFaceVerifier(
  session: PassiveLivenessSession(
    threshold: 0.90,
    minimumFrames: 3,
    minimumObservation: const Duration(milliseconds: 600),
    minimumInterval: const Duration(milliseconds: 100),
    maximumGap: const Duration(milliseconds: 700),
  ),
);
```

| Parameter | Meaning |
| --- | --- |
| `threshold` | Minimum score per accepted frame. Default 0.90 is an initial engineering setting, not business-calibrated. |
| `minimumFrames` | Minimum accepted frame count; at least 2. |
| `minimumObservation` | Minimum observation span; must be positive. |
| `minimumInterval` | Minimum spacing between counted frames. |
| `maximumGap` | Longer gaps restart confirmation; must exceed the minimum interval. |

By default, at least three frames and a span of 600 ms are required. Low scores,
large tracking jumps, reversed timestamps, missing faces, and interruptions clear
confirmation. Box overlap is only a continuity check; the joint verifier also
requires each accepted frame to match the same reference.

When using `PassiveLivenessSession` directly, call `update(frameResult,
monotonicCaptureTime)` and `reset()` as needed. The caller owns identity binding,
frame provenance, tracking, and interruption handling.

## Frame-level inference

If an application already owns detection and tracking, it can reuse the original
camera frame and the corresponding source-image face box:

```dart
final engine = FaceLivenessEngine();
await engine.initialize();
final result = await engine.evaluateFrame(originalCameraFrame, faceDetection);
print(result.modelScores);
await engine.close();
```

The box must be fully inside that image and at least 80 pixels wide and high.
Use `availableLivenessContext` to check available surrounding context before
inference. This low-level method does not enforce the joint verifier's context
gate or provide an overall verification decision.

Maintain a separate temporal session for each tracked person in a custom
multi-person pipeline. Never combine one person's identity match with another
person's liveness score.

## Camera integration and performance

The SDK includes no camera UI or server integration. Supply fresh frames at a
controlled rate, for example 5-10 processed frames per second, and drop incoming
frames while processing is busy instead of building a queue.

Preload models, then measure cold start, per-frame processing, full confirmation
latency, P50/P95, and sustained performance on actual devices. Desktop synthetic
benchmarks in the model manifests are **not phone latency or accuracy results**.

The full local development workspace also contains a separate server-backed
camera demo. It can send embeddings for server identity lookup after local
anti-spoofing; that networking belongs to the host app, not this SDK. Its app
sources, private server configuration, and build scripts are not included in the
SDK branches or package. Do not assume a standalone SDK checkout contains that
application. Local maintainer instructions are retained in the
[Chinese guide](README.zh-CN.md#示例与速度测量).

## Models, validation, and licenses

RGB anti-spoofing does not verify the trustworthiness of the camera input source.
Replaying an old photo as multiple input frames is not a trusted capture flow.
This version has not completed representative live/print/screen-replay evaluation
across devices and lighting conditions and carries no payment or identity-check
certification claim.

This package takes the minimum of two live scores rather than the upstream
average. Upstream accuracy figures do not transfer to this integration.

- SDK code: [MIT](LICENSE).
- Minivision models and adapted crop logic: Apache-2.0; see
  [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- [MODEL_MANIFEST.json](MODEL_MANIFEST.json) and
  [MODEL_CONTEXT_MANIFEST.json](MODEL_CONTEXT_MANIFEST.json): pinned sources,
  hashes, sizes, conversion parity, and desktop benchmarks.
- `tool/export_model.py`: reproducible model export and numerical checks.
- [AGENT_GUIDE.md](AGENT_GUIDE.md): detailed maintainer instructions.
- [CHANGELOG.md](CHANGELOG.md): version history.
