import 'package:flutter/foundation.dart';

/// At most two current photos, in memory only. Compare bytes, not file names or
/// hashes: callers may reuse a buffer, and equal files may use different buffers.
class PhotoCache<T> {
  final _entries = <(Uint8List, T)>[];

  T? lookup(Uint8List bytes) {
    final index = _entries.indexWhere((entry) => listEquals(entry.$1, bytes));
    if (index < 0) return null;
    final entry = _entries.removeAt(index);
    _entries.add(entry);
    return entry.$2;
  }

  void put(Uint8List bytes, T value) {
    _entries.removeWhere((entry) => listEquals(entry.$1, bytes));
    if (_entries.length == 2) _entries.removeAt(0);
    _entries.add((Uint8List.fromList(bytes), value));
  }

  void retain(Iterable<Uint8List> photos) {
    final inputs = photos.toList();
    _entries.removeWhere(
      (entry) => !inputs.any((bytes) => listEquals(entry.$1, bytes)),
    );
  }

  void clear() => _entries.clear();
}
