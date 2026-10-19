/// Application display scale, not a probability or measured visual likeness.
/// 0 -> 0%, the Intel demo reference 0.4 -> 60%, and 1 -> 100%.
/// The reference point is model/dataset-specific; this is NOT calibration.
/// Intel demo: distance = (1 - cosine) / 2; distance <= 0.3.
/// This is a demo operating point, not a passport/selfie accuracy guarantee.
const recognitionReferenceCosine = 0.4;
const defaultThreshold = 0.60;

double likenessScore(double cosine) {
  if (!cosine.isFinite) {
    throw ArgumentError.value(cosine, 'cosine', 'Must be finite');
  }
  final value = cosine.clamp(0.0, 1.0);
  if (value <= recognitionReferenceCosine) {
    return value / recognitionReferenceCosine * defaultThreshold;
  }
  return defaultThreshold +
      (value - recognitionReferenceCosine) /
          (1 - recognitionReferenceCosine) *
          (1 - defaultThreshold);
}

String formatLikeness(double score) =>
    '${(score.clamp(0.0, 1.0) * 100).toStringAsFixed(2)}%';

/// Legacy SFace reference, retained only for migration of old results.
@Deprecated('Intel 0095 uses recognitionReferenceCosine')
const sfaceReferenceCosine = 0.363;
