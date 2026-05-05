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
  /// **'If empty, /app-update/manifest from the current Bridge is used. When a new version is found, the system opens the download link and handles installation.'**
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

  /// No description provided for @whisperCompatible.
  ///
  /// In en, this message translates to:
  /// **'Whisper / OpenAI Compatible'**
  String get whisperCompatible;

  /// No description provided for @apiKey.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get apiKey;

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
  /// **'Use an OpenAI-compatible endpoint to approve low-risk commands'**
  String get enableAiApprovalSubtitle;

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

  /// No description provided for @compressReplies.
  ///
  /// In en, this message translates to:
  /// **'Compress AI replies'**
  String get compressReplies;

  /// No description provided for @compressRepliesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When enabled, new sessions ask the AI to summarize what it did briefly, ideally within 50 characters'**
  String get compressRepliesSubtitle;

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

  /// No description provided for @createProject.
  ///
  /// In en, this message translates to:
  /// **'Create project'**
  String get createProject;

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

  /// No description provided for @projectCount.
  ///
  /// In en, this message translates to:
  /// **'{count} sessions'**
  String projectCount(int count);

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

  /// No description provided for @searchSessions.
  ///
  /// In en, this message translates to:
  /// **'Search session title or summary'**
  String get searchSessions;

  /// No description provided for @sessionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get sessionsTitle;

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

  /// No description provided for @loadMoreSessions.
  ///
  /// In en, this message translates to:
  /// **'Load more ({count})'**
  String loadMoreSessions(int count);

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

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @refreshNativeSessions.
  ///
  /// In en, this message translates to:
  /// **'Refresh native sessions'**
  String get refreshNativeSessions;

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

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

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

  /// No description provided for @zhipuApiKeyRequired.
  ///
  /// In en, this message translates to:
  /// **'Fill in the Zhipu API key in settings first'**
  String get zhipuApiKeyRequired;

  /// No description provided for @zhipuAsrRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Zhipu ASR request failed ({statusCode}): {body}'**
  String zhipuAsrRequestFailed(Object statusCode, Object body);

  /// No description provided for @zhipuAsrMissingText.
  ///
  /// In en, this message translates to:
  /// **'Zhipu ASR response is missing text'**
  String get zhipuAsrMissingText;

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

  /// No description provided for @zhipuTtsRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Zhipu TTS request failed ({statusCode}): {body}'**
  String zhipuTtsRequestFailed(Object statusCode, Object body);

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
  /// **'Update manifest is missing apk_url'**
  String get updateManifestMissingApkUrl;
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
