import 'package:flutter/material.dart';
import '../../l10n/generated/app_localizations.dart';

extension AppLocaleX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}

Locale? localeFromSetting(String languageCode) {
  return switch (languageCode) {
    'en' => const Locale('en'),
    'zh' => const Locale('zh'),
    _ => null,
  };
}
