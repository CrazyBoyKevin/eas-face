import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:eas_face/eas_face.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: SdkExample()));
}

class SdkExample extends StatefulWidget {
  const SdkExample({super.key});
  @override
  State<SdkExample> createState() => _SdkExampleState();
}

class _SdkExampleState extends State<SdkExample> {
  final _engine = FaceEngine();
  final _photos = <Uint8List?>[null, null];
  Future<void>? _pending;
  bool _busy = true;
  String _message = 'Loading local models…';

  @override
  void initState() {
    super.initState();
    _pending = _load();
  }

  Future<void> _load() async {
    try {
      await _engine.initialize();
      if (mounted) setState(() => _message = 'Select two photos');
    } catch (error) {
      if (mounted) setState(() => _message = 'Initialization failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(int index) async {
    setState(() => _busy = true);
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (photo == null || !mounted) return;
      if (await photo.length() > maxFileBytes) {
        throw const FormatException('Select a photo smaller than 15 MB');
      }
      final bytes = await photo.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photos[index] = bytes;
        _message = 'Ready to compare';
      });
      _engine.retainCachedPhotos(_photos.whereType<Uint8List>());
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _compare() async {
    setState(() => _busy = true);
    try {
      final result = await _engine.compare(_photos[0]!, _photos[1]!);
      if (mounted) {
        setState(
          () =>
              _message =
                  '${formatLikeness(result.likeness)}\n'
                  '${(result.elapsed.inMicroseconds / 1000).toStringAsFixed(2)} ms',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    final pending = _pending;
    unawaited(() async {
      await pending;
      await _engine.close();
    }());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('EAS Face SDK example')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          for (var i = 0; i < 2; i++) ...[
            if (_photos[i] != null)
              Image.memory(_photos[i]!, height: 180, cacheWidth: 600),
            OutlinedButton(
              onPressed:
                  _busy
                      ? null
                      : () {
                        _pending = _pick(i);
                      },
              child: Text('Select photo ${i + 1}'),
            ),
          ],
          FilledButton(
            onPressed:
                _busy || !_engine.isReady || _photos.any((p) => p == null)
                    ? null
                    : () {
                      _pending = _compare();
                    },
            child: const Text('Compare on device'),
          ),
          if (!_engine.isReady && !_busy)
            TextButton(
              onPressed: () {
                setState(() => _busy = true);
                _pending = _load();
              },
              child: const Text('Retry initialization'),
            ),
          const SizedBox(height: 16),
          Text(_message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          const Text(
            'The percentage is a model display scale, not a measured likeness ratio or identity probability.',
          ),
        ],
      ),
    ),
  );
}
