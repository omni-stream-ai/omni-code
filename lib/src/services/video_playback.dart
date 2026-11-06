import 'package:fvp/fvp.dart' as fvp;
import 'package:flutter/foundation.dart';

/// Supply the desktop implementation behind the app's existing video_player API.
/// Android, iOS, macOS and web keep their platform implementations.
void initializeVideoPlayback() {
  fvp.registerWith(options: {
    'platforms': <String>['linux', 'windows'],
    // VA-API can initialize without a usable display/driver, then return blank
    // frames or crash instead of falling back. Software decoding also works
    // on desktops and acceptance environments without GPU drivers.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux)
      'video.decoders': <String>['FFmpeg'],
  });
}
