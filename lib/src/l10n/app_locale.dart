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

Locale preferredLocaleFromSetting(String languageCode) {
  return localeFromSetting(languageCode) ??
      WidgetsBinding.instance.platformDispatcher.locale;
}

String preferredLocaleTagFromSetting(String languageCode) {
  final locale = preferredLocaleFromSetting(languageCode);
  final countryCode = locale.countryCode;
  if (countryCode == null || countryCode.trim().isEmpty) {
    return locale.languageCode;
  }
  return '${locale.languageCode}_${countryCode.trim().toUpperCase()}';
}
