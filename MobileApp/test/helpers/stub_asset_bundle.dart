import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// An 8x8 grey square served for every asset key.
///
/// Layout tests assert which elements a screen renders; whether a bundled
/// bitmap decodes is a different question and must not be able to redden
/// them. A visible grey block (rather than a transparent pixel) also
/// makes the preview sheets legible, since an image slot then reads as a
/// placeholder instead of a hole.
final Uint8List kStubPixel = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x08,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x4B, 0x6D, 0x29, 0xDC, 0x00, 0x00, 0x00,
  0x15, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xEC, 0x9E, 0x30, 0x8D,
  0x01, 0x1B, 0x60, 0x62, 0xC0, 0x01, 0x06, 0xA7, 0x04, 0x00, 0x55, 0xF2,
  0x01, 0xC1, 0x9C, 0x7D, 0xA5, 0x80, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class StubAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    // The manifest must still decode, or every AssetImage fails while
    // resolving variants rather than while loading bytes.
    if (key == 'AssetManifest.bin' || key == 'AssetManifest.bin.json') {
      return const StandardMessageCodec().encodeMessage(<String, Object>{})!;
    }
    return ByteData.sublistView(kStubPixel);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async => '';
}

/// Wraps [child] so every asset resolves against [StubAssetBundle].
Widget withStubAssets(Widget child) =>
    DefaultAssetBundle(bundle: StubAssetBundle(), child: child);
