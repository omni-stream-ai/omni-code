import 'dart:ui';

import '../../l10n/generated/app_localizations.dart';
import '../../l10n/generated/app_localizations_en.dart';
import '../../l10n/generated/app_localizations_zh.dart';
import '../settings/app_settings.dart';

AppLocalizations currentL10n() {
  final configured = appSettingsController.settings.appLanguage;
  final code = switch (configured) {
    'en' => 'en',
    'zh' => 'zh',
    _ => PlatformDispatcher.instance.locale.languageCode.toLowerCase(),
  };
  return code.startsWith('zh')
      ? AppLocalizationsZh()
      : AppLocalizationsEn();
}
