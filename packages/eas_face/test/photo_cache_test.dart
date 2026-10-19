import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:eas_face/src/photo_cache.dart';

void main() {
  Uint8List bytes(int value) => Uint8List.fromList([value, 2, 3]);

  test('matches full contents, snapshots mutable inputs, and evicts LRU', () {
    final cache = PhotoCache<String>();
    final original = bytes(1);
    cache.put(original, 'a');
    original[0] = 9;
    expect(cache.lookup(original), isNull);
    expect(cache.lookup(bytes(1)), 'a');
    cache.put(bytes(4), 'b');
    expect(cache.lookup(bytes(1)), 'a');
    cache.put(bytes(5), 'c');
    expect(cache.lookup(bytes(4)), isNull);
    expect(cache.lookup(bytes(1)), 'a');
    expect(cache.lookup(bytes(5)), 'c');
  });

  test(
    'removed photos are evicted; replacing an entry does not grow cache',
    () {
      final cache = PhotoCache<String>();
      cache.put(bytes(1), 'a');
      cache.put(bytes(4), 'b');
      cache.put(bytes(1), 'a2');
      expect(cache.lookup(bytes(4)), 'b');
      cache.retain([bytes(1)]);
      expect(cache.lookup(bytes(1)), 'a2');
      expect(cache.lookup(bytes(4)), isNull);
      cache.clear();
      expect(cache.lookup(bytes(1)), isNull);
    },
  );
}
