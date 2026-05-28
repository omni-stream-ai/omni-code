class KwsWakeWordNormalization {
  const KwsWakeWordNormalization({
    required this.original,
    required this.normalized,
    required this.unsupportedTokens,
  });

  final String original;
  final String normalized;
  final List<String> unsupportedTokens;

  bool get isSupported => unsupportedTokens.isEmpty && normalized.isNotEmpty;
}

class KwsWakeWordNormalizer {
  KwsWakeWordNormalizer({Set<String>? modelTokens})
      : _modelTokens = modelTokens ?? defaultModelTokens;

  final Set<String> _modelTokens;

  static const Set<String> defaultModelTokens = {
    'AA0',
    'AA1',
    'AA2',
    'AE0',
    'AE1',
    'AE2',
    'AH0',
    'AH1',
    'AH2',
    'AO0',
    'AO1',
    'AO2',
    'AW0',
    'AW1',
    'AW2',
    'AY0',
    'AY1',
    'AY2',
    'B',
    'CH',
    'D',
    'DH',
    'EH0',
    'EH1',
    'EH2',
    'ER0',
    'ER1',
    'ER2',
    'EY0',
    'EY1',
    'EY2',
    'F',
    'G',
    'HH',
    'IH0',
    'IH1',
    'IH2',
    'IY0',
    'IY1',
    'IY2',
    'JH',
    'K',
    'L',
    'M',
    'N',
    'NG',
    'OW0',
    'OW1',
    'OW2',
    'OY0',
    'OY1',
    'OY2',
    'P',
    'R',
    'S',
    'SH',
    'T',
    'TH',
    'UH0',
    'UH1',
    'UH2',
    'UW0',
    'UW1',
    'UW2',
    'V',
    'W',
    'Y',
    'Z',
    'ZH',
    'a',
    'ai',
    'an',
    'ang',
    'ao',
    'b',
    'c',
    'ch',
    'd',
    'e',
    'ei',
    'en',
    'eng',
    'er',
    'f',
    'g',
    'h',
    'hm',
    'i',
    'ia',
    'ian',
    'iang',
    'iao',
    'ie',
    'in',
    'ing',
    'iu',
    'ià',
    'iàn',
    'iàng',
    'iào',
    'iá',
    'ián',
    'iáng',
    'iáo',
    'iè',
    'ié',
    'iòng',
    'ióng',
    'iù',
    'iú',
    'iā',
    'iān',
    'iāng',
    'iāo',
    'iē',
    'iě',
    'iōng',
    'iǎ',
    'iǎn',
    'iǎng',
    'iǎo',
    'iǒng',
    'iǔ',
    'j',
    'k',
    'l',
    'm',
    'n',
    'o',
    'ong',
    'ou',
    'p',
    'q',
    'r',
    's',
    'sh',
    't',
    'u',
    'ua',
    'uai',
    'uan',
    'uang',
    'ue',
    'ui',
    'un',
    'uo',
    'uà',
    'uài',
    'uàn',
    'uàng',
    'uá',
    'uái',
    'uán',
    'uáng',
    'uè',
    'ué',
    'uì',
    'uí',
    'uò',
    'uó',
    'uā',
    'uāi',
    'uān',
    'uāng',
    'uē',
    'uě',
    'uī',
    'uō',
    'uǎ',
    'uǎi',
    'uǎn',
    'uǎng',
    'uǐ',
    'uǒ',
    'v',
    'w',
    'x',
    'y',
    'z',
    'zh',
    'à',
    'ài',
    'àn',
    'àng',
    'ào',
    'á',
    'ái',
    'án',
    'áng',
    'áo',
    'è',
    'èi',
    'èn',
    'èng',
    'èr',
    'é',
    'éi',
    'én',
    'éng',
    'ér',
    'ì',
    'ìn',
    'ìng',
    'í',
    'ín',
    'íng',
    'ò',
    'òng',
    'òu',
    'ó',
    'óng',
    'óu',
    'ù',
    'ùn',
    'ú',
    'ún',
    'üè',
    'üě',
    'ā',
    'āi',
    'ān',
    'āng',
    'āo',
    'ē',
    'ēi',
    'ēn',
    'ēng',
    'ě',
    'ěi',
    'ěn',
    'ěng',
    'ěr',
    'ī',
    'īn',
    'īng',
    'ń',
    'ň',
    'ō',
    'ōng',
    'ōu',
    'ū',
    'ūn',
    'ǎ',
    'ǎi',
    'ǎn',
    'ǎng',
    'ǎo',
    'ǐ',
    'ǐn',
    'ǐng',
    'ǒ',
    'ǒng',
    'ǒu',
    'ǔ',
    'ǔn',
    'ǘ',
    'ǚ',
    'ǜ',
    'ǹ',
    'ḿ',
  };

  static const Map<String, String> _knownEnglishPhrases = {
    'hey omni': 'HH EY1 OW1 M N IY0',
  };

  List<KwsWakeWordNormalization> normalizeAll(List<String> wakeWords) {
    return wakeWords.map(normalize).toList(growable: false);
  }

  KwsWakeWordNormalization normalize(String wakeWord) {
    final original = wakeWord.trim();
    if (original.isEmpty) {
      return KwsWakeWordNormalization(
        original: wakeWord,
        normalized: '',
        unsupportedTokens: const [],
      );
    }

    final knownPhrase = _knownEnglishPhrases[original.toLowerCase()];
    if (knownPhrase != null) {
      return KwsWakeWordNormalization(
        original: wakeWord,
        normalized: knownPhrase,
        unsupportedTokens: const [],
      );
    }

    final rawTokens = original.split(RegExp(r'\s+'));
    if (rawTokens.every(_modelTokens.contains)) {
      return KwsWakeWordNormalization(
        original: wakeWord,
        normalized: rawTokens.join(' '),
        unsupportedTokens: const [],
      );
    }

    final normalizedTokens = <String>[];
    final unsupportedTokens = <String>[];
    for (final rawToken in rawTokens) {
      final pinyinToken = _numberedPinyinToMarked(rawToken.toLowerCase());
      if (pinyinToken == null) {
        unsupportedTokens.add(rawToken);
        continue;
      }
      final pieces = _splitIntoModelTokens(pinyinToken);
      if (pieces == null) {
        unsupportedTokens.add(rawToken);
        continue;
      }
      normalizedTokens.addAll(pieces);
    }

    return KwsWakeWordNormalization(
      original: wakeWord,
      normalized: normalizedTokens.join(' '),
      unsupportedTokens: unsupportedTokens,
    );
  }

  List<String>? _splitIntoModelTokens(String value) {
    final pieces = <String>[];
    var offset = 0;
    while (offset < value.length) {
      String? match;
      for (var end = value.length; end > offset; end--) {
        final candidate = value.substring(offset, end);
        if (_modelTokens.contains(candidate)) {
          match = candidate;
          break;
        }
      }
      if (match == null) {
        return null;
      }
      pieces.add(match);
      offset += match.length;
    }
    return pieces;
  }

  String? _numberedPinyinToMarked(String value) {
    final match = RegExp(r'^([a-züv]+)([1-5])$').firstMatch(value);
    if (match == null) {
      return null;
    }
    final syllable = match.group(1)!.replaceAll('v', 'ü');
    final tone = int.parse(match.group(2)!);
    if (tone == 5) {
      return syllable;
    }
    final vowelIndex = _toneMarkVowelIndex(syllable);
    if (vowelIndex == null) {
      return null;
    }
    final vowel = syllable[vowelIndex];
    final marked = _toneMarks[vowel]?[tone - 1];
    if (marked == null) {
      return null;
    }
    return syllable.replaceRange(vowelIndex, vowelIndex + 1, marked);
  }

  int? _toneMarkVowelIndex(String syllable) {
    final a = syllable.indexOf('a');
    if (a >= 0) return a;
    final e = syllable.indexOf('e');
    if (e >= 0) return e;
    final ou = syllable.indexOf('ou');
    if (ou >= 0) return ou;
    for (var i = syllable.length - 1; i >= 0; i--) {
      if ('iouü'.contains(syllable[i])) {
        return i;
      }
    }
    return null;
  }

  static const Map<String, List<String>> _toneMarks = {
    'a': ['ā', 'á', 'ǎ', 'à'],
    'e': ['ē', 'é', 'ě', 'è'],
    'i': ['ī', 'í', 'ǐ', 'ì'],
    'o': ['ō', 'ó', 'ǒ', 'ò'],
    'u': ['ū', 'ú', 'ǔ', 'ù'],
    'ü': ['ǖ', 'ǘ', 'ǚ', 'ǜ'],
  };
}
