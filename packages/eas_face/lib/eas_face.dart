/// Local face comparison. No camera, picker, image upload, or persistent history.
library;

export 'src/face_engine.dart'
    show
        FaceEngine,
        FaceSample,
        FaceComparison,
        FaceSearchResult,
        FaceFrameSamples,
        maxFileBytes;
export 'src/face_math.dart' show FacePoint, FaceDetection;
export 'src/face_score.dart'
    show
        defaultThreshold,
        recognitionReferenceCosine,
        sfaceReferenceCosine,
        likenessScore,
        formatLikeness;
