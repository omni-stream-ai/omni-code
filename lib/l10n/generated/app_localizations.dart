import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Omni Code'**
  String get appTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get saving;

  /// No description provided for @systemSection.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get systemSection;

  /// No description provided for @languageSection.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSection;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get languageLabel;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get languageChinese;

  /// No description provided for @bridgeSection.
  ///
  /// In en, this message translates to:
  /// **'Bridge'**
  String get bridgeSection;

  /// No description provided for @bridgeUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Bridge URL'**
  String get bridgeUrlLabel;

  /// No description provided for @bridgeHelp.
  ///
  /// In en, this message translates to:
  /// **'Use 127.0.0.1:8787 with adb reverse. For LAN access, enter your computer IP. The server can allow requests by token and client ID.'**
  String get bridgeHelp;

  /// No description provided for @appUpdateSection.
  ///
  /// In en, this message translates to:
  /// **'App Update'**
  String get appUpdateSection;

  /// No description provided for @updateManifestUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Manifest URL'**
  String get updateManifestUrlLabel;

  /// No description provided for @updateTargetVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Target version'**
  String get updateTargetVersionLabel;

  /// No description provided for @updateTargetVersionHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional. Enter a release version like 0.2.1 to download that specific GitHub release instead of the latest one.'**
  String get updateTargetVersionHelp;

  /// No description provided for @checkingUpdate.
  ///
  /// In en, this message translates to:
  /// **'Checking...'**
  String get checkingUpdate;

  /// No description provided for @checkAppUpdate.
  ///
  /// In en, this message translates to:
  /// **'Check app update'**
  String get checkAppUpdate;

  /// No description provided for @updateHelp.
  ///
  /// In en, this message translates to:
  /// **'By default, updates are checked from the official GitHub release manifest. You can override it with a custom manifest URL, including a self-hosted Bridge manifest. When a new version is found, the system opens the download link and handles installation.'**
  String get updateHelp;

  /// No description provided for @speechSection.
  ///
  /// In en, this message translates to:
  /// **'Speech'**
  String get speechSection;

  /// No description provided for @ttsProviderLabel.
  ///
  /// In en, this message translates to:
  /// **'TTS Provider'**
  String get ttsProviderLabel;

  /// No description provided for @asrProviderLabel.
  ///
  /// In en, this message translates to:
  /// **'ASR Provider'**
  String get asrProviderLabel;

  /// No description provided for @bridgeCloudProxy.
  ///
  /// In en, this message translates to:
  /// **'Bridge / Cloud relay'**
  String get bridgeCloudProxy;

  /// No description provided for @apiKey.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get apiKey;

  /// No description provided for @appId.
  ///
  /// In en, this message translates to:
  /// **'App ID'**
  String get appId;

  /// No description provided for @secretId.
  ///
  /// In en, this message translates to:
  /// **'Secret ID'**
  String get secretId;

  /// No description provided for @secretKey.
  ///
  /// In en, this message translates to:
  /// **'Secret Key'**
  String get secretKey;

  /// No description provided for @baseUrl.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get baseUrl;

  /// No description provided for @aiApprovalSection.
  ///
  /// In en, this message translates to:
  /// **'AI Approval'**
  String get aiApprovalSection;

  /// No description provided for @enableAiApproval.
  ///
  /// In en, this message translates to:
  /// **'Enable AI-assisted approval'**
  String get enableAiApproval;

  /// No description provided for @enableAiApprovalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use a configured model to approve low-risk commands'**
  String get enableAiApprovalSubtitle;

  /// No description provided for @aiApprovalModel.
  ///
  /// In en, this message translates to:
  /// **'Approval model'**
  String get aiApprovalModel;

  /// No description provided for @aiApprovalProvider.
  ///
  /// In en, this message translates to:
  /// **'Approval model provider'**
  String get aiApprovalProvider;

  /// No description provided for @loadingApprovalModels.
  ///
  /// In en, this message translates to:
  /// **'Loading models...'**
  String get loadingApprovalModels;

  /// No description provided for @approvalModelsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load models; configured defaults are shown'**
  String get approvalModelsLoadFailed;

  /// No description provided for @noApprovalModels.
  ///
  /// In en, this message translates to:
  /// **'No models returned by this provider'**
  String get noApprovalModels;

  /// No description provided for @loadingModelProviders.
  ///
  /// In en, this message translates to:
  /// **'Loading configured models...'**
  String get loadingModelProviders;

  /// No description provided for @noConfiguredModels.
  ///
  /// In en, this message translates to:
  /// **'Configure and enable a model provider first'**
  String get noConfiguredModels;

  /// No description provided for @modelProvidersLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load configured models'**
  String get modelProvidersLoadFailed;

  /// No description provided for @selectAiApprovalModel.
  ///
  /// In en, this message translates to:
  /// **'Select an approval model'**
  String get selectAiApprovalModel;

  /// No description provided for @aiApprovalMaxRisk.
  ///
  /// In en, this message translates to:
  /// **'Highest auto-approval risk'**
  String get aiApprovalMaxRisk;

  /// No description provided for @aiApprovalHelp.
  ///
  /// In en, this message translates to:
  /// **'Saved settings sync to the current Bridge. Keeping Low is recommended. High-risk commands, failed calls, or hard-blocked rules still fall back to manual approval on the phone.'**
  String get aiApprovalHelp;

  /// No description provided for @aiApprovalPrompt.
  ///
  /// In en, this message translates to:
  /// **'Global approval prompt'**
  String get aiApprovalPrompt;

  /// No description provided for @aiApprovalPromptHint.
  ///
  /// In en, this message translates to:
  /// **'Add organization-wide approval guidance'**
  String get aiApprovalPromptHint;

  /// No description provided for @aiApprovalPromptEntrySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Edit the instructions used for automatic approval decisions'**
  String get aiApprovalPromptEntrySubtitle;

  /// No description provided for @projectAiApprovalPrompt.
  ///
  /// In en, this message translates to:
  /// **'Project approval prompt'**
  String get projectAiApprovalPrompt;

  /// No description provided for @projectAiApprovalPromptHint.
  ///
  /// In en, this message translates to:
  /// **'Add approval guidance for this project'**
  String get projectAiApprovalPromptHint;

  /// No description provided for @alwaysAllowedCommands.
  ///
  /// In en, this message translates to:
  /// **'Always allowed commands'**
  String get alwaysAllowedCommands;

  /// No description provided for @alwaysAllow.
  ///
  /// In en, this message translates to:
  /// **'Always allow'**
  String get alwaysAllow;

  /// No description provided for @autoApprovalAiReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'AI recommends your review'**
  String get autoApprovalAiReviewTitle;

  /// No description provided for @autoApprovalRiskThresholdTitle.
  ///
  /// In en, this message translates to:
  /// **'Risk exceeds the automatic approval limit'**
  String get autoApprovalRiskThresholdTitle;

  /// No description provided for @autoApprovalHardBlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Blocked by a safety rule'**
  String get autoApprovalHardBlockTitle;

  /// No description provided for @autoApprovalReviewFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Automatic review was unavailable'**
  String get autoApprovalReviewFailedTitle;

  /// No description provided for @autoApprovalHardBlockReason.
  ///
  /// In en, this message translates to:
  /// **'This command affects a protected or project-external resource, so it needs your confirmation.'**
  String get autoApprovalHardBlockReason;

  /// No description provided for @autoApprovalReviewFailedReason.
  ///
  /// In en, this message translates to:
  /// **'The approval model could not complete its review, so this request was sent to you instead.'**
  String get autoApprovalReviewFailedReason;

  /// No description provided for @projectApprovalSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Project approval settings saved'**
  String get projectApprovalSettingsSaved;

  /// No description provided for @riskLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get riskLow;

  /// No description provided for @riskMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get riskMedium;

  /// No description provided for @riskHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get riskHigh;

  /// No description provided for @autoSpeakReplies.
  ///
  /// In en, this message translates to:
  /// **'Auto-play agent replies'**
  String get autoSpeakReplies;

  /// No description provided for @autoSpeakRepliesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start playback automatically after the AI reply finishes'**
  String get autoSpeakRepliesSubtitle;

  /// No description provided for @speechPlaybackPrompt.
  ///
  /// In en, this message translates to:
  /// **'Optimize replies for speech playback'**
  String get speechPlaybackPrompt;

  /// No description provided for @speechPlaybackPromptSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When a reply will be spoken aloud, ask the agent to avoid hard-to-read-aloud content unless you explicitly request it.'**
  String get speechPlaybackPromptSubtitle;

  /// No description provided for @compressReplies.
  ///
  /// In en, this message translates to:
  /// **'Compress AI replies'**
  String get compressReplies;

  /// No description provided for @compressRepliesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When enabled, new sessions ask the AI to summarize what it did briefly'**
  String get compressRepliesSubtitle;

  /// No description provided for @compressReplyMaxChars.
  ///
  /// In en, this message translates to:
  /// **'Compressed reply max chars'**
  String get compressReplyMaxChars;

  /// No description provided for @settingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved'**
  String get settingsSaved;

  /// No description provided for @settingsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save settings: {error}'**
  String settingsSaveFailed(Object error);

  /// No description provided for @alreadyLatestVersion.
  ///
  /// In en, this message translates to:
  /// **'Already up to date: {version}'**
  String alreadyLatestVersion(Object version);

  /// No description provided for @newVersionFound.
  ///
  /// In en, this message translates to:
  /// **'New version {versionName}'**
  String newVersionFound(Object versionName);

  /// No description provided for @targetVersionReady.
  ///
  /// In en, this message translates to:
  /// **'Version {versionName} is ready'**
  String targetVersionReady(Object versionName);

  /// No description provided for @targetVersionNotFound.
  ///
  /// In en, this message translates to:
  /// **'Version {version} could not be found or downloaded'**
  String targetVersionNotFound(Object version);

  /// No description provided for @targetVersionDowngradeWarning.
  ///
  /// In en, this message translates to:
  /// **'If this is an older version than the one currently installed, Android may block the install as a downgrade.'**
  String get targetVersionDowngradeWarning;

  /// No description provided for @currentVersion.
  ///
  /// In en, this message translates to:
  /// **'Current version: {version}'**
  String currentVersion(Object version);

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @updateNow.
  ///
  /// In en, this message translates to:
  /// **'Update now'**
  String get updateNow;

  /// No description provided for @downloadingUpdate.
  ///
  /// In en, this message translates to:
  /// **'Downloading update'**
  String get downloadingUpdate;

  /// No description provided for @downloadedBytes.
  ///
  /// In en, this message translates to:
  /// **'Downloaded {received}'**
  String downloadedBytes(Object received);

  /// No description provided for @downloadProgress.
  ///
  /// In en, this message translates to:
  /// **'{received} / {total}'**
  String downloadProgress(Object received, Object total);

  /// No description provided for @homeManageByProject.
  ///
  /// In en, this message translates to:
  /// **'Manage Codex by project'**
  String get homeManageByProject;

  /// No description provided for @homeBridgeAddress.
  ///
  /// In en, this message translates to:
  /// **'Current Bridge: {address}'**
  String homeBridgeAddress(Object address);

  /// No description provided for @homeIntro.
  ///
  /// In en, this message translates to:
  /// **'Open a project first, then choose an existing session or start a new Codex session under that project.'**
  String get homeIntro;

  /// No description provided for @projectsTitle.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get projectsTitle;

  /// No description provided for @selectProject.
  ///
  /// In en, this message translates to:
  /// **'Select project'**
  String get selectProject;

  /// No description provided for @createProject.
  ///
  /// In en, this message translates to:
  /// **'Create project'**
  String get createProject;

  /// No description provided for @createNewProject.
  ///
  /// In en, this message translates to:
  /// **'Create new project'**
  String get createNewProject;

  /// No description provided for @newProject.
  ///
  /// In en, this message translates to:
  /// **'New project'**
  String get newProject;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @editMessage.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editMessage;

  /// No description provided for @withdrawMessage.
  ///
  /// In en, this message translates to:
  /// **'Withdraw'**
  String get withdrawMessage;

  /// No description provided for @projectCount.
  ///
  /// In en, this message translates to:
  /// **'{count} sessions'**
  String projectCount(int count);

  /// No description provided for @sessionCount.
  ///
  /// In en, this message translates to:
  /// **'{count} sessions'**
  String sessionCount(int count);

  /// No description provided for @projectsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} projects'**
  String projectsCount(int count);

  /// No description provided for @projectUpdatedAt.
  ///
  /// In en, this message translates to:
  /// **'Updated {time}'**
  String projectUpdatedAt(Object time);

  /// No description provided for @loadProjectsFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load projects: {error}'**
  String loadProjectsFailed(Object error);

  /// No description provided for @noProjectsYet.
  ///
  /// In en, this message translates to:
  /// **'No projects yet'**
  String get noProjectsYet;

  /// No description provided for @noProjectsHelp.
  ///
  /// In en, this message translates to:
  /// **'Create a project first, fill in the local code directory, then start or resume a Codex session inside it.'**
  String get noProjectsHelp;

  /// No description provided for @projectName.
  ///
  /// In en, this message translates to:
  /// **'Project name'**
  String get projectName;

  /// No description provided for @localPath.
  ///
  /// In en, this message translates to:
  /// **'Local directory path'**
  String get localPath;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @projectIntro.
  ///
  /// In en, this message translates to:
  /// **'Open any session to continue the existing context, or create a new Codex session under this project.'**
  String get projectIntro;

  /// No description provided for @homePrompt.
  ///
  /// In en, this message translates to:
  /// **'Remote agent cockpit'**
  String get homePrompt;

  /// No description provided for @homeCreateProjectHint.
  ///
  /// In en, this message translates to:
  /// **'Add local codebase'**
  String get homeCreateProjectHint;

  /// No description provided for @homeBrowseProjects.
  ///
  /// In en, this message translates to:
  /// **'Browse all'**
  String get homeBrowseProjects;

  /// No description provided for @searchSessions.
  ///
  /// In en, this message translates to:
  /// **'Search session title or summary'**
  String get searchSessions;

  /// No description provided for @searchProjects.
  ///
  /// In en, this message translates to:
  /// **'Search project name or path'**
  String get searchProjects;

  /// No description provided for @noSearchResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'No matches found'**
  String get noSearchResultsTitle;

  /// No description provided for @noSearchResultsBody.
  ///
  /// In en, this message translates to:
  /// **'Try a different project name, path, session title, or summary.'**
  String get noSearchResultsBody;

  /// No description provided for @themeSection.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeSection;

  /// No description provided for @themeFollowSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get themeFollowSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @sessionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get sessionsTitle;

  /// No description provided for @recentSessionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent sessions'**
  String get recentSessionsTitle;

  /// No description provided for @loadSessionsFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load sessions: {error}'**
  String loadSessionsFailed(Object error);

  /// No description provided for @sessionUpdatedAtWithAgent.
  ///
  /// In en, this message translates to:
  /// **'{agent} · Updated {time}'**
  String sessionUpdatedAtWithAgent(Object agent, Object time);

  /// No description provided for @forkedFromSession.
  ///
  /// In en, this message translates to:
  /// **'Forked from {source}'**
  String forkedFromSession(Object source);

  /// No description provided for @loadMoreSessions.
  ///
  /// In en, this message translates to:
  /// **'Load more ({count})'**
  String loadMoreSessions(int count);

  /// Label for loading more recent sessions without showing a count.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMoreSessionsLabel;

  /// No description provided for @newSession.
  ///
  /// In en, this message translates to:
  /// **'New session'**
  String get newSession;

  /// No description provided for @sessionStatusIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get sessionStatusIdle;

  /// No description provided for @sessionStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get sessionStatusRunning;

  /// No description provided for @sessionStatusAwaitingApproval.
  ///
  /// In en, this message translates to:
  /// **'Awaiting approval'**
  String get sessionStatusAwaitingApproval;

  /// No description provided for @sessionStatusInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Interrupted'**
  String get sessionStatusInterrupted;

  /// No description provided for @sessionStatusWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get sessionStatusWaiting;

  /// No description provided for @sessionStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get sessionStatusFailed;

  /// No description provided for @noSessionsYet.
  ///
  /// In en, this message translates to:
  /// **'No sessions in this project yet'**
  String get noSessionsYet;

  /// No description provided for @noSessionsHelp.
  ///
  /// In en, this message translates to:
  /// **'After starting a Codex session, you can return to this project and reopen the same conversation later.'**
  String get noSessionsHelp;

  /// No description provided for @noSessionsMatched.
  ///
  /// In en, this message translates to:
  /// **'No matching sessions. Try a different keyword.'**
  String get noSessionsMatched;

  /// No description provided for @sessionTitleOptional.
  ///
  /// In en, this message translates to:
  /// **'Session title (optional)'**
  String get sessionTitleOptional;

  /// No description provided for @agentLabel.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get agentLabel;

  /// No description provided for @agentInstalledStatus.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get agentInstalledStatus;

  /// No description provided for @agentNotInstalledStatus.
  ///
  /// In en, this message translates to:
  /// **'Not installed'**
  String get agentNotInstalledStatus;

  /// No description provided for @installAgent.
  ///
  /// In en, this message translates to:
  /// **'Install agent'**
  String get installAgent;

  /// No description provided for @installingAgent.
  ///
  /// In en, this message translates to:
  /// **'Installing...'**
  String get installingAgent;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @creatingSession.
  ///
  /// In en, this message translates to:
  /// **'Creating session...'**
  String get creatingSession;

  /// No description provided for @waitingApprovalProcessing.
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval processing...'**
  String get waitingApprovalProcessing;

  /// No description provided for @waitingApprovalListening.
  ///
  /// In en, this message translates to:
  /// **'Listening for approval...'**
  String get waitingApprovalListening;

  /// No description provided for @connectHeader.
  ///
  /// In en, this message translates to:
  /// **'Connect Bridge'**
  String get connectHeader;

  /// No description provided for @connectPrompt.
  ///
  /// In en, this message translates to:
  /// **'Connect your Bridge to get started.'**
  String get connectPrompt;

  /// No description provided for @connectWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Omni Code'**
  String get connectWelcomeTitle;

  /// No description provided for @connectWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Run the Bridge service on your computer, then authorize this device to open projects and continue sessions.'**
  String get connectWelcomeBody;

  /// No description provided for @connectBridgeHint.
  ///
  /// In en, this message translates to:
  /// **'Use your computer IP if the phone is on the same LAN.'**
  String get connectBridgeHint;

  /// No description provided for @connectDownloadTitle.
  ///
  /// In en, this message translates to:
  /// **'Download Bridge service'**
  String get connectDownloadTitle;

  /// No description provided for @connectDownloadBody.
  ///
  /// In en, this message translates to:
  /// **'Get the service from GitHub on the computer that hosts your local projects.'**
  String get connectDownloadBody;

  /// No description provided for @connectDownloadRepo.
  ///
  /// In en, this message translates to:
  /// **'github.com/omni-stream-ai/omni-code-bridge'**
  String get connectDownloadRepo;

  /// No description provided for @authorizeThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Authorize this device'**
  String get authorizeThisDevice;

  /// No description provided for @connectNextStep.
  ///
  /// In en, this message translates to:
  /// **'Next: approval screen'**
  String get connectNextStep;

  /// No description provided for @backToWelcome.
  ///
  /// In en, this message translates to:
  /// **'Back to welcome'**
  String get backToWelcome;

  /// No description provided for @waitingApprovalHeader.
  ///
  /// In en, this message translates to:
  /// **'Authorization'**
  String get waitingApprovalHeader;

  /// No description provided for @waitingApprovalHeaderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Approve this device on your Bridge host.'**
  String get waitingApprovalHeaderSubtitle;

  /// No description provided for @turnPausedWaiting.
  ///
  /// In en, this message translates to:
  /// **'This turn is paused and waiting for follow-up results...'**
  String get turnPausedWaiting;

  /// No description provided for @speechReadyStatus.
  ///
  /// In en, this message translates to:
  /// **'Voice transcription ready'**
  String get speechReadyStatus;

  /// No description provided for @waitingProcessApproval.
  ///
  /// In en, this message translates to:
  /// **'Waiting to process approval...'**
  String get waitingProcessApproval;

  /// No description provided for @stopReply.
  ///
  /// In en, this message translates to:
  /// **'Stop reply'**
  String get stopReply;

  /// No description provided for @messageInputHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a task, for example: Help me inspect why the latest build failed'**
  String get messageInputHint;

  /// No description provided for @stopVoice.
  ///
  /// In en, this message translates to:
  /// **'Stop voice'**
  String get stopVoice;

  /// No description provided for @voiceInput.
  ///
  /// In en, this message translates to:
  /// **'Voice input'**
  String get voiceInput;

  /// No description provided for @keyboardInput.
  ///
  /// In en, this message translates to:
  /// **'Keyboard input'**
  String get keyboardInput;

  /// No description provided for @voiceHoldToTalk.
  ///
  /// In en, this message translates to:
  /// **'Hold to talk'**
  String get voiceHoldToTalk;

  /// No description provided for @voiceHoldRecording.
  ///
  /// In en, this message translates to:
  /// **'Listening...'**
  String get voiceHoldRecording;

  /// No description provided for @voiceHoldSlideUpHint.
  ///
  /// In en, this message translates to:
  /// **'Slide up for text or cancel'**
  String get voiceHoldSlideUpHint;

  /// No description provided for @voiceHoldReleaseHint.
  ///
  /// In en, this message translates to:
  /// **'Release left for text, right to cancel'**
  String get voiceHoldReleaseHint;

  /// No description provided for @voiceHoldReleaseToText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get voiceHoldReleaseToText;

  /// No description provided for @voiceHoldReleaseCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get voiceHoldReleaseCancel;

  /// No description provided for @voiceChatTitle.
  ///
  /// In en, this message translates to:
  /// **'Voice chat'**
  String get voiceChatTitle;

  /// No description provided for @callModeListening.
  ///
  /// In en, this message translates to:
  /// **'Go ahead, I\'m listening'**
  String get callModeListening;

  /// No description provided for @callModePreparingListening.
  ///
  /// In en, this message translates to:
  /// **'Preparing microphone'**
  String get callModePreparingListening;

  /// No description provided for @callModeSpeaking.
  ///
  /// In en, this message translates to:
  /// **'Replying out loud'**
  String get callModeSpeaking;

  /// No description provided for @callModeWorking.
  ///
  /// In en, this message translates to:
  /// **'Thinking through your request'**
  String get callModeWorking;

  /// No description provided for @callModeIdleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Speak naturally. I will listen, send, and read the reply back.'**
  String get callModeIdleSubtitle;

  /// No description provided for @callModePreparingListeningLabel.
  ///
  /// In en, this message translates to:
  /// **'Preparing to listen'**
  String get callModePreparingListeningLabel;

  /// No description provided for @callModePreparingListeningDetail.
  ///
  /// In en, this message translates to:
  /// **'Microphone and speech recognition are starting. Speech may not be captured yet.'**
  String get callModePreparingListeningDetail;

  /// No description provided for @callModeListeningReadyLabel.
  ///
  /// In en, this message translates to:
  /// **'Listening now'**
  String get callModeListeningReadyLabel;

  /// No description provided for @callModeListeningReadyDetail.
  ///
  /// In en, this message translates to:
  /// **'Start speaking whenever you\'re ready. Live transcription will show up here.'**
  String get callModeListeningReadyDetail;

  /// No description provided for @callModeWaitingWakeWordLabel.
  ///
  /// In en, this message translates to:
  /// **'Waiting for wake word'**
  String get callModeWaitingWakeWordLabel;

  /// No description provided for @callModeWaitingWakeWordDetail.
  ///
  /// In en, this message translates to:
  /// **'Put the configured wake word at the start or end of the utterance. Middle matches are ignored.'**
  String get callModeWaitingWakeWordDetail;

  /// No description provided for @callModeWakeWordDetectedLabel.
  ///
  /// In en, this message translates to:
  /// **'Wake word detected'**
  String get callModeWakeWordDetectedLabel;

  /// No description provided for @callModeWakeWordDetectedDetail.
  ///
  /// In en, this message translates to:
  /// **'I am listening. The next utterance will be captured and sent.'**
  String get callModeWakeWordDetectedDetail;

  /// No description provided for @callModeWakeWordAck.
  ///
  /// In en, this message translates to:
  /// **'I am listening'**
  String get callModeWakeWordAck;

  /// No description provided for @callModeCommandAccepted.
  ///
  /// In en, this message translates to:
  /// **'Let me think'**
  String get callModeCommandAccepted;

  /// No description provided for @callModeRejectedSpeakerTranscript.
  ///
  /// In en, this message translates to:
  /// **'{transcript} (not selected speaker)'**
  String callModeRejectedSpeakerTranscript(String transcript);

  /// No description provided for @callModeRejectedWakeWordTranscript.
  ///
  /// In en, this message translates to:
  /// **'{transcript} (wake word not matched)'**
  String callModeRejectedWakeWordTranscript(String transcript);

  /// No description provided for @callModeSpeechDetectedLabel.
  ///
  /// In en, this message translates to:
  /// **'Speech detected'**
  String get callModeSpeechDetectedLabel;

  /// No description provided for @callModeSpeechDetectedDetail.
  ///
  /// In en, this message translates to:
  /// **'Keep talking naturally. The current utterance is still being captured.'**
  String get callModeSpeechDetectedDetail;

  /// No description provided for @callModeWaitingForPauseLabel.
  ///
  /// In en, this message translates to:
  /// **'Waiting for you to finish'**
  String get callModeWaitingForPauseLabel;

  /// No description provided for @callModeWaitingForPauseDetail.
  ///
  /// In en, this message translates to:
  /// **'After a short pause, this utterance will be sent automatically.'**
  String get callModeWaitingForPauseDetail;

  /// No description provided for @callModeOpenChatHistory.
  ///
  /// In en, this message translates to:
  /// **'Open chat history'**
  String get callModeOpenChatHistory;

  /// No description provided for @showCallModeSubtitles.
  ///
  /// In en, this message translates to:
  /// **'Show subtitles'**
  String get showCallModeSubtitles;

  /// No description provided for @hideCallModeSubtitles.
  ///
  /// In en, this message translates to:
  /// **'Hide subtitles'**
  String get hideCallModeSubtitles;

  /// No description provided for @startCallMode.
  ///
  /// In en, this message translates to:
  /// **'Start call mode'**
  String get startCallMode;

  /// No description provided for @stopCallMode.
  ///
  /// In en, this message translates to:
  /// **'Stop call mode'**
  String get stopCallMode;

  /// No description provided for @callModeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Call mode is unavailable until speech services finish initializing.'**
  String get callModeUnavailable;

  /// No description provided for @callModeRequiresStreamingAsr.
  ///
  /// In en, this message translates to:
  /// **'Call mode requires Omni Bridge Local or a realtime ASR plugin.'**
  String get callModeRequiresStreamingAsr;

  /// No description provided for @callModeSection.
  ///
  /// In en, this message translates to:
  /// **'Call mode'**
  String get callModeSection;

  /// No description provided for @callModeAllowInterruptionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Allow speaking over replies'**
  String get callModeAllowInterruptionsLabel;

  /// No description provided for @callModeAllowInterruptionsHelp.
  ///
  /// In en, this message translates to:
  /// **'When enabled, speaking again during call mode will stop the current spoken reply and take over the turn.'**
  String get callModeAllowInterruptionsHelp;

  /// No description provided for @callModeSpeechPauseLabel.
  ///
  /// In en, this message translates to:
  /// **'Speech pause detection'**
  String get callModeSpeechPauseLabel;

  /// No description provided for @callModeSpeechPauseHelp.
  ///
  /// In en, this message translates to:
  /// **'How many milliseconds of silence to wait before sending the current utterance. Recommended range: 600-2400 ms.'**
  String get callModeSpeechPauseHelp;

  /// No description provided for @callModeSpeechPauseRangeError.
  ///
  /// In en, this message translates to:
  /// **'Enter a value from {min} to {max} ms.'**
  String callModeSpeechPauseRangeError(int min, int max);

  /// No description provided for @callModeSpeechPauseBridgeOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'This pause setting currently applies precisely to Omni Bridge Local realtime call mode. Other ASR providers may keep their own built-in pause behavior.'**
  String get callModeSpeechPauseBridgeOnlyHint;

  /// No description provided for @callModeWakeWordLabel.
  ///
  /// In en, this message translates to:
  /// **'Require wake word'**
  String get callModeWakeWordLabel;

  /// No description provided for @callModeWakeWordHelp.
  ///
  /// In en, this message translates to:
  /// **'When enabled, Omni Bridge Local uses its local keyword detector before accepting realtime speech. Unsupported phrases are rejected with a setup error.'**
  String get callModeWakeWordHelp;

  /// No description provided for @callModeWakeWordsLabel.
  ///
  /// In en, this message translates to:
  /// **'Wake words'**
  String get callModeWakeWordsLabel;

  /// No description provided for @callModeWakeWordsHelp.
  ///
  /// In en, this message translates to:
  /// **'Separate multiple phrases with commas. English phrases and numbered pinyin such as ou1 mi3 are converted to model tokens. Direct Chinese characters are not supported.'**
  String get callModeWakeWordsHelp;

  /// No description provided for @callModeWakeWordsEmptyError.
  ///
  /// In en, this message translates to:
  /// **'Enter at least one wake word.'**
  String get callModeWakeWordsEmptyError;

  /// No description provided for @callModeWakeWordsUnsupportedError.
  ///
  /// In en, this message translates to:
  /// **'\"{wakeWord}\" is not supported by the local wake-word model. Use an English phrase, numbered pinyin, or model token sequence such as \"{example}\".'**
  String callModeWakeWordsUnsupportedError(String wakeWord, String example);

  /// No description provided for @callModeWakeWordModelUnsupported.
  ///
  /// In en, this message translates to:
  /// **'The current speech model does not support wake words. Wake word detection has been automatically disabled.'**
  String get callModeWakeWordModelUnsupported;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @imageAttachment.
  ///
  /// In en, this message translates to:
  /// **'Upload file or image'**
  String get imageAttachment;

  /// No description provided for @previewImage.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get previewImage;

  /// No description provided for @imagePreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Image preview'**
  String get imagePreviewTitle;

  /// No description provided for @imagePreviewLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load image preview'**
  String get imagePreviewLoadFailed;

  /// No description provided for @imagePreviewBgDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get imagePreviewBgDark;

  /// No description provided for @imagePreviewBgLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get imagePreviewBgLight;

  /// No description provided for @imagePreviewBgChecker.
  ///
  /// In en, this message translates to:
  /// **'Checker'**
  String get imagePreviewBgChecker;

  /// No description provided for @agentAwaitingPermission.
  ///
  /// In en, this message translates to:
  /// **'{agent} is waiting for permission'**
  String agentAwaitingPermission(Object agent);

  /// No description provided for @desktopOnlyApproval.
  ///
  /// In en, this message translates to:
  /// **'This request can currently only be handled on desktop.'**
  String get desktopOnlyApproval;

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approve;

  /// No description provided for @approveForSession.
  ///
  /// In en, this message translates to:
  /// **'Allow for this session'**
  String get approveForSession;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @processing.
  ///
  /// In en, this message translates to:
  /// **'Processing...'**
  String get processing;

  /// No description provided for @toolActivity.
  ///
  /// In en, this message translates to:
  /// **'Tool activity'**
  String get toolActivity;

  /// No description provided for @working.
  ///
  /// In en, this message translates to:
  /// **'Working...'**
  String get working;

  /// No description provided for @stopPlayback.
  ///
  /// In en, this message translates to:
  /// **'Stop playback'**
  String get stopPlayback;

  /// No description provided for @playback.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get playback;

  /// No description provided for @createSessionFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create session: {error}'**
  String createSessionFailed(Object error);

  /// No description provided for @loadMessagesFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load messages: {error}'**
  String loadMessagesFailed(Object error);

  /// No description provided for @restoreSessionFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to restore session: {error}'**
  String restoreSessionFailed(Object error);

  /// No description provided for @approvalSubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to submit approval: {error}'**
  String approvalSubmitFailed(Object error);

  /// No description provided for @approvalAccepted.
  ///
  /// In en, this message translates to:
  /// **'Approval granted'**
  String get approvalAccepted;

  /// No description provided for @approvalAcceptedForSession.
  ///
  /// In en, this message translates to:
  /// **'Similar future requests are allowed in this session'**
  String get approvalAcceptedForSession;

  /// No description provided for @approvalAlwaysAllow.
  ///
  /// In en, this message translates to:
  /// **'This kind of request is always allowed'**
  String get approvalAlwaysAllow;

  /// No description provided for @approvalRejected.
  ///
  /// In en, this message translates to:
  /// **'Approval rejected'**
  String get approvalRejected;

  /// No description provided for @approvalCancelled.
  ///
  /// In en, this message translates to:
  /// **'Approval cancelled'**
  String get approvalCancelled;

  /// No description provided for @microphonePermissionMissing.
  ///
  /// In en, this message translates to:
  /// **'This device does not have microphone permission'**
  String get microphonePermissionMissing;

  /// No description provided for @recordingInitFailed.
  ///
  /// In en, this message translates to:
  /// **'Recording init timed out or failed: {error}'**
  String recordingInitFailed(Object error);

  /// No description provided for @ttsFailed.
  ///
  /// In en, this message translates to:
  /// **'TTS failed: {error}'**
  String ttsFailed(Object error);

  /// No description provided for @ttsInitFailed.
  ///
  /// In en, this message translates to:
  /// **'TTS init timed out or failed: {error}'**
  String ttsInitFailed(Object error);

  /// No description provided for @reinitializingRecording.
  ///
  /// In en, this message translates to:
  /// **'Reinitializing recording...'**
  String get reinitializingRecording;

  /// No description provided for @recordingInProgress.
  ///
  /// In en, this message translates to:
  /// **'Recording. Tap once to stop and transcribe...'**
  String get recordingInProgress;

  /// No description provided for @startRecordingFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to start recording: {error}'**
  String startRecordingFailed(Object error);

  /// No description provided for @stopRecordingFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to stop recording: {error}'**
  String stopRecordingFailed(Object error);

  /// No description provided for @uploadingAudio.
  ///
  /// In en, this message translates to:
  /// **'Uploading audio and transcribing...'**
  String get uploadingAudio;

  /// No description provided for @recordingFileMissing.
  ///
  /// In en, this message translates to:
  /// **'No recording file was produced'**
  String get recordingFileMissing;

  /// No description provided for @voiceTranscriptionComplete.
  ///
  /// In en, this message translates to:
  /// **'Voice transcription complete'**
  String get voiceTranscriptionComplete;

  /// No description provided for @voiceTranscriptionFailed.
  ///
  /// In en, this message translates to:
  /// **'Voice transcription failed: {error}'**
  String voiceTranscriptionFailed(Object error);

  /// No description provided for @reinitializingTts.
  ///
  /// In en, this message translates to:
  /// **'Reinitializing TTS...'**
  String get reinitializingTts;

  /// No description provided for @requestingTts.
  ///
  /// In en, this message translates to:
  /// **'Requesting TTS playback...'**
  String get requestingTts;

  /// No description provided for @ttsPlaybackFailed.
  ///
  /// In en, this message translates to:
  /// **'TTS playback failed: {error}'**
  String ttsPlaybackFailed(Object error);

  /// No description provided for @sessionStillCreating.
  ///
  /// In en, this message translates to:
  /// **'The session is still being created. Please wait.'**
  String get sessionStillCreating;

  /// No description provided for @sessionStillRunning.
  ///
  /// In en, this message translates to:
  /// **'This session is still processing. Wait for this turn to finish before sending again.'**
  String get sessionStillRunning;

  /// No description provided for @messageInputRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter text or use voice recognition first'**
  String get messageInputRequired;

  /// No description provided for @sendFailed.
  ///
  /// In en, this message translates to:
  /// **'Send failed: {error}'**
  String sendFailed(Object error);

  /// No description provided for @replyStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped this reply'**
  String get replyStopped;

  /// No description provided for @allToolActivity.
  ///
  /// In en, this message translates to:
  /// **'All tool activity'**
  String get allToolActivity;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @toolActivityDetail.
  ///
  /// In en, this message translates to:
  /// **'Tool activity detail'**
  String get toolActivityDetail;

  /// No description provided for @detailType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get detailType;

  /// No description provided for @detailPhase.
  ///
  /// In en, this message translates to:
  /// **'Phase'**
  String get detailPhase;

  /// No description provided for @detailContent.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get detailContent;

  /// No description provided for @detailItems.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get detailItems;

  /// No description provided for @detailExtra.
  ///
  /// In en, this message translates to:
  /// **'Extra'**
  String get detailExtra;

  /// No description provided for @detailRawContent.
  ///
  /// In en, this message translates to:
  /// **'Raw content'**
  String get detailRawContent;

  /// No description provided for @toolKindCommand.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get toolKindCommand;

  /// No description provided for @toolKindFile.
  ///
  /// In en, this message translates to:
  /// **'File change'**
  String get toolKindFile;

  /// No description provided for @toolKindTodo.
  ///
  /// In en, this message translates to:
  /// **'Todo'**
  String get toolKindTodo;

  /// No description provided for @toolKindPlan.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get toolKindPlan;

  /// No description provided for @toolKindSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get toolKindSearch;

  /// No description provided for @toolKindFetch.
  ///
  /// In en, this message translates to:
  /// **'Fetch'**
  String get toolKindFetch;

  /// No description provided for @toolKindReasoning.
  ///
  /// In en, this message translates to:
  /// **'Reasoning'**
  String get toolKindReasoning;

  /// No description provided for @toolKindThread.
  ///
  /// In en, this message translates to:
  /// **'Thread status'**
  String get toolKindThread;

  /// No description provided for @toolKindTurn.
  ///
  /// In en, this message translates to:
  /// **'Turn status'**
  String get toolKindTurn;

  /// No description provided for @toolKindApproval.
  ///
  /// In en, this message translates to:
  /// **'Approval'**
  String get toolKindApproval;

  /// No description provided for @toolKindDebug.
  ///
  /// In en, this message translates to:
  /// **'Debug event'**
  String get toolKindDebug;

  /// No description provided for @toolPrimaryCommand.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get toolPrimaryCommand;

  /// No description provided for @toolSecondaryResult.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get toolSecondaryResult;

  /// No description provided for @toolExitCode.
  ///
  /// In en, this message translates to:
  /// **'Exit code {code}'**
  String toolExitCode(Object code);

  /// No description provided for @toolPrimaryFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get toolPrimaryFile;

  /// No description provided for @toolSecondaryOtherFiles.
  ///
  /// In en, this message translates to:
  /// **'Other files'**
  String get toolSecondaryOtherFiles;

  /// No description provided for @toolMoreFiles.
  ///
  /// In en, this message translates to:
  /// **'{count} more files not expanded'**
  String toolMoreFiles(Object count);

  /// No description provided for @toolPrimaryTodoItems.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get toolPrimaryTodoItems;

  /// No description provided for @toolSecondaryOtherItems.
  ///
  /// In en, this message translates to:
  /// **'Other items'**
  String get toolSecondaryOtherItems;

  /// No description provided for @toolPrimarySteps.
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get toolPrimarySteps;

  /// No description provided for @toolSecondaryOtherSteps.
  ///
  /// In en, this message translates to:
  /// **'Other steps'**
  String get toolSecondaryOtherSteps;

  /// No description provided for @toolPrimaryIdentifier.
  ///
  /// In en, this message translates to:
  /// **'Identifier'**
  String get toolPrimaryIdentifier;

  /// No description provided for @toolSecondaryDetail.
  ///
  /// In en, this message translates to:
  /// **'Detail'**
  String get toolSecondaryDetail;

  /// No description provided for @phaseRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get phaseRunning;

  /// No description provided for @phaseCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get phaseCompleted;

  /// No description provided for @phaseStarted.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get phaseStarted;

  /// No description provided for @draftPending.
  ///
  /// In en, this message translates to:
  /// **'Pending sync'**
  String get draftPending;

  /// No description provided for @draftFailed.
  ///
  /// In en, this message translates to:
  /// **'Send failed, tap to retry'**
  String get draftFailed;

  /// No description provided for @whisperApiKeyRequired.
  ///
  /// In en, this message translates to:
  /// **'Fill in the Whisper/OpenAI API key in settings first'**
  String get whisperApiKeyRequired;

  /// No description provided for @whisperAsrRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Whisper ASR request failed ({statusCode}): {body}'**
  String whisperAsrRequestFailed(Object statusCode, Object body);

  /// No description provided for @whisperAsrMissingText.
  ///
  /// In en, this message translates to:
  /// **'Whisper ASR response is missing text'**
  String get whisperAsrMissingText;

  /// No description provided for @updateManifestUrlRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the manifest URL first'**
  String get updateManifestUrlRequired;

  /// No description provided for @updateManifestUrlInvalid.
  ///
  /// In en, this message translates to:
  /// **'Manifest URL is invalid'**
  String get updateManifestUrlInvalid;

  /// No description provided for @updateCheckHttpFailed.
  ///
  /// In en, this message translates to:
  /// **'Update check failed: HTTP {statusCode}'**
  String updateCheckHttpFailed(Object statusCode);

  /// No description provided for @updateManifestMustBeJson.
  ///
  /// In en, this message translates to:
  /// **'Update manifest must be a JSON object'**
  String get updateManifestMustBeJson;

  /// No description provided for @updateCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Update check failed: {error}'**
  String updateCheckFailed(Object error);

  /// No description provided for @apkUrlInvalid.
  ///
  /// In en, this message translates to:
  /// **'APK download URL is invalid'**
  String get apkUrlInvalid;

  /// No description provided for @apkDownloadHttpFailed.
  ///
  /// In en, this message translates to:
  /// **'APK download failed: HTTP {statusCode}'**
  String apkDownloadHttpFailed(Object statusCode);

  /// No description provided for @cannotOpenInstaller.
  ///
  /// In en, this message translates to:
  /// **'Unable to open system installer'**
  String get cannotOpenInstaller;

  /// No description provided for @updateManifestMissingVersionName.
  ///
  /// In en, this message translates to:
  /// **'Update manifest is missing version_name'**
  String get updateManifestMissingVersionName;

  /// No description provided for @updateManifestInvalidVersionCode.
  ///
  /// In en, this message translates to:
  /// **'Update manifest version_code is invalid'**
  String get updateManifestInvalidVersionCode;

  /// No description provided for @updateManifestMissingApkUrl.
  ///
  /// In en, this message translates to:
  /// **'Update manifest is missing apk_url or apk_urls'**
  String get updateManifestMissingApkUrl;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @waitingApprovalTitle.
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval'**
  String get waitingApprovalTitle;

  /// No description provided for @waitingApprovalBody.
  ///
  /// In en, this message translates to:
  /// **'Approve this request on the Bridge host. The app continues automatically after approval.'**
  String get waitingApprovalBody;

  /// No description provided for @waitingApprovalInstallHint.
  ///
  /// In en, this message translates to:
  /// **'If the Bridge service is not running yet, download it from GitHub and start it first.'**
  String get waitingApprovalInstallHint;

  /// No description provided for @waitingApprovalDownloadBridge.
  ///
  /// In en, this message translates to:
  /// **'Download Bridge service on GitHub'**
  String get waitingApprovalDownloadBridge;

  /// No description provided for @waitingApprovalRunCommand.
  ///
  /// In en, this message translates to:
  /// **'Run this command on the Bridge host:'**
  String get waitingApprovalRunCommand;

  /// No description provided for @waitingApprovalRequestAgain.
  ///
  /// In en, this message translates to:
  /// **'Request again'**
  String get waitingApprovalRequestAgain;

  /// No description provided for @voiceInputInitFailed.
  ///
  /// In en, this message translates to:
  /// **'Voice input init timed out or failed: {error}'**
  String voiceInputInitFailed(Object error);

  /// No description provided for @startVoiceInputFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to start voice input: {error}'**
  String startVoiceInputFailed(Object error);

  /// No description provided for @stopVoiceInputFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to stop voice input: {error}'**
  String stopVoiceInputFailed(Object error);

  /// No description provided for @voiceInputInProgress.
  ///
  /// In en, this message translates to:
  /// **'Listening. Tap once to stop and transcribe...'**
  String get voiceInputInProgress;

  /// No description provided for @reinitializingVoiceInput.
  ///
  /// In en, this message translates to:
  /// **'Reinitializing voice input...'**
  String get reinitializingVoiceInput;

  /// No description provided for @voiceTranscriptionNoResult.
  ///
  /// In en, this message translates to:
  /// **'No speech was recognized'**
  String get voiceTranscriptionNoResult;

  /// No description provided for @speechSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get speechSystem;

  /// No description provided for @omniBridgeLocal.
  ///
  /// In en, this message translates to:
  /// **'Omni Bridge Local'**
  String get omniBridgeLocal;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @refreshing.
  ///
  /// In en, this message translates to:
  /// **'Refreshing...'**
  String get refreshing;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @speechSystemPreferredHelp.
  ///
  /// In en, this message translates to:
  /// **'System is used by default when available. Switch to cloud providers if you need a fallback.'**
  String get speechSystemPreferredHelp;

  /// No description provided for @systemTtsUnavailableOnLinux.
  ///
  /// In en, this message translates to:
  /// **'Linux system TTS requires speech-dispatcher (spd-say) or espeak-ng. Install one and retry, or switch to a cloud provider.'**
  String get systemTtsUnavailableOnLinux;

  /// No description provided for @systemAsrUnavailableOnLinux.
  ///
  /// In en, this message translates to:
  /// **'System ASR is not available on Linux yet. Choose a cloud provider to enable voice input.'**
  String get systemAsrUnavailableOnLinux;

  /// No description provided for @systemAsrMacosPermissionHint.
  ///
  /// In en, this message translates to:
  /// **'System ASR on macOS requires microphone and speech recognition permissions.'**
  String get systemAsrMacosPermissionHint;

  /// No description provided for @systemSpeechUnavailable.
  ///
  /// In en, this message translates to:
  /// **'System speech is unavailable on this device. Switch providers in Settings to use cloud speech.'**
  String get systemSpeechUnavailable;

  /// No description provided for @localBridgeSpeechSection.
  ///
  /// In en, this message translates to:
  /// **'Local Bridge Speech'**
  String get localBridgeSpeechSection;

  /// No description provided for @localBridgeModelsSection.
  ///
  /// In en, this message translates to:
  /// **'Local Bridge Models'**
  String get localBridgeModelsSection;

  /// No description provided for @localBridgeSpeechIntro.
  ///
  /// In en, this message translates to:
  /// **'Use the local Bridge to run offline ASR, TTS, VAD, and model downloads on your own machine.'**
  String get localBridgeSpeechIntro;

  /// No description provided for @localBridgeModelsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Local Bridge model status has not loaded yet.'**
  String get localBridgeModelsUnavailable;

  /// No description provided for @bridgeDetails.
  ///
  /// In en, this message translates to:
  /// **'Bridge details'**
  String get bridgeDetails;

  /// No description provided for @localBridgeModelRoot.
  ///
  /// In en, this message translates to:
  /// **'Model root'**
  String get localBridgeModelRoot;

  /// No description provided for @localBridgeDownloadTasksSection.
  ///
  /// In en, this message translates to:
  /// **'Download tasks'**
  String get localBridgeDownloadTasksSection;

  /// No description provided for @localBridgeTtsVoiceLabel.
  ///
  /// In en, this message translates to:
  /// **'TTS voice'**
  String get localBridgeTtsVoiceLabel;

  /// No description provided for @localBridgeTtsVoiceField.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get localBridgeTtsVoiceField;

  /// No description provided for @localBridgeTtsVoiceHelp.
  ///
  /// In en, this message translates to:
  /// **'Used for local Bridge reply playback, auto-play, and call mode spoken replies.'**
  String get localBridgeTtsVoiceHelp;

  /// No description provided for @localBridgeTtsStreamingLabel.
  ///
  /// In en, this message translates to:
  /// **'Stream Bridge Local TTS'**
  String get localBridgeTtsStreamingLabel;

  /// No description provided for @localBridgeTtsStreamingHelp.
  ///
  /// In en, this message translates to:
  /// **'Starts playback while the local Bridge is still generating speech. Disable this if you prefer full audio to be generated before playback begins.'**
  String get localBridgeTtsStreamingHelp;

  /// No description provided for @localBridgeTtsVoiceOption.
  ///
  /// In en, this message translates to:
  /// **'Voice {voice}'**
  String localBridgeTtsVoiceOption(Object voice);

  /// No description provided for @localBridgeTtsVoiceDefault.
  ///
  /// In en, this message translates to:
  /// **'Voice {voice} (Default)'**
  String localBridgeTtsVoiceDefault(Object voice);

  /// No description provided for @localBridgeTtsNamedVoiceDefault.
  ///
  /// In en, this message translates to:
  /// **'{voice} (Default)'**
  String localBridgeTtsNamedVoiceDefault(Object voice);

  /// No description provided for @localBridgeTtsVoiceId.
  ///
  /// In en, this message translates to:
  /// **'ID {voice}'**
  String localBridgeTtsVoiceId(Object voice);

  /// No description provided for @speechVoiceLanguageChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get speechVoiceLanguageChinese;

  /// No description provided for @speechVoiceLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get speechVoiceLanguageEnglish;

  /// No description provided for @speechVoiceLanguageChineseEnglish.
  ///
  /// In en, this message translates to:
  /// **'Chinese + English'**
  String get speechVoiceLanguageChineseEnglish;

  /// No description provided for @speechVoiceLanguageJapanese.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get speechVoiceLanguageJapanese;

  /// No description provided for @speechVoiceLanguageSpanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get speechVoiceLanguageSpanish;

  /// No description provided for @speechVoiceLanguageFrench.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get speechVoiceLanguageFrench;

  /// No description provided for @speechVoiceLanguageHindi.
  ///
  /// In en, this message translates to:
  /// **'Hindi'**
  String get speechVoiceLanguageHindi;

  /// No description provided for @speechVoiceLanguageItalian.
  ///
  /// In en, this message translates to:
  /// **'Italian'**
  String get speechVoiceLanguageItalian;

  /// No description provided for @speechVoiceLanguagePortugueseBr.
  ///
  /// In en, this message translates to:
  /// **'Portuguese (BR)'**
  String get speechVoiceLanguagePortugueseBr;

  /// No description provided for @speechVoiceLanguageUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown language'**
  String get speechVoiceLanguageUnknown;

  /// No description provided for @speechVoiceAccentAmericanEnglish.
  ///
  /// In en, this message translates to:
  /// **'American English'**
  String get speechVoiceAccentAmericanEnglish;

  /// No description provided for @speechVoiceAccentBritishEnglish.
  ///
  /// In en, this message translates to:
  /// **'British English'**
  String get speechVoiceAccentBritishEnglish;

  /// No description provided for @speechVoiceAccentBrazilianPortuguese.
  ///
  /// In en, this message translates to:
  /// **'Brazilian Portuguese'**
  String get speechVoiceAccentBrazilianPortuguese;

  /// No description provided for @speechVoiceGenderFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get speechVoiceGenderFemale;

  /// No description provided for @speechVoiceGenderMale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get speechVoiceGenderMale;

  /// No description provided for @bridgeLocalTtsHelp.
  ///
  /// In en, this message translates to:
  /// **'Uses the bridge-local /v1/audio/speech endpoint and the selected TTS model below.'**
  String get bridgeLocalTtsHelp;

  /// No description provided for @bridgeLocalAsrHelp.
  ///
  /// In en, this message translates to:
  /// **'Uses the bridge-local /v1/audio/transcriptions endpoint for recorded voice input.'**
  String get bridgeLocalAsrHelp;

  /// No description provided for @speechNotSelected.
  ///
  /// In en, this message translates to:
  /// **'Not selected'**
  String get speechNotSelected;

  /// No description provided for @speechInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get speechInstalled;

  /// No description provided for @speechNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Not installed'**
  String get speechNotInstalled;

  /// No description provided for @speechDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get speechDownload;

  /// No description provided for @speechDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading...'**
  String get speechDownloading;

  /// No description provided for @speechDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get speechDelete;

  /// No description provided for @speechInstalledModels.
  ///
  /// In en, this message translates to:
  /// **'Installed models'**
  String get speechInstalledModels;

  /// No description provided for @speechNoInstalledModels.
  ///
  /// In en, this message translates to:
  /// **'No installed models yet.'**
  String get speechNoInstalledModels;

  /// No description provided for @speechModelKindAsr.
  ///
  /// In en, this message translates to:
  /// **'ASR'**
  String get speechModelKindAsr;

  /// No description provided for @speechModelKindTts.
  ///
  /// In en, this message translates to:
  /// **'TTS'**
  String get speechModelKindTts;

  /// No description provided for @speechModelKindVad.
  ///
  /// In en, this message translates to:
  /// **'VAD'**
  String get speechModelKindVad;

  /// No description provided for @speechRuntimeStreaming.
  ///
  /// In en, this message translates to:
  /// **'Streaming'**
  String get speechRuntimeStreaming;

  /// No description provided for @speechRuntimeOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get speechRuntimeOffline;

  /// No description provided for @speechProfileBatchAsrTitle.
  ///
  /// In en, this message translates to:
  /// **'Batch ASR'**
  String get speechProfileBatchAsrTitle;

  /// No description provided for @speechProfileRealtimeAsrTitle.
  ///
  /// In en, this message translates to:
  /// **'Realtime ASR'**
  String get speechProfileRealtimeAsrTitle;

  /// No description provided for @speechProfileTtsTitle.
  ///
  /// In en, this message translates to:
  /// **'TTS'**
  String get speechProfileTtsTitle;

  /// No description provided for @speechDownloadStatusQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get speechDownloadStatusQueued;

  /// No description provided for @speechDownloadStatusDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get speechDownloadStatusDownloading;

  /// No description provided for @speechDownloadStatusExtracting.
  ///
  /// In en, this message translates to:
  /// **'Extracting'**
  String get speechDownloadStatusExtracting;

  /// No description provided for @speechDownloadStatusVerifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying'**
  String get speechDownloadStatusVerifying;

  /// No description provided for @speechDownloadStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get speechDownloadStatusCompleted;

  /// No description provided for @speechDownloadStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get speechDownloadStatusFailed;

  /// No description provided for @speechActiveDownloadsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 active download} other{{count} active downloads}}'**
  String speechActiveDownloadsCount(int count);

  /// No description provided for @speechDownloadProgressPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}% complete'**
  String speechDownloadProgressPercent(int percent);

  /// No description provided for @speechLocalModelsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load local speech models: {error}'**
  String speechLocalModelsLoadFailed(Object error);

  /// No description provided for @speechModelDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed for {modelId}: {error}'**
  String speechModelDownloadFailed(Object modelId, Object error);

  /// No description provided for @appDownloadSection.
  ///
  /// In en, this message translates to:
  /// **'App Download'**
  String get appDownloadSection;

  /// No description provided for @appDownloadHelp.
  ///
  /// In en, this message translates to:
  /// **'Download the latest release from GitHub.'**
  String get appDownloadHelp;

  /// No description provided for @openGithubReleases.
  ///
  /// In en, this message translates to:
  /// **'Open GitHub Releases'**
  String get openGithubReleases;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @signOutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out and reauthorize?'**
  String get signOutConfirmTitle;

  /// No description provided for @signOutConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This clears the current device authorization and returns you to the welcome screen. You will need to reconnect Bridge and authorize this device again.'**
  String get signOutConfirmBody;

  /// No description provided for @sessionFailedGeneric.
  ///
  /// In en, this message translates to:
  /// **'Session failed'**
  String get sessionFailedGeneric;

  /// No description provided for @modelProvidersSection.
  ///
  /// In en, this message translates to:
  /// **'MODEL PROVIDERS'**
  String get modelProvidersSection;

  /// No description provided for @modelProvidersHelp.
  ///
  /// In en, this message translates to:
  /// **'Configure LLM providers for agents'**
  String get modelProvidersHelp;

  /// No description provided for @addProvider.
  ///
  /// In en, this message translates to:
  /// **'Add Provider'**
  String get addProvider;

  /// No description provided for @editProvider.
  ///
  /// In en, this message translates to:
  /// **'Edit Provider'**
  String get editProvider;

  /// No description provided for @deleteProvider.
  ///
  /// In en, this message translates to:
  /// **'Delete Provider'**
  String get deleteProvider;

  /// No description provided for @providerName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get providerName;

  /// No description provided for @providerNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. My OpenAI'**
  String get providerNameHint;

  /// No description provided for @providerBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get providerBaseUrl;

  /// No description provided for @providerBaseUrlHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. https://api.openai.com/v1'**
  String get providerBaseUrlHint;

  /// No description provided for @providerApiKey.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get providerApiKey;

  /// No description provided for @providerModel.
  ///
  /// In en, this message translates to:
  /// **'Model (optional)'**
  String get providerModel;

  /// No description provided for @providerModelHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty for default'**
  String get providerModelHint;

  /// No description provided for @providerFormat.
  ///
  /// In en, this message translates to:
  /// **'API Format'**
  String get providerFormat;

  /// No description provided for @providerEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get providerEnabled;

  /// No description provided for @providerPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get providerPriority;

  /// No description provided for @providerPriorityHelp.
  ///
  /// In en, this message translates to:
  /// **'Lower number = higher priority'**
  String get providerPriorityHelp;

  /// No description provided for @providerAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get providerAuto;

  /// No description provided for @providerDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get providerDefault;

  /// No description provided for @providerOverride.
  ///
  /// In en, this message translates to:
  /// **'Provider Override'**
  String get providerOverride;

  /// No description provided for @noProvidersYet.
  ///
  /// In en, this message translates to:
  /// **'No providers configured'**
  String get noProvidersYet;

  /// No description provided for @noProvidersHelp.
  ///
  /// In en, this message translates to:
  /// **'Add a provider to use custom LLM endpoints'**
  String get noProvidersHelp;

  /// No description provided for @providerSaved.
  ///
  /// In en, this message translates to:
  /// **'Provider saved'**
  String get providerSaved;

  /// No description provided for @providerDeleted.
  ///
  /// In en, this message translates to:
  /// **'Provider deleted'**
  String get providerDeleted;

  /// No description provided for @providerSessionLabel.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get providerSessionLabel;

  /// No description provided for @providerOverrideFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save provider selection'**
  String get providerOverrideFailed;

  /// No description provided for @reasoningEffortDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get reasoningEffortDefault;

  /// No description provided for @reasoningEffortLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get reasoningEffortLow;

  /// No description provided for @reasoningEffortMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get reasoningEffortMedium;

  /// No description provided for @reasoningEffortHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get reasoningEffortHigh;

  /// No description provided for @reasoningEffortXhigh.
  ///
  /// In en, this message translates to:
  /// **'XHigh'**
  String get reasoningEffortXhigh;

  /// No description provided for @reasoningEffortMax.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get reasoningEffortMax;

  /// No description provided for @reasoningEffortOverride.
  ///
  /// In en, this message translates to:
  /// **'Reasoning Effort'**
  String get reasoningEffortOverride;

  /// No description provided for @reasoningEffortSessionLabel.
  ///
  /// In en, this message translates to:
  /// **'Reasoning effort'**
  String get reasoningEffortSessionLabel;

  /// No description provided for @reasoningEffortOverrideFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save reasoning effort'**
  String get reasoningEffortOverrideFailed;

  /// No description provided for @modelDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get modelDefault;

  /// No description provided for @modelSessionLabel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get modelSessionLabel;

  /// No description provided for @modelOverrideFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save model selection'**
  String get modelOverrideFailed;

  /// No description provided for @copySessionId.
  ///
  /// In en, this message translates to:
  /// **'Copy {agent} ID'**
  String copySessionId(Object agent);

  /// No description provided for @desktopSessionOverview.
  ///
  /// In en, this message translates to:
  /// **'Session overview'**
  String get desktopSessionOverview;

  /// No description provided for @desktopSessionOverviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keep status, context, and actions visible without leaving the conversation.'**
  String get desktopSessionOverviewSubtitle;

  /// No description provided for @desktopSessionUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get desktopSessionUpdated;

  /// No description provided for @desktopSessionStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get desktopSessionStatus;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @fieldRequired.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get fieldRequired;

  /// No description provided for @unknownRoute.
  ///
  /// In en, this message translates to:
  /// **'Unknown route: {route}'**
  String unknownRoute(Object route);

  /// No description provided for @recentProjectsTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent projects'**
  String get recentProjectsTitle;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @subtitles.
  ///
  /// In en, this message translates to:
  /// **'Subtitles'**
  String get subtitles;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @hold.
  ///
  /// In en, this message translates to:
  /// **'Hold'**
  String get hold;

  /// No description provided for @microphone.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get microphone;

  /// No description provided for @end.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get end;

  /// No description provided for @openNavigation.
  ///
  /// In en, this message translates to:
  /// **'Open navigation'**
  String get openNavigation;

  /// No description provided for @providerOrder.
  ///
  /// In en, this message translates to:
  /// **'Provider order'**
  String get providerOrder;

  /// No description provided for @configured.
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get configured;

  /// No description provided for @enabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enabled;

  /// No description provided for @defaultLabel.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultLabel;

  /// No description provided for @none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No description provided for @projectDesk.
  ///
  /// In en, this message translates to:
  /// **'Project desk'**
  String get projectDesk;

  /// No description provided for @allSessions.
  ///
  /// In en, this message translates to:
  /// **'All sessions'**
  String get allSessions;

  /// No description provided for @inMotion.
  ///
  /// In en, this message translates to:
  /// **'In motion'**
  String get inMotion;

  /// No description provided for @clearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// No description provided for @projectContext.
  ///
  /// In en, this message translates to:
  /// **'Project context'**
  String get projectContext;

  /// No description provided for @rootPath.
  ///
  /// In en, this message translates to:
  /// **'Root path'**
  String get rootPath;

  /// No description provided for @branch.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get branch;

  /// No description provided for @gitState.
  ///
  /// In en, this message translates to:
  /// **'Git state'**
  String get gitState;

  /// No description provided for @statusMix.
  ///
  /// In en, this message translates to:
  /// **'Status mix'**
  String get statusMix;

  /// No description provided for @approvals.
  ///
  /// In en, this message translates to:
  /// **'Approvals'**
  String get approvals;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @projectNotesNoActiveSessions.
  ///
  /// In en, this message translates to:
  /// **'No active sessions yet. Start a new one to turn this project into a working desk.'**
  String get projectNotesNoActiveSessions;

  /// No description provided for @projectNotesWaitingApproval.
  ///
  /// In en, this message translates to:
  /// **'There are sessions waiting on approval. Review them before starting parallel work.'**
  String get projectNotesWaitingApproval;

  /// No description provided for @projectNotesActiveWork.
  ///
  /// In en, this message translates to:
  /// **'This project has active work in motion. Keep recent sessions concise and easy to scan.'**
  String get projectNotesActiveWork;

  /// No description provided for @projectNotesQuiet.
  ///
  /// In en, this message translates to:
  /// **'The current session mix is quiet. Use this space to restart stalled threads or begin a focused run.'**
  String get projectNotesQuiet;

  /// No description provided for @sessionOptions.
  ///
  /// In en, this message translates to:
  /// **'Session options'**
  String get sessionOptions;

  /// No description provided for @collapseSessionDetails.
  ///
  /// In en, this message translates to:
  /// **'Collapse session details'**
  String get collapseSessionDetails;

  /// No description provided for @customModel.
  ///
  /// In en, this message translates to:
  /// **'Custom model'**
  String get customModel;

  /// No description provided for @files.
  ///
  /// In en, this message translates to:
  /// **'files'**
  String get files;

  /// No description provided for @scrollToLatest.
  ///
  /// In en, this message translates to:
  /// **'Scroll to latest'**
  String get scrollToLatest;

  /// No description provided for @project.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get project;

  /// No description provided for @path.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get path;

  /// No description provided for @gitSnapshot.
  ///
  /// In en, this message translates to:
  /// **'Git snapshot'**
  String get gitSnapshot;

  /// No description provided for @summary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get summary;

  /// No description provided for @projectContextUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Project context is unavailable.'**
  String get projectContextUnavailable;

  /// No description provided for @clientId.
  ///
  /// In en, this message translates to:
  /// **'Client ID'**
  String get clientId;

  /// No description provided for @replyBehaviorSection.
  ///
  /// In en, this message translates to:
  /// **'Reply behavior'**
  String get replyBehaviorSection;

  /// No description provided for @currentVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Current version'**
  String get currentVersionLabel;

  /// No description provided for @updateManifest.
  ///
  /// In en, this message translates to:
  /// **'Update manifest'**
  String get updateManifest;

  /// No description provided for @atAGlance.
  ///
  /// In en, this message translates to:
  /// **'At a glance'**
  String get atAGlance;

  /// No description provided for @workspaceNote.
  ///
  /// In en, this message translates to:
  /// **'Workspace note'**
  String get workspaceNote;

  /// No description provided for @threads.
  ///
  /// In en, this message translates to:
  /// **'Threads'**
  String get threads;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @review.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get review;

  /// No description provided for @newLabel.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newLabel;

  /// No description provided for @inFocus.
  ///
  /// In en, this message translates to:
  /// **'In focus'**
  String get inFocus;

  /// No description provided for @upNext.
  ///
  /// In en, this message translates to:
  /// **'Up next'**
  String get upNext;

  /// No description provided for @threadsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} threads'**
  String threadsCount(int count);

  /// No description provided for @nothingUrgentWaiting.
  ///
  /// In en, this message translates to:
  /// **'Nothing urgent is waiting right now.'**
  String get nothingUrgentWaiting;

  /// No description provided for @visibleProjectsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} visible'**
  String visibleProjectsCount(int count);

  /// No description provided for @authorizationNeeded.
  ///
  /// In en, this message translates to:
  /// **'Authorization needed'**
  String get authorizationNeeded;

  /// No description provided for @connectedBridge.
  ///
  /// In en, this message translates to:
  /// **'Connected • {address}'**
  String connectedBridge(Object address);

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @collapseStatus.
  ///
  /// In en, this message translates to:
  /// **'Collapse status'**
  String get collapseStatus;

  /// No description provided for @pendingApprovals.
  ///
  /// In en, this message translates to:
  /// **'Pending approvals'**
  String get pendingApprovals;

  /// No description provided for @waitingActionsNeedReview.
  ///
  /// In en, this message translates to:
  /// **'{count} waiting actions need review'**
  String waitingActionsNeedReview(int count);

  /// No description provided for @noApprovalsWaiting.
  ///
  /// In en, this message translates to:
  /// **'No approvals are waiting right now'**
  String get noApprovalsWaiting;

  /// No description provided for @bridgeStatus.
  ///
  /// In en, this message translates to:
  /// **'Bridge status'**
  String get bridgeStatus;

  /// No description provided for @voiceDevice.
  ///
  /// In en, this message translates to:
  /// **'Voice / device'**
  String get voiceDevice;

  /// No description provided for @activeSessionsMicrophoneReady.
  ///
  /// In en, this message translates to:
  /// **'{count} active sessions • microphone ready'**
  String activeSessionsMicrophoneReady(int count);

  /// No description provided for @microphoneReadySystemSpeechAvailable.
  ///
  /// In en, this message translates to:
  /// **'Microphone ready • system speech available'**
  String get microphoneReadySystemSpeechAvailable;

  /// No description provided for @projectsOverview.
  ///
  /// In en, this message translates to:
  /// **'Projects overview'**
  String get projectsOverview;

  /// No description provided for @activeProjectsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} active projects'**
  String activeProjectsCount(int count);

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get quickActions;

  /// No description provided for @quickActionsBody.
  ///
  /// In en, this message translates to:
  /// **'Open projects or adjust settings'**
  String get quickActionsBody;

  /// No description provided for @pluginManifest.
  ///
  /// In en, this message translates to:
  /// **'Plugin manifest'**
  String get pluginManifest;

  /// No description provided for @importLabel.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importLabel;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemDefault;

  /// No description provided for @systemDefaultCapabilitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use the built-in behavior for this capability.'**
  String get systemDefaultCapabilitySubtitle;

  /// No description provided for @chooseSpeechCapabilityProvider.
  ///
  /// In en, this message translates to:
  /// **'Choose system default or pick a plugin for this capability.'**
  String get chooseSpeechCapabilityProvider;

  /// No description provided for @savingPluginSettings.
  ///
  /// In en, this message translates to:
  /// **'Saving plugin settings...'**
  String get savingPluginSettings;

  /// No description provided for @savedToSettings.
  ///
  /// In en, this message translates to:
  /// **'Saved to settings.'**
  String get savedToSettings;

  /// No description provided for @pluginSettingsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save plugin settings.\n\nRaw error:\n{error}'**
  String pluginSettingsSaveFailed(Object error);

  /// No description provided for @fillRequiredPluginSettings.
  ///
  /// In en, this message translates to:
  /// **'Fill in the required settings below before using this plugin.'**
  String get fillRequiredPluginSettings;

  /// No description provided for @defaultTtsTestText.
  ///
  /// In en, this message translates to:
  /// **'Hello from Omni Code speech settings.'**
  String get defaultTtsTestText;

  /// No description provided for @systemTtsTestUnavailable.
  ///
  /// In en, this message translates to:
  /// **'System TTS test is not available on this platform. Choose a TTS plugin to test playback here.'**
  String get systemTtsTestUnavailable;

  /// No description provided for @startingPlaybackTest.
  ///
  /// In en, this message translates to:
  /// **'Starting playback test...'**
  String get startingPlaybackTest;

  /// No description provided for @playbackStartedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Playback started successfully.'**
  String get playbackStartedSuccessfully;

  /// No description provided for @testTts.
  ///
  /// In en, this message translates to:
  /// **'Test TTS'**
  String get testTts;

  /// No description provided for @systemDefaultTtsCannotBeTested.
  ///
  /// In en, this message translates to:
  /// **'System default TTS cannot be tested on this platform.'**
  String get systemDefaultTtsCannotBeTested;

  /// No description provided for @ttsTestUsesCurrentConfiguration.
  ///
  /// In en, this message translates to:
  /// **'TTS test uses your current saved speech configuration.'**
  String get ttsTestUsesCurrentConfiguration;

  /// No description provided for @testText.
  ///
  /// In en, this message translates to:
  /// **'Test text'**
  String get testText;

  /// No description provided for @playing.
  ///
  /// In en, this message translates to:
  /// **'Playing...'**
  String get playing;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @batchAsrAuthOrParameterError.
  ///
  /// In en, this message translates to:
  /// **'Authentication or parameter error. Check that APPID and API Key (Access Token) are correct.\n\nRaw error:\n{error}'**
  String batchAsrAuthOrParameterError(Object error);

  /// No description provided for @batchAsrAuthenticationFailed.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed. Check that the API Key is correct and enabled for this service.\n\nRaw error:\n{error}'**
  String batchAsrAuthenticationFailed(Object error);

  /// No description provided for @batchAsrAccessDenied.
  ///
  /// In en, this message translates to:
  /// **'Access denied. Check that the API Key has permission for the selected Resource ID.\n\nRaw error:\n{error}'**
  String batchAsrAccessDenied(Object error);

  /// No description provided for @microphonePermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission is required.'**
  String get microphonePermissionRequired;

  /// No description provided for @recordingStartedSpeakThenStop.
  ///
  /// In en, this message translates to:
  /// **'Recording started. Speak a short sentence, then stop.'**
  String get recordingStartedSpeakThenStop;

  /// No description provided for @transcribingRecordedAudio.
  ///
  /// In en, this message translates to:
  /// **'Transcribing recorded audio...'**
  String get transcribingRecordedAudio;

  /// No description provided for @transcriptionSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Transcription succeeded.'**
  String get transcriptionSucceeded;

  /// No description provided for @transcriptionSucceededWithText.
  ///
  /// In en, this message translates to:
  /// **'Transcription succeeded: {text}'**
  String transcriptionSucceededWithText(Object text);

  /// No description provided for @testBatchAsr.
  ///
  /// In en, this message translates to:
  /// **'Test Batch ASR'**
  String get testBatchAsr;

  /// No description provided for @batchAsrTestDescription.
  ///
  /// In en, this message translates to:
  /// **'Batch ASR test records a short clip, then transcribes it with your current saved speech configuration.'**
  String get batchAsrTestDescription;

  /// No description provided for @record.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get record;

  /// No description provided for @transcribing.
  ///
  /// In en, this message translates to:
  /// **'Transcribing...'**
  String get transcribing;

  /// No description provided for @stopAndTranscribe.
  ///
  /// In en, this message translates to:
  /// **'Stop & Transcribe'**
  String get stopAndTranscribe;

  /// No description provided for @recordingSpeakThenStop.
  ///
  /// In en, this message translates to:
  /// **'Recording... speak a short sentence, then stop.'**
  String get recordingSpeakThenStop;

  /// No description provided for @realtimeAsrAuthenticationRejected.
  ///
  /// In en, this message translates to:
  /// **'The current service rejected realtime speech authentication. Check the selected plugin credentials, especially API Key and Resource ID.\n\nRaw error:\n{error}'**
  String realtimeAsrAuthenticationRejected(Object error);

  /// No description provided for @realtimeAsrAccessRefused.
  ///
  /// In en, this message translates to:
  /// **'The current service refused realtime speech access. Check that the API Key is enabled for the selected Volcengine speech resource, and that Resource ID exactly matches the purchased duration or concurrent edition.\n\nRaw error:\n{error}'**
  String realtimeAsrAccessRefused(Object error);

  /// No description provided for @realtimeAsrStartFailed.
  ///
  /// In en, this message translates to:
  /// **'The current service could not start realtime speech. This usually means the selected plugin is not exposing a valid realtime websocket endpoint.\n\nRaw error:\n{error}'**
  String realtimeAsrStartFailed(Object error);

  /// No description provided for @startingRealtimeSpeechTest.
  ///
  /// In en, this message translates to:
  /// **'Starting realtime speech test...'**
  String get startingRealtimeSpeechTest;

  /// No description provided for @realtimeTranscriptReceived.
  ///
  /// In en, this message translates to:
  /// **'Realtime transcript received.'**
  String get realtimeTranscriptReceived;

  /// No description provided for @realtimeSpeechComingThrough.
  ///
  /// In en, this message translates to:
  /// **'Realtime speech is coming through.'**
  String get realtimeSpeechComingThrough;

  /// No description provided for @realtimeSpeechComingThroughWithText.
  ///
  /// In en, this message translates to:
  /// **'Realtime speech is coming through: {text}'**
  String realtimeSpeechComingThroughWithText(Object text);

  /// No description provided for @listeningSpeakShortSentence.
  ///
  /// In en, this message translates to:
  /// **'Listening now. Speak a short sentence.'**
  String get listeningSpeakShortSentence;

  /// No description provided for @testRealtimeAsr.
  ///
  /// In en, this message translates to:
  /// **'Test Realtime ASR'**
  String get testRealtimeAsr;

  /// No description provided for @realtimeAsrSystemTestDescription.
  ///
  /// In en, this message translates to:
  /// **'Realtime ASR test uses the current saved system speech input.'**
  String get realtimeAsrSystemTestDescription;

  /// No description provided for @realtimeAsrPluginTestDescription.
  ///
  /// In en, this message translates to:
  /// **'Realtime ASR test uses the current saved plugin configuration.'**
  String get realtimeAsrPluginTestDescription;

  /// No description provided for @starting.
  ///
  /// In en, this message translates to:
  /// **'Starting...'**
  String get starting;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @use.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get use;

  /// No description provided for @test.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get test;

  /// No description provided for @uninstall.
  ///
  /// In en, this message translates to:
  /// **'Uninstall'**
  String get uninstall;

  /// No description provided for @install.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get install;

  /// No description provided for @getApiKey.
  ///
  /// In en, this message translates to:
  /// **'Get API key'**
  String get getApiKey;

  /// No description provided for @startService.
  ///
  /// In en, this message translates to:
  /// **'Start Service'**
  String get startService;

  /// No description provided for @stopService.
  ///
  /// In en, this message translates to:
  /// **'Stop Service'**
  String get stopService;

  /// No description provided for @sentAsXApiKey.
  ///
  /// In en, this message translates to:
  /// **'Sent using the plugin authentication configuration.'**
  String get sentAsXApiKey;

  /// No description provided for @targetSpeakerOnly.
  ///
  /// In en, this message translates to:
  /// **'Target speaker only'**
  String get targetSpeakerOnly;

  /// No description provided for @speakerName.
  ///
  /// In en, this message translates to:
  /// **'Speaker name'**
  String get speakerName;

  /// No description provided for @myVoice.
  ///
  /// In en, this message translates to:
  /// **'My voice'**
  String get myVoice;

  /// No description provided for @speaker.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get speaker;

  /// No description provided for @enrollSpeakerBeforeFiltering.
  ///
  /// In en, this message translates to:
  /// **'Enroll a speaker on the bridge before enabling filtering.'**
  String get enrollSpeakerBeforeFiltering;

  /// No description provided for @batchAsrIgnoresUnmatchedSpeaker.
  ///
  /// In en, this message translates to:
  /// **'Batch ASR will ignore speech that does not match the selected voiceprint.'**
  String get batchAsrIgnoresUnmatchedSpeaker;

  /// No description provided for @voiceprintModelInstalled.
  ///
  /// In en, this message translates to:
  /// **'Voiceprint model installed'**
  String get voiceprintModelInstalled;

  /// No description provided for @voiceprintModelRequired.
  ///
  /// In en, this message translates to:
  /// **'Voiceprint model is required'**
  String get voiceprintModelRequired;

  /// No description provided for @savingSpeaker.
  ///
  /// In en, this message translates to:
  /// **'Saving speaker'**
  String get savingSpeaker;

  /// No description provided for @finishEnrollment.
  ///
  /// In en, this message translates to:
  /// **'Finish enrollment'**
  String get finishEnrollment;

  /// No description provided for @recordEnrollmentSample.
  ///
  /// In en, this message translates to:
  /// **'Record enrollment sample'**
  String get recordEnrollmentSample;

  /// No description provided for @speechRoutingSystemDefaultIntro.
  ///
  /// In en, this message translates to:
  /// **'Speech uses the system by default. Install a plugin only for the capabilities that need a custom service.'**
  String get speechRoutingSystemDefaultIntro;

  /// No description provided for @realtimeAsrRouteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Mic streaming, live transcripts, and interrupt detection.'**
  String get realtimeAsrRouteSubtitle;

  /// No description provided for @realtimeAsrRouteFooter.
  ///
  /// In en, this message translates to:
  /// **'Good default for on-device dictation and interruption handling.'**
  String get realtimeAsrRouteFooter;

  /// No description provided for @batchAsrRouteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Recorded clips, uploads, and non-realtime recognition.'**
  String get batchAsrRouteSubtitle;

  /// No description provided for @batchAsrRouteFooter.
  ///
  /// In en, this message translates to:
  /// **'Useful for cloud transcription providers or higher-accuracy offline jobs.'**
  String get batchAsrRouteFooter;

  /// No description provided for @ttsRouteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reply playback, voice output, and spoken call-mode responses.'**
  String get ttsRouteSubtitle;

  /// No description provided for @ttsRouteFooter.
  ///
  /// In en, this message translates to:
  /// **'Use a plugin when you want a cloud voice or a local TTS service.'**
  String get ttsRouteFooter;

  /// No description provided for @systemRealtimeAsrTestUnavailable.
  ///
  /// In en, this message translates to:
  /// **'System realtime ASR cannot be tested on this platform. Choose a realtime ASR plugin to test here.'**
  String get systemRealtimeAsrTestUnavailable;

  /// No description provided for @systemBatchAsrTestUnavailable.
  ///
  /// In en, this message translates to:
  /// **'System default does not provide batch ASR testing. Choose a batch ASR plugin to test transcription here.'**
  String get systemBatchAsrTestUnavailable;

  /// No description provided for @selectedPluginNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'The selected plugin is not installed, so it cannot be tested.'**
  String get selectedPluginNotInstalled;

  /// No description provided for @selectedPluginMissingCapabilityConfig.
  ///
  /// In en, this message translates to:
  /// **'The selected plugin does not expose {capability} configuration, so it cannot be tested.'**
  String selectedPluginMissingCapabilityConfig(Object capability);

  /// No description provided for @expectedTtsEndpoint.
  ///
  /// In en, this message translates to:
  /// **'an OpenAI-compatible TTS endpoint'**
  String get expectedTtsEndpoint;

  /// No description provided for @expectedTranscriptionEndpoint.
  ///
  /// In en, this message translates to:
  /// **'an OpenAI-compatible transcription endpoint'**
  String get expectedTranscriptionEndpoint;

  /// No description provided for @expectedRealtimeWebsocketEndpoint.
  ///
  /// In en, this message translates to:
  /// **'a realtime websocket endpoint'**
  String get expectedRealtimeWebsocketEndpoint;

  /// No description provided for @currentSelectionMissingExpectedEndpoint.
  ///
  /// In en, this message translates to:
  /// **'The current selection does not expose {expected}, so testing is unavailable.'**
  String currentSelectionMissingExpectedEndpoint(Object expected);

  /// No description provided for @currentSelectionMissingRequiredSetting.
  ///
  /// In en, this message translates to:
  /// **'The current selection is missing {setting}, so testing is unavailable.'**
  String currentSelectionMissingRequiredSetting(Object setting);

  /// No description provided for @currentSelectionMissingRealtimeWebsocketUrl.
  ///
  /// In en, this message translates to:
  /// **'The current selection is missing a realtime websocket URL, so testing is unavailable.'**
  String get currentSelectionMissingRealtimeWebsocketUrl;

  /// No description provided for @currentSelectionInvalidRealtimeWebsocketUrl.
  ///
  /// In en, this message translates to:
  /// **'The current selection has an invalid realtime websocket URL, so testing is unavailable.'**
  String get currentSelectionInvalidRealtimeWebsocketUrl;

  /// No description provided for @currentSelectionNonStreamingEndpoint.
  ///
  /// In en, this message translates to:
  /// **'The current selection points to a non-streaming endpoint, so testing is unavailable. Configure a realtime websocket URL first.'**
  String get currentSelectionNonStreamingEndpoint;

  /// No description provided for @installedAndReady.
  ///
  /// In en, this message translates to:
  /// **'Installed and ready to use.'**
  String get installedAndReady;

  /// No description provided for @installBeforeSelectingPlugin.
  ///
  /// In en, this message translates to:
  /// **'Install first before selecting this plugin.'**
  String get installBeforeSelectingPlugin;

  /// No description provided for @fillRequiredPluginSettingsBeforeTesting.
  ///
  /// In en, this message translates to:
  /// **'Fill in the required settings before testing.'**
  String get fillRequiredPluginSettingsBeforeTesting;

  /// No description provided for @commandSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Command succeeded: {command}'**
  String commandSucceeded(Object command);

  /// No description provided for @commandFailed.
  ///
  /// In en, this message translates to:
  /// **'Command failed ({exitCode}): {stderr}'**
  String commandFailed(int exitCode, Object stderr);

  /// No description provided for @missingKey.
  ///
  /// In en, this message translates to:
  /// **'Missing key'**
  String get missingKey;

  /// No description provided for @keySaved.
  ///
  /// In en, this message translates to:
  /// **'Key saved'**
  String get keySaved;

  /// No description provided for @pluginApiKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'{pluginName} · API Key'**
  String pluginApiKeyTitle(Object pluginName);

  /// No description provided for @savePluginSettings.
  ///
  /// In en, this message translates to:
  /// **'Save plugin settings'**
  String get savePluginSettings;

  /// No description provided for @saveAndUse.
  ///
  /// In en, this message translates to:
  /// **'Save and use'**
  String get saveAndUse;

  /// No description provided for @additionalPluginSettings.
  ///
  /// In en, this message translates to:
  /// **'Additional plugin settings'**
  String get additionalPluginSettings;

  /// No description provided for @bridgeErrorWithStatus.
  ///
  /// In en, this message translates to:
  /// **'Bridge error ({status}): {error}'**
  String bridgeErrorWithStatus(Object status, Object error);

  /// No description provided for @noEnrollmentAudioRecorded.
  ///
  /// In en, this message translates to:
  /// **'No enrollment audio was recorded.'**
  String get noEnrollmentAudioRecorded;

  /// No description provided for @defaultSpeakerName.
  ///
  /// In en, this message translates to:
  /// **'Speaker {index}'**
  String defaultSpeakerName(int index);

  /// No description provided for @gitClean.
  ///
  /// In en, this message translates to:
  /// **'clean'**
  String get gitClean;

  /// No description provided for @gitDirty.
  ///
  /// In en, this message translates to:
  /// **'dirty'**
  String get gitDirty;

  /// No description provided for @gitStaged.
  ///
  /// In en, this message translates to:
  /// **'staged'**
  String get gitStaged;

  /// No description provided for @gitChanged.
  ///
  /// In en, this message translates to:
  /// **'changed'**
  String get gitChanged;

  /// No description provided for @gitUntracked.
  ///
  /// In en, this message translates to:
  /// **'untracked'**
  String get gitUntracked;

  /// No description provided for @gitAhead.
  ///
  /// In en, this message translates to:
  /// **'ahead {count}'**
  String gitAhead(int count);

  /// No description provided for @gitBehind.
  ///
  /// In en, this message translates to:
  /// **'behind {count}'**
  String gitBehind(int count);

  /// No description provided for @gitChangedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} changed'**
  String gitChangedCount(int count);

  /// No description provided for @gitStagedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} staged'**
  String gitStagedCount(int count);

  /// No description provided for @gitUnstagedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} modified'**
  String gitUnstagedCount(int count);

  /// No description provided for @gitUntrackedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} untracked'**
  String gitUntrackedCount(int count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
