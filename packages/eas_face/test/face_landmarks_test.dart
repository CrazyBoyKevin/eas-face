import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eas_face/src/face_landmarks.dart';
import 'package:eas_face/src/face_math.dart';

void main() {
  testWidgets(
    'landmarks follow centered contain with horizontal and vertical padding',
    (tester) async {
      Future<void> check(
        Size imageSize,
        FacePoint point,
        Offset expected,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 300,
                height: 240,
                child: FaceLandmarkOverlay(
                  imageSize: imageSize,
                  points: [point],
                  matches: true,
                ),
              ),
            ),
          ),
        );
        final origin = tester.getTopLeft(find.byType(FaceLandmarkOverlay));
        final dot = tester.getCenter(
          find.byKey(const ValueKey('landmark-dot-0')),
        );
        expect(dot - origin, expected);
        expect(tester.takeException(), isNull);
      }

      await check(
        const Size(600, 300),
        const FacePoint(150, 75),
        const Offset(75, 82.5),
      );
      await check(
        const Size(300, 600),
        const FacePoint(75, 150),
        const Offset(120, 60),
      );
      await check(
        const Size(300, 240),
        const FacePoint(75, 60),
        const Offset(75, 60),
      );
    },
  );

  testWidgets('all five dots change color together without numeric labels', (
    tester,
  ) async {
    for (final matches in [true, false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 300,
            height: 240,
            child: FaceLandmarkOverlay(
              imageSize: const Size(300, 240),
              points: canonicalLandmarks,
              matches: matches,
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        final dot = tester.widget<Container>(
          find.byKey(ValueKey('landmark-dot-$i')),
        );
        expect(
          (dot.decoration as BoxDecoration).color,
          matches ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
        );
      }
      expect(find.byType(Text), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
