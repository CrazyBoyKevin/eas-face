# Validation — 2026-10-16

## Known failure and 0.1.1 retest candidate

- User reported that a large static photo displayed on another screen passed the 0.1.0 iPhone demo. The earlier joint-pass screen is not evidence of successful spoof rejection. The single-model version must not be treated as a reliable liveness gate.
- 0.1.1 adds MiniFASNetV1SE with 4x context to the 2.7x MiniFASNetV2. Acceptance uses the lower live score, requiring both models >=0.90. This is stricter than upstream averaging but has NOT been validated on a live/replay evaluation set.
- App and joint verification reject source context below 2.7x before inference/search. This is a framing quality gate, not a screen detector; the 4x crop may still be limited by image boundaries.
- MiniFASNetV1SE export: 1,742,703 bytes, SHA-256 `21a0f3ac61d280708f4f47e2d09b8cc4c32b4fe14c8da53ad463fc6a919da8ff`; maximum PyTorch/ONNX logit difference on synthetic inputs 0.0000141263. See MODEL_CONTEXT_MANIFEST.json.
- The original screen attack and live acceptance must be retested before claiming improvement. Remain passive: no blink/turn challenges were added.
- 0.1.1 Release was built, its signature verified, both bundled ONNX hashes verified against their manifests, then installed and launched on the connected iPhone 15 Pro. User-assisted live-versus-screen retest is pending; installation alone is not an accuracy result.

## Automated checks

- Extension: 18 tests passed, including dual-model disagreement, second-model errors and partial-initialization retry.
- Base `eas_face`: 42 existing tests passed.
- Root application: 31 tests passed, including the camera-only server-liveness demo at two phone sizes and 12 server-liveness orchestration tests.
- Changed app entry, camera page and widget tests: analysis clean.
- Runtime adapter tests simulate native output; they verify tensor shape/channel order, stable class-1 softmax, resource disposal, error handling, concurrent-call rejection and initialization retry. They do not measure actual anti-spoof accuracy.
- Session/verifier tests cover minimum count AND time, duplicate/reversed timestamps, rate limiting, gaps, face movement, missing/multiple faces, reference byte mutation, resolution changes, failed inference, reset while inference is pending, and custom match-threshold JSON.
- Synthetic OpenCV reference: 115,200 preprocessing values across both scales and central/edge crops agree within 1 uint8 intensity value. New crop sizes include more half-value rounding ties; the previous fixture-specific mean <0.2 bound became <0.5 while the per-element <=1 contract remains unchanged. No personal images used.
- Server-liveness orchestration tests verify original-frame local inference, embedding-only requests, no request on low/invalid score or multiple/missing/unusable faces, the 600ms window, business-ID changes, ambiguous/no match, pause/reset, geometry changes, capture gaps, network failure, stale responses and reset during pending inference/search.
- Existing server health endpoint: HTTPS 200, 218 templates, matching feature version. This read-only check did not submit camera images or biometric features.

## Actual model conversion and desktop inference

- Original: pinned Minivision MiniFASNetV2, PyTorch 2.14.1; converted FP32 ONNX opset 17, IR 8.
- Model: 1,743,535 bytes; SHA-256 `151851621df3e93f7127847271e923a7a8247b8f6f4c9bb4e46170d1eba7400b`.
- PyTorch/ONNX maximum absolute logit difference over zero/constant/random input: 0.0000028611.
- ONNX Runtime 1.31.0 CPU, macOS arm64, 2 intra-op threads / 1 inter-op thread; 20 warmups, 200 timed iterations.
- Pure inference P50: 0.5974 ms; P95: 0.6464 ms. Input was synthetic, no camera, image conversion, Flutter bridge or preprocessing included. These are NOT phone latency or accuracy results.
- Raw output and provenance are retained in MODEL_MANIFEST.json.

## Historical 0.1.0 native builds

- Camera-only server-liveness demo: Android ARM64 Release built with `scripts/build_liveness_android.sh`, using the existing server configuration. Output: `dist/eas-face-liveness-demo-arm64.apk` (136,313,405 bytes). Verified the packaged liveness model SHA-256 and HTTPS CA asset; exactly three ONNX models are bundled.
- Camera-only server-liveness demo: iOS simulator Debug build succeeded with `scripts/build_liveness_ios.sh`; installed and launched on the iPhone 17 Pro / iOS 26.5 simulator. Both local model initialization and HTTPS health succeeded; the screen shows 218 server records and a camera start button with no photo picker. Screenshot: `verification/liveness-server-simulator.png`. No real camera liveness claim is made from this startup check.
- Android debug camera demo built with `flutter build apk --debug --target lib/main_liveness.dart`.
- Confirmed APK contains one new liveness ONNX asset (raw 1,743,535 bytes / APK compressed 1,609,678 bytes) and the two existing face models. No original PTH files bundled.
- iOS simulator Debug build succeeded with Xcode using derived data outside the workspace at `~/Library/Caches/eas-face-liveness-build`.
- Initial iOS failure: generated Flutter SPM wrapper advertised iOS 15 while the project and existing runtime require iOS 16. Aligned the generated wrapper to 16.0 and rebuilt with xcodebuild. scripts/build_liveness_ios.sh reproduces this adjustment after Flutter configuration generation. No changes to the original package's minimum OS or model were needed.

## Not yet validated

- Physical Android timing; iPhone cold start, capture-to-confirm P50/P95 and thermal behavior. The limited iPhone observations below are not a latency distribution.
- Business live/print/screen replay dataset, error rates and device/lighting-specific threshold calibration.
- Camera provenance/injection protection, mask/deepfake defenses or any certification.

The implementation is a local engineering build, not a production anti-spoof accuracy claim. Default score threshold 0.90 and 600ms window are initial engineering settings.

## Historical 0.1.0 iPhone installation and camera-flow smoke check

- Installed and launched the Release server-liveness demo on a connected iPhone 15 Pro (iOS 27.0.1), using the existing development signing team and server configuration. Bundle: `com.localface.faceComparison`.
- Observed the live camera preview and successful server connection (218 records). A subsequent screen displayed the joint-pass state and the returned business marker after 4 accepted frames spanning 800ms.
- Two observed frames reported local liveness processing of 2ms, full frame processing of 124ms / 127ms, feature extraction of 77ms, and network round trips of 28ms / 31ms. These are UI-reported samples, not P50/P95 benchmarks. The 800ms observation window is separate from one-frame processing latency.
- No runtime errors appeared in the attached app console during this brief check. This verifies device integration and the displayed result flow; it does not establish that a given camera subject is genuinely live, or validate print/screen replay rejection.
- Build/install logs and screenshots remain under ignored `verification/`; camera images are not included in distributable artifacts.
