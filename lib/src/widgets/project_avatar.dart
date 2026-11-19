import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart';

/// The same project identity in project pickers, navigation, and task lists.
class ProjectAvatar extends StatelessWidget {
  const ProjectAvatar({
    super.key,
    required this.name,
    this.iconDataUri,
    this.size = 34,
  });

  final String name;
  final String? iconDataUri;
  final double size;
  static final _decoded = <String, Uint8List?>{};

  static Uint8List? _bytes(String uri) {
    if (_decoded.containsKey(uri)) return _decoded[uri];
    Uint8List? bytes;
    try {
      final data = UriData.parse(uri);
      if (data.isBase64 &&
          (data.mimeType == 'image/png' || data.mimeType == 'image/svg+xml')) {
        bytes = data.contentAsBytes();
      }
    } on FormatException {
      // Missing and invalid artwork use the same name fallback.
    }
    if (_decoded.length >= 128) _decoded.remove(_decoded.keys.first);
    _decoded[uri] = bytes;
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isLight = colors.brightness == Brightness.light;
    final foreground = isLight ? AppColors.lightSuccessText : colors.primary;
    final background = isLight
        ? AppColors.lightSuccessBg
        : colors.primary.withValues(alpha: .08);
    final trimmed = name.trim();
    final initial =
        trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
    final fallback = Center(
      child: Text(initial,
          maxLines: 1,
          style: TextStyle(
              fontSize: size * .46,
              fontWeight: FontWeight.w700,
              color: foreground)),
    );
    final uri = iconDataUri;
    final bytes = uri != null && uri.length <= 90000 ? _bytes(uri) : null;
    Widget artwork = fallback;
    if (bytes != null) {
      artwork = uri!.startsWith('data:image/svg+xml;')
          ? SvgPicture.memory(bytes,
              width: size,
              height: size,
              fit: BoxFit.contain,
              placeholderBuilder: (_) => fallback,
              errorBuilder: (_, __, ___) => fallback)
          : Image.memory(bytes,
              width: size,
              height: size,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => fallback);
    }
    return Semantics(
      label: name,
      image: true,
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(size * .24)),
          child: artwork,
        ),
      ),
    );
  }
}
