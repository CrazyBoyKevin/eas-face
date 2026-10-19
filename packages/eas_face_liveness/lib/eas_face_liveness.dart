/// On-device passive anti-spoofing. Requires fresh camera frames; never apply
/// to passport/reference photos. Scores are model outputs, not probabilities
/// that a real person is present. No camera capture or network is included.
library;

export 'src/liveness_engine.dart';
export 'src/liveness_session.dart';
export 'src/liveness_preprocessing.dart' show availableLivenessContext;
export 'src/live_face_verifier.dart';
