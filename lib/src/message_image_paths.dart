import 'dart:convert';
import 'dart:typed_data';

import 'bridge_client.dart';

class MessageImageReference {
  const MessageImageReference._(
    this.path, {
    this.mimeType,
    this.dataBytes,
  });

  final String path;
  final String? mimeType;
  final Uint8List? dataBytes;

  String get displayPath =>
      isDataUri ? 'data:${mimeType ?? 'image'};base64,...' : path;

  String get cardKey {
    if (!isDataUri) {
      return path;
    }
    return 'data-image-${path.length}-${_stableHash(path)}';
  }

  bool get isRemoteUrl {
    final uri = Uri.tryParse(path);
    return uri != null && (uri.scheme.eq('http') || uri.scheme.eq('https'));
  }

  bool get isDataUri => mimeType != null && dataBytes != null;

  bool get isAbsoluteLocalPath => BridgeClient.isAbsoluteFilePath(path);

  bool get isSvg => isDataUri
      ? mimeType != null && mimeType!.eq('image/svg+xml')
      : path.toLowerCase().endsWith('.svg');

  static MessageImageReference? tryParse(String raw) {
    var value = raw.trim();
    if (value.isEmpty) {
      return null;
    }

    value = _stripWrapping(value);
    if (value.isEmpty) {
      return null;
    }

    final dataUriReference = _tryParseDataUri(value);
    if (dataUriReference != null) {
      return dataUriReference;
    }

    final uri = Uri.tryParse(value);
    if (uri != null && uri.scheme.eq('file')) {
      value = uri.toFilePath();
    }

    if (!BridgeClient.isSupportedImagePath(value)) {
      return null;
    }

    return MessageImageReference._(value);
  }
}

List<MessageImageReference> extractMessageImageReferences(String content) {
  final matches = <String, MessageImageReference>{};

  void addCandidate(String value) {
    final reference = MessageImageReference.tryParse(value);
    if (reference == null) {
      return;
    }
    matches.putIfAbsent(reference.path, () => reference);
  }

  for (final match in _markdownLinkPattern.allMatches(content)) {
    final rawDestination = match.group(1) ?? match.group(2);
    if (rawDestination == null) {
      continue;
    }
    addCandidate(_normalizeMarkdownDestination(rawDestination));
  }

  for (final match in _inlineCodePattern.allMatches(content)) {
    final value = match.group(1);
    if (value != null) {
      addCandidate(value);
    }
  }

  for (final match in _bareDataImagePattern.allMatches(content)) {
    final value = match.group(0);
    if (value != null) {
      addCandidate(value);
    }
  }

  for (final match in _bareImagePathPattern.allMatches(content)) {
    final value = match.group(1);
    if (value != null) {
      addCandidate(value);
    }
  }

  return matches.values.toList(growable: false);
}

final RegExp _markdownLinkPattern =
    RegExp(r"!?\[[^\]]*\]\(([^)]+)\)|<((?:https?|file)://[^>]+)>");
final RegExp _inlineCodePattern = RegExp(r'`([^`\n]+)`');
final RegExp _bareDataImagePattern = RegExp(
  r'data:image\/(?:png|jpe?g|gif|webp|bmp|svg\+xml)(?:;[^,;]+(?:=[^,;]+)?)*;base64,[A-Za-z0-9+/=]+',
  caseSensitive: false,
);
final RegExp _bareImagePathPattern = RegExp(
  r"""(?:(?<=^)|(?<=[\s(>:\[\-]))((?:\.\.?[\\/]|[\\/]|[A-Za-z]:[\\/])?[^\s<>()\[\]{}"'`]+\.(?:png|jpe?g|gif|webp|bmp|svg))(?=$|[\s),.!?;:\]\}])""",
  caseSensitive: false,
);

MessageImageReference? _tryParseDataUri(String value) {
  final match = _dataUriPattern.firstMatch(value);
  if (match == null) {
    return null;
  }

  final mimeType = match.group(1)?.toLowerCase();
  final encoded = match.group(2);
  if (mimeType == null || encoded == null) {
    return null;
  }

  try {
    final bytes = base64Decode(encoded);
    return MessageImageReference._(
      'data:$mimeType;base64,$encoded',
      mimeType: mimeType,
      dataBytes: bytes,
    );
  } on FormatException {
    return null;
  }
}

final RegExp _dataUriPattern = RegExp(
  r'^data:(image\/(?:png|jpe?g|gif|webp|bmp|svg\+xml))(?:;[^,;]+(?:=[^,;]+)?)*;base64,([A-Za-z0-9+/=]+)$',
  caseSensitive: false,
);

String _normalizeMarkdownDestination(String rawDestination) {
  final trimmed = rawDestination.trim();
  if (trimmed.startsWith('<')) {
    final end = trimmed.indexOf('>');
    if (end > 1) {
      return trimmed.substring(1, end);
    }
  }

  final titleMatch =
      RegExp(r"""^(.*?)(?:\s+["'][^"']*["'])$""").firstMatch(trimmed);
  if (titleMatch != null) {
    return titleMatch.group(1)?.trim() ?? trimmed;
  }
  return trimmed;
}

String _stripWrapping(String value) {
  var next = value;
  const trailing = '.,!?:;)]}>';
  const leading = '(<[{';

  while (next.isNotEmpty && leading.contains(next[0])) {
    next = next.substring(1);
  }
  while (next.isNotEmpty && trailing.contains(next[next.length - 1])) {
    next = next.substring(0, next.length - 1);
  }

  if ((next.startsWith('"') && next.endsWith('"')) ||
      (next.startsWith("'") && next.endsWith("'")) ||
      (next.startsWith('`') && next.endsWith('`'))) {
    next = next.substring(1, next.length - 1).trim();
  }

  return next;
}

extension on String {
  bool eq(String other) => toLowerCase() == other;
}

String _stableHash(String value) {
  var hash = 0x811C9DC5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7FFFFFFF;
  }
  return hash.toRadixString(16);
}
