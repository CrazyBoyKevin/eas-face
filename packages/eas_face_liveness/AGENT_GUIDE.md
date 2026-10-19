# Maintainer / AI Agent guide

## Scope and dependency direction

- Package name `eas_face_liveness`, local version 0.1.1, publish_to none.
- Depends on local eas_face 0.2.0 (searchImage API), image and flutter_onnxruntime 1.9.0.
- Never add the liveness model to eas_face's asset manifest: applications that use only eas_face must not gain its weight.
- Branch feat-local-passive-liveness. Do not publish without an explicit user request; do not change the original app's default server-search entry.

## Model contract

Pinned upstream commit and expected hashes are in tool/export_model.py and MODEL_MANIFEST.json. Source weights must match checksums before importing model code or loading state. PyTorch load uses weights_only=True. Do not change the model or normalization silently.

MiniFASNetV2 at scale 2.7 plus MiniFASNetV1SE at scale 4.0, 80x80, BGR NCHW float32 **0..255**. The upstream transform docstring says 0..1 but its implementation explicitly removes /255. Output is 3 logits, live index 1; apply stable softmax exactly once. Apply softmax separately to each model and use the MINIMUM live score, not upstream averaging. Require both scores >= threshold. Return modelScores; no fallback to a single model if the second fails. Keep original camera texture and surrounding context. Do not use face alignment, white balance, grayscale, beautification, dewarping or recognition previews.

Input geometry is in upright, unmirrored source pixels; face must be fully inside the image and >=80 px on both axes. Bilinear sampling follows OpenCV half-pixel coordinates; at most 1 uint8 intensity rounding difference is tested over 115,200 synthetic values across both scales. Face boxes are not resized twice.

## API and state

- FaceLivenessEngine: loads two sessions, no detection/camera/network. evaluateFrame serial, throws on reentry/invalid data/runtime failure. Release tensors even on failure and reject duplicate handles. close waits initialization and rejects active inference. Closed instances cannot be reused.
- PassiveLivenessSession: monotonic timestamp, same box IoU>=0.5, per-frame score>=0.90, >=3 accepted frames, >=600ms, >=100ms spacing, max700ms gap by default. Reset on low/nonfinite score, reversed time, large gap/jump. No stale pass getter. This is not a camera-origin proof; raw session consumers must bind identity themselves.
- LiveFaceVerifier: owns supplied engines. Reject availableLivenessContext < 2.7 with insufficientContext before inference. searchImage runs once, then liveness uses that same candidate's original box. Require one detected frame face and one reference face, matching identity on EVERY accepted frame. Return false for multiple faces, no faces, mismatch, exceptions or reset-during-inference. Reference bytes (including in-place mutation) and frame-dimension changes reset accumulation. reset must invalidate in-flight completion. Keep no camera frames persistently. Reset after errors and resume only fresh evidence.
- High-level multi-person joint verification is deliberately not implemented in this first version. Do not combine person A's identity with B's live score. Base SDK all-face matching remains unchanged. Low-level API can be used by a future per-track implementation.
- Top-level JSON passed is joint result; comparison.passed is only identity. Honor custom identity threshold in JSON. Coordinates integer; numeric score/timing fields rounded to two decimals without strings.

## Camera demo

lib/main_liveness.dart selects LiveFaceApp(enableLiveness:true), opening ServerFacePage with on-device liveness and the same FaceApi as the static demo. No reference picker or gallery lookup in this mode: capture the viewfinder, evaluate its original pixels locally, send only embeddings after a passing single-frame score, then bind temporal confirmation to the same matched server business ID on EVERY accepted frame. At least 3 frames and 600ms are required; multiple detections, low score, identity changes, ambiguous/no match, network failure, geometry changes and >700ms frame gaps reset evidence. Responses older than 1500ms are discarded. App orchestration lives in lib/server_liveness_verifier.dart; the SDK has no network dependency. Busy frames are dropped, minimum250ms interval. Pause/switch/background/dispose reset generation and verification. Stop camera, await work, then close engines and API. The original main.dart remains the static server-search demo; LiveFacePage retains the separate reference-photo comparison widget for existing callers. Do not capture or upload user photos for tests.

## Verification

Run flutter test and flutter analyze in this package, base package tests, root tests and analyze changed app files. Fake runtime tests verify shape, channel order, softmax, disposal, failures and concurrency; they are not model accuracy tests.

Reproduce model conversion using Python with torch/onnx/onnxruntime/numpy:

```sh
python packages/eas_face_liveness/tool/export_model.py --cache verification/liveness-source
```

Expected weights and upstream model definition are downloaded only by that development script. Runtime is offline. The benchmark is synthetic desktop CPU inference with two threads, 20 warmups and 200 measured iterations. Report mobile timing only after an actual mobile benchmark. Never present desktop timing as complete verification latency.

Generate OpenCV crop reference with tool/make_preprocessing_fixture.py --upstream-crop <pinned src/generate_patches.py>. That fixture is synthetic colored pixels, not personal data. Keep evaluation images, templates and PTH files out of distributable archives. Use .pubignore overrides so both ONNX assets is included despite repo gitignore.

## Release gates

This is an engineering integration, not a calibrated/certified anti-spoof product. Device/camera-specific live/print/display replay data and false accept/reject evaluation are outstanding. Do not claim temporal repetition prevents photo/video injection or masks. Preserve standalone limitations in human README. Release on pub.dev requires a resolvable published eas_face dependency and explicit user instruction.

## Known false acceptance / retest candidate

The user reported that a large static photo displayed on another screen passed the original single-model iPhone demo. 0.1.1 adds dual-model minimum-score agreement and a minimum 2.7x source-context quality gate in app/joint verification. The 4x crop may still clamp to available source bounds. The framing gate is NOT a screen detector. Do not claim this attack is fixed until live and replay samples are actually retested. Preserve passive operation; the user explicitly rejected action challenges.
