// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Omni Code';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get save => 'Save';

  @override
  String get saving => 'Saving...';

  @override
  String get systemSection => 'System';

  @override
  String get languageSection => 'Language';

  @override
  String get languageLabel => 'App language';

  @override
  String get languageSystem => 'Follow system';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => 'Chinese';

  @override
  String get bridgeSection => 'Bridge';

  @override
  String get bridgeUrlLabel => 'Bridge URL';

  @override
  String get bridgeHelp =>
      'Use 127.0.0.1:8787 with adb reverse. For LAN access, enter your computer IP. The server can allow requests by token and client ID.';

  @override
  String get appUpdateSection => 'App Update';

  @override
  String get updateManifestUrlLabel => 'Manifest URL';

  @override
  String get updateTargetVersionLabel => 'Target version';

  @override
  String get updateTargetVersionHelp =>
      'Optional. Enter a release version like 0.2.1 to download that specific GitHub release instead of the latest one.';

  @override
  String get checkingUpdate => 'Checking...';

  @override
  String get checkAppUpdate => 'Check app update';

  @override
  String get updateHelp =>
      'By default, updates are checked from the official GitHub release manifest. You can override it with a custom manifest URL, including a self-hosted Bridge manifest. When a new version is found, the system opens the download link and handles installation.';

  @override
  String get speechSection => 'Speech';

  @override
  String get ttsProviderLabel => 'TTS Provider';

  @override
  String get asrProviderLabel => 'ASR Provider';

  @override
  String get bridgeCloudProxy => 'Bridge / Cloud relay';

  @override
  String get whisperCompatible => 'Whisper / OpenAI Compatible';

  @override
  String get apiKey => 'API Key';

  @override
  String get appId => 'App ID';

  @override
  String get secretId => 'Secret ID';

  @override
  String get secretKey => 'Secret Key';

  @override
  String get baseUrl => 'Base URL';

  @override
  String get aiApprovalSection => 'AI Approval';

  @override
  String get enableAiApproval => 'Enable AI-assisted approval';

  @override
  String get enableAiApprovalSubtitle =>
      'Use an OpenAI-compatible endpoint to approve low-risk commands';

  @override
  String get aiApprovalMaxRisk => 'Highest auto-approval risk';

  @override
  String get aiApprovalHelp =>
      'Saved settings sync to the current Bridge. Keeping Low is recommended. High-risk commands, failed calls, or hard-blocked rules still fall back to manual approval on the phone.';

  @override
  String get riskLow => 'Low';

  @override
  String get riskMedium => 'Medium';

  @override
  String get riskHigh => 'High';

  @override
  String get autoSpeakReplies => 'Auto-play agent replies';

  @override
  String get autoSpeakRepliesSubtitle =>
      'Start playback automatically after the AI reply finishes';

  @override
  String get speechPlaybackPrompt => 'Optimize replies for speech playback';

  @override
  String get speechPlaybackPromptSubtitle =>
      'When a reply will be spoken aloud, ask the agent to avoid hard-to-read-aloud content unless you explicitly request it.';

  @override
  String get compressReplies => 'Compress AI replies';

  @override
  String get compressRepliesSubtitle =>
      'When enabled, new sessions ask the AI to summarize what it did briefly';

  @override
  String get compressReplyMaxChars => 'Compressed reply max chars';

  @override
  String get settingsSaved => 'Settings saved';

  @override
  String settingsSaveFailed(Object error) {
    return 'Failed to save settings: $error';
  }

  @override
  String alreadyLatestVersion(Object version) {
    return 'Already up to date: $version';
  }

  @override
  String newVersionFound(Object versionName) {
    return 'New version $versionName';
  }

  @override
  String targetVersionReady(Object versionName) {
    return 'Version $versionName is ready';
  }

  @override
  String targetVersionNotFound(Object version) {
    return 'Version $version could not be found or downloaded';
  }

  @override
  String get targetVersionDowngradeWarning =>
      'If this is an older version than the one currently installed, Android may block the install as a downgrade.';

  @override
  String currentVersion(Object version) {
    return 'Current version: $version';
  }

  @override
  String get later => 'Later';

  @override
  String get updateNow => 'Update now';

  @override
  String get downloadingUpdate => 'Downloading update';

  @override
  String downloadedBytes(Object received) {
    return 'Downloaded $received';
  }

  @override
  String downloadProgress(Object received, Object total) {
    return '$received / $total';
  }

  @override
  String get homeManageByProject => 'Manage Codex by project';

  @override
  String homeBridgeAddress(Object address) {
    return 'Current Bridge: $address';
  }

  @override
  String get homeIntro =>
      'Open a project first, then choose an existing session or start a new Codex session under that project.';

  @override
  String get projectsTitle => 'Projects';

  @override
  String get selectProject => 'Select project';

  @override
  String get createProject => 'Create project';

  @override
  String get createNewProject => 'Create new project';

  @override
  String get newProject => 'New project';

  @override
  String get retry => 'Retry';

  @override
  String projectCount(int count) {
    return '$count sessions';
  }

  @override
  String sessionCount(int count) {
    return '$count sessions';
  }

  @override
  String projectsCount(int count) {
    return '$count projects';
  }

  @override
  String projectUpdatedAt(Object time) {
    return 'Updated $time';
  }

  @override
  String loadProjectsFailed(Object error) {
    return 'Failed to load projects: $error';
  }

  @override
  String get noProjectsYet => 'No projects yet';

  @override
  String get noProjectsHelp =>
      'Create a project first, fill in the local code directory, then start or resume a Codex session inside it.';

  @override
  String get projectName => 'Project name';

  @override
  String get localPath => 'Local directory path';

  @override
  String get cancel => 'Cancel';

  @override
  String get projectIntro =>
      'Open any session to continue the existing context, or create a new Codex session under this project.';

  @override
  String get homePrompt => 'Remote agent cockpit';

  @override
  String get homeCreateProjectHint => 'Add local codebase';

  @override
  String get homeBrowseProjects => 'Browse all';

  @override
  String get searchSessions => 'Search session title or summary';

  @override
  String get searchProjects => 'Search project name or path';

  @override
  String get themeSection => 'Theme';

  @override
  String get themeFollowSystem => 'Follow system';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get sessionsTitle => 'Recent';

  @override
  String get recentSessionsTitle => 'Recent sessions';

  @override
  String loadSessionsFailed(Object error) {
    return 'Failed to load sessions: $error';
  }

  @override
  String sessionUpdatedAtWithAgent(Object agent, Object time) {
    return '$agent · Updated $time';
  }

  @override
  String loadMoreSessions(int count) {
    return 'Load more ($count)';
  }

  @override
  String get loadMoreSessionsLabel => 'Load more';

  @override
  String get newSession => 'New session';

  @override
  String get sessionStatusIdle => 'Idle';

  @override
  String get sessionStatusRunning => 'Running';

  @override
  String get sessionStatusAwaitingApproval => 'Awaiting approval';

  @override
  String get sessionStatusWaiting => 'Waiting';

  @override
  String get sessionStatusFailed => 'Failed';

  @override
  String get noSessionsYet => 'No sessions in this project yet';

  @override
  String get noSessionsHelp =>
      'After starting a Codex session, you can return to this project and reopen the same conversation later.';

  @override
  String get noSessionsMatched =>
      'No matching sessions. Try a different keyword.';

  @override
  String get sessionTitleOptional => 'Session title (optional)';

  @override
  String get agentLabel => 'Agent';

  @override
  String get create => 'Create';

  @override
  String get refreshNativeSessions => 'Refresh native sessions';

  @override
  String get creatingSession => 'Creating session...';

  @override
  String get waitingApprovalProcessing => 'Waiting for approval processing...';

  @override
  String get waitingApprovalListening => 'Listening for approval...';

  @override
  String get connectHeader => 'Connect Bridge';

  @override
  String get connectPrompt => 'Connect your Bridge to get started.';

  @override
  String get connectWelcomeTitle => 'Welcome to Omni Code';

  @override
  String get connectWelcomeBody =>
      'Run the Bridge service on your computer, then authorize this device to open projects and continue sessions.';

  @override
  String get connectBridgeHint =>
      'Use your computer IP if the phone is on the same LAN.';

  @override
  String get connectDownloadTitle => 'Download Bridge service';

  @override
  String get connectDownloadBody =>
      'Get the service from GitHub on the computer that hosts your local projects.';

  @override
  String get connectDownloadRepo =>
      'github.com/omni-stream-ai/omni-code-bridge';

  @override
  String get authorizeThisDevice => 'Authorize this device';

  @override
  String get connectNextStep => 'Next: approval screen';

  @override
  String get backToWelcome => 'Back to welcome';

  @override
  String get waitingApprovalHeader => 'Authorization';

  @override
  String get waitingApprovalHeaderSubtitle =>
      'Approve this device on your Bridge host.';

  @override
  String get turnPausedWaiting =>
      'This turn is paused and waiting for follow-up results...';

  @override
  String get speechReadyStatus => 'Voice transcription ready';

  @override
  String get waitingProcessApproval => 'Waiting to process approval...';

  @override
  String get stopReply => 'Stop reply';

  @override
  String get messageInputHint =>
      'Enter a task, for example: Help me inspect why the latest build failed';

  @override
  String get stopVoice => 'Stop voice';

  @override
  String get voiceInput => 'Voice input';

  @override
  String get voiceChatTitle => 'Voice chat';

  @override
  String get callModeListening => 'Go ahead, I\'m listening';

  @override
  String get callModePreparingListening => 'Preparing microphone';

  @override
  String get callModeSpeaking => 'Replying out loud';

  @override
  String get callModeWorking => 'Thinking through your request';

  @override
  String get callModeIdleSubtitle =>
      'Speak naturally. I will listen, send, and read the reply back.';

  @override
  String get callModePreparingListeningLabel => 'Preparing to listen';

  @override
  String get callModePreparingListeningDetail =>
      'Microphone and speech recognition are starting. Speech may not be captured yet.';

  @override
  String get callModeListeningReadyLabel => 'Listening now';

  @override
  String get callModeListeningReadyDetail =>
      'Start speaking whenever you\'re ready. Live transcription will show up here.';

  @override
  String get callModeWaitingWakeWordLabel => 'Waiting for wake word';

  @override
  String get callModeWaitingWakeWordDetail =>
      'Put the configured wake word at the start or end of the utterance. Middle matches are ignored.';

  @override
  String get callModeWakeWordDetectedLabel => 'Wake word detected';

  @override
  String get callModeWakeWordDetectedDetail =>
      'I am listening. The next utterance will be captured and sent.';

  @override
  String get callModeWakeWordAck => 'I am listening';

  @override
  String get callModeCommandAccepted => 'Let me think';

  @override
  String callModeRejectedSpeakerTranscript(String transcript) {
    return '$transcript (not selected speaker)';
  }

  @override
  String callModeRejectedWakeWordTranscript(String transcript) {
    return '$transcript (wake word not matched)';
  }

  @override
  String get callModeSpeechDetectedLabel => 'Speech detected';

  @override
  String get callModeSpeechDetectedDetail =>
      'Keep talking naturally. The current utterance is still being captured.';

  @override
  String get callModeWaitingForPauseLabel => 'Waiting for you to finish';

  @override
  String get callModeWaitingForPauseDetail =>
      'After a short pause, this utterance will be sent automatically.';

  @override
  String get callModeOpenChatHistory => 'Open chat history';

  @override
  String get showCallModeSubtitles => 'Show subtitles';

  @override
  String get hideCallModeSubtitles => 'Hide subtitles';

  @override
  String get startCallMode => 'Start call mode';

  @override
  String get stopCallMode => 'Stop call mode';

  @override
  String get callModeUnavailable =>
      'Call mode is unavailable until speech services finish initializing.';

  @override
  String get callModeRequiresStreamingAsr =>
      'Call mode currently requires System ASR or Omni Bridge Local.';

  @override
  String get callModeSection => 'Call mode';

  @override
  String get callModeAllowInterruptionsLabel => 'Allow speaking over replies';

  @override
  String get callModeAllowInterruptionsHelp =>
      'When enabled, speaking again during call mode will stop the current spoken reply and take over the turn.';

  @override
  String get callModeSpeechPauseLabel => 'Speech pause detection';

  @override
  String get callModeSpeechPauseHelp =>
      'How long to wait after you stop speaking before the current utterance is sent automatically.';

  @override
  String callModeSpeechPauseOption(Object seconds) {
    return 'Pause ${seconds}s';
  }

  @override
  String get callModeSpeechPauseBridgeOnlyHint =>
      'This pause setting currently applies precisely to Omni Bridge Local realtime call mode. Other ASR providers may keep their own built-in pause behavior.';

  @override
  String get callModeWakeWordLabel => 'Require wake word';

  @override
  String get callModeWakeWordHelp =>
      'When enabled, Omni Bridge Local uses its local keyword detector before accepting realtime speech. Unsupported phrases are rejected with a setup error.';

  @override
  String get callModeWakeWordsLabel => 'Wake words';

  @override
  String get callModeWakeWordsHelp =>
      'Separate multiple phrases with commas. English phrases and numbered pinyin such as ou1 mi3 are converted to model tokens. Direct Chinese characters are not supported.';

  @override
  String get callModeWakeWordsEmptyError => 'Enter at least one wake word.';

  @override
  String callModeWakeWordsUnsupportedError(String wakeWord, String example) {
    return '\"$wakeWord\" is not supported by the local wake-word model. Use an English phrase, numbered pinyin, or model token sequence such as \"$example\".';
  }

  @override
  String get callModeWakeWordModelUnsupported =>
      'The current speech model does not support wake words. Wake word detection has been automatically disabled.';

  @override
  String get send => 'Send';

  @override
  String get imageAttachment => 'Image attachment';

  @override
  String get previewImage => 'Preview';

  @override
  String get imagePreviewTitle => 'Image preview';

  @override
  String get imagePreviewLoadFailed => 'Failed to load image preview';

  @override
  String get imagePreviewBgDark => 'Dark';

  @override
  String get imagePreviewBgLight => 'Light';

  @override
  String get imagePreviewBgChecker => 'Checker';

  @override
  String agentAwaitingPermission(Object agent) {
    return '$agent is waiting for permission';
  }

  @override
  String get desktopOnlyApproval =>
      'This request can currently only be handled on desktop.';

  @override
  String get approve => 'Approve';

  @override
  String get approveForSession => 'Allow for this session';

  @override
  String get reject => 'Reject';

  @override
  String get processing => 'Processing...';

  @override
  String get toolActivity => 'Tool activity';

  @override
  String get working => 'Working...';

  @override
  String get stopPlayback => 'Stop playback';

  @override
  String get playback => 'Play';

  @override
  String createSessionFailed(Object error) {
    return 'Failed to create session: $error';
  }

  @override
  String loadMessagesFailed(Object error) {
    return 'Failed to load messages: $error';
  }

  @override
  String restoreSessionFailed(Object error) {
    return 'Failed to restore session: $error';
  }

  @override
  String approvalSubmitFailed(Object error) {
    return 'Failed to submit approval: $error';
  }

  @override
  String get approvalAccepted => 'Approval granted';

  @override
  String get approvalAcceptedForSession =>
      'Similar future requests are allowed in this session';

  @override
  String get approvalAlwaysAllow => 'This kind of request is always allowed';

  @override
  String get approvalRejected => 'Approval rejected';

  @override
  String get approvalCancelled => 'Approval cancelled';

  @override
  String get microphonePermissionMissing =>
      'This device does not have microphone permission';

  @override
  String recordingInitFailed(Object error) {
    return 'Recording init timed out or failed: $error';
  }

  @override
  String ttsFailed(Object error) {
    return 'TTS failed: $error';
  }

  @override
  String ttsInitFailed(Object error) {
    return 'TTS init timed out or failed: $error';
  }

  @override
  String get reinitializingRecording => 'Reinitializing recording...';

  @override
  String get recordingInProgress =>
      'Recording. Tap once to stop and transcribe...';

  @override
  String startRecordingFailed(Object error) {
    return 'Failed to start recording: $error';
  }

  @override
  String stopRecordingFailed(Object error) {
    return 'Failed to stop recording: $error';
  }

  @override
  String get uploadingAudio => 'Uploading audio and transcribing...';

  @override
  String get recordingFileMissing => 'No recording file was produced';

  @override
  String get voiceTranscriptionComplete => 'Voice transcription complete';

  @override
  String voiceTranscriptionFailed(Object error) {
    return 'Voice transcription failed: $error';
  }

  @override
  String get reinitializingTts => 'Reinitializing TTS...';

  @override
  String get requestingTts => 'Requesting TTS playback...';

  @override
  String ttsPlaybackFailed(Object error) {
    return 'TTS playback failed: $error';
  }

  @override
  String get sessionStillCreating =>
      'The session is still being created. Please wait.';

  @override
  String get sessionStillRunning =>
      'This session is still processing. Wait for this turn to finish before sending again.';

  @override
  String get messageInputRequired =>
      'Enter text or use voice recognition first';

  @override
  String sendFailed(Object error) {
    return 'Send failed: $error';
  }

  @override
  String get replyStopped => 'Stopped this reply';

  @override
  String get allToolActivity => 'All tool activity';

  @override
  String get close => 'Close';

  @override
  String get toolActivityDetail => 'Tool activity detail';

  @override
  String get detailType => 'Type';

  @override
  String get detailPhase => 'Phase';

  @override
  String get detailContent => 'Content';

  @override
  String get detailItems => 'Items';

  @override
  String get detailExtra => 'Extra';

  @override
  String get detailRawContent => 'Raw content';

  @override
  String get toolKindCommand => 'Command';

  @override
  String get toolKindFile => 'File change';

  @override
  String get toolKindTodo => 'Todo';

  @override
  String get toolKindPlan => 'Plan';

  @override
  String get toolKindSearch => 'Search';

  @override
  String get toolKindFetch => 'Fetch';

  @override
  String get toolKindReasoning => 'Reasoning';

  @override
  String get toolKindThread => 'Thread status';

  @override
  String get toolKindTurn => 'Turn status';

  @override
  String get toolKindApproval => 'Approval';

  @override
  String get toolKindDebug => 'Debug event';

  @override
  String get toolPrimaryCommand => 'Command';

  @override
  String get toolSecondaryResult => 'Result';

  @override
  String toolExitCode(Object code) {
    return 'Exit code $code';
  }

  @override
  String get toolPrimaryFile => 'File';

  @override
  String get toolSecondaryOtherFiles => 'Other files';

  @override
  String toolMoreFiles(Object count) {
    return '$count more files not expanded';
  }

  @override
  String get toolPrimaryTodoItems => 'Items';

  @override
  String get toolSecondaryOtherItems => 'Other items';

  @override
  String get toolPrimarySteps => 'Steps';

  @override
  String get toolSecondaryOtherSteps => 'Other steps';

  @override
  String get toolPrimaryIdentifier => 'Identifier';

  @override
  String get toolSecondaryDetail => 'Detail';

  @override
  String get phaseRunning => 'Running';

  @override
  String get phaseCompleted => 'Completed';

  @override
  String get phaseStarted => 'Started';

  @override
  String get draftPending => 'Pending sync';

  @override
  String get draftFailed => 'Send failed, tap to retry';

  @override
  String get whisperApiKeyRequired =>
      'Fill in the Whisper/OpenAI API key in settings first';

  @override
  String whisperAsrRequestFailed(Object statusCode, Object body) {
    return 'Whisper ASR request failed ($statusCode): $body';
  }

  @override
  String get whisperAsrMissingText => 'Whisper ASR response is missing text';

  @override
  String get updateManifestUrlRequired => 'Enter the manifest URL first';

  @override
  String get updateManifestUrlInvalid => 'Manifest URL is invalid';

  @override
  String updateCheckHttpFailed(Object statusCode) {
    return 'Update check failed: HTTP $statusCode';
  }

  @override
  String get updateManifestMustBeJson =>
      'Update manifest must be a JSON object';

  @override
  String updateCheckFailed(Object error) {
    return 'Update check failed: $error';
  }

  @override
  String get apkUrlInvalid => 'APK download URL is invalid';

  @override
  String apkDownloadHttpFailed(Object statusCode) {
    return 'APK download failed: HTTP $statusCode';
  }

  @override
  String get cannotOpenInstaller => 'Unable to open system installer';

  @override
  String get updateManifestMissingVersionName =>
      'Update manifest is missing version_name';

  @override
  String get updateManifestInvalidVersionCode =>
      'Update manifest version_code is invalid';

  @override
  String get updateManifestMissingApkUrl =>
      'Update manifest is missing apk_url or apk_urls';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get waitingApprovalTitle => 'Waiting for approval';

  @override
  String get waitingApprovalBody =>
      'Approve this request on the Bridge host. The app continues automatically after approval.';

  @override
  String get waitingApprovalInstallHint =>
      'If the Bridge service is not running yet, download it from GitHub and start it first.';

  @override
  String get waitingApprovalDownloadBridge =>
      'Download Bridge service on GitHub';

  @override
  String get waitingApprovalRunCommand =>
      'Run this command on the Bridge host:';

  @override
  String get waitingApprovalRequestAgain => 'Request again';

  @override
  String voiceInputInitFailed(Object error) {
    return 'Voice input init timed out or failed: $error';
  }

  @override
  String startVoiceInputFailed(Object error) {
    return 'Failed to start voice input: $error';
  }

  @override
  String stopVoiceInputFailed(Object error) {
    return 'Failed to stop voice input: $error';
  }

  @override
  String get voiceInputInProgress =>
      'Listening. Tap once to stop and transcribe...';

  @override
  String get reinitializingVoiceInput => 'Reinitializing voice input...';

  @override
  String get voiceTranscriptionNoResult => 'No speech was recognized';

  @override
  String get speechSystem => 'System';

  @override
  String get omniBridgeLocal => 'Omni Bridge Local';

  @override
  String get refresh => 'Refresh';

  @override
  String get refreshing => 'Refreshing...';

  @override
  String get clear => 'Clear';

  @override
  String get speechSystemPreferredHelp =>
      'System is used by default when available. Switch to cloud providers if you need a fallback.';

  @override
  String get systemTtsUnavailableOnLinux =>
      'System TTS is not available on Linux yet. Choose a cloud provider to enable playback.';

  @override
  String get systemAsrUnavailableOnLinux =>
      'System ASR is not available on Linux yet. Choose a cloud provider to enable voice input.';

  @override
  String get systemAsrMacosPermissionHint =>
      'System ASR on macOS requires microphone and speech recognition permissions.';

  @override
  String get systemSpeechUnavailable =>
      'System speech is unavailable on this device. Switch providers in Settings to use cloud speech.';

  @override
  String get localBridgeSpeechSection => 'Local Bridge Speech';

  @override
  String get localBridgeModelsSection => 'Local Bridge Models';

  @override
  String get localBridgeSpeechIntro =>
      'Use the local Bridge to run offline ASR, TTS, VAD, and model downloads on your own machine.';

  @override
  String get localBridgeModelsUnavailable =>
      'Local Bridge model status has not loaded yet.';

  @override
  String get bridgeDetails => 'Bridge details';

  @override
  String get localBridgeModelRoot => 'Model root';

  @override
  String get localBridgeDownloadTasksSection => 'Download tasks';

  @override
  String get localBridgeNoCompatibleModels =>
      'No compatible models are available for this type yet.';

  @override
  String get localBridgeTtsVoiceLabel => 'TTS voice';

  @override
  String get localBridgeTtsVoiceField => 'Voice';

  @override
  String get localBridgeTtsVoiceHelp =>
      'Used for local Bridge reply playback, auto-play, and call mode spoken replies.';

  @override
  String get localBridgeTtsStreamingLabel => 'Stream Bridge Local TTS';

  @override
  String get localBridgeTtsStreamingHelp =>
      'Starts playback while the local Bridge is still generating speech. Disable this if you prefer full audio to be generated before playback begins.';

  @override
  String localBridgeTtsVoiceOption(Object voice) {
    return 'Voice $voice';
  }

  @override
  String localBridgeTtsVoiceDefault(Object voice) {
    return 'Voice $voice (Default)';
  }

  @override
  String localBridgeTtsNamedVoiceDefault(Object voice) {
    return '$voice (Default)';
  }

  @override
  String localBridgeTtsVoiceId(Object voice) {
    return 'ID $voice';
  }

  @override
  String get speechVoiceLanguageChinese => 'Chinese';

  @override
  String get speechVoiceLanguageEnglish => 'English';

  @override
  String get speechVoiceLanguageChineseEnglish => 'Chinese + English';

  @override
  String get speechVoiceLanguageJapanese => 'Japanese';

  @override
  String get speechVoiceLanguageSpanish => 'Spanish';

  @override
  String get speechVoiceLanguageFrench => 'French';

  @override
  String get speechVoiceLanguageHindi => 'Hindi';

  @override
  String get speechVoiceLanguageItalian => 'Italian';

  @override
  String get speechVoiceLanguagePortugueseBr => 'Portuguese (BR)';

  @override
  String get speechVoiceLanguageUnknown => 'Unknown language';

  @override
  String get speechVoiceAccentAmericanEnglish => 'American English';

  @override
  String get speechVoiceAccentBritishEnglish => 'British English';

  @override
  String get speechVoiceAccentBrazilianPortuguese => 'Brazilian Portuguese';

  @override
  String get speechVoiceGenderFemale => 'Female';

  @override
  String get speechVoiceGenderMale => 'Male';

  @override
  String get whisperApiSection => 'Whisper API';

  @override
  String get bridgeLocalTtsHelp =>
      'Uses the bridge-local /v1/audio/speech endpoint and the selected TTS model below.';

  @override
  String get bridgeLocalAsrHelp =>
      'Uses the bridge-local /v1/audio/transcriptions endpoint for recorded voice input.';

  @override
  String get whisperApiHelp =>
      'Requires a Whisper-compatible base URL and API key.';

  @override
  String get speechNotSelected => 'Not selected';

  @override
  String get speechInstalled => 'Installed';

  @override
  String get speechNotInstalled => 'Not installed';

  @override
  String get speechDownload => 'Download';

  @override
  String get speechDownloading => 'Downloading...';

  @override
  String get speechDelete => 'Delete';

  @override
  String get speechInstalledModels => 'Installed models';

  @override
  String get speechNoInstalledModels => 'No installed models yet.';

  @override
  String get speechSelect => 'Select';

  @override
  String get speechChange => 'Change';

  @override
  String get speechSelected => 'Selected';

  @override
  String get speechModelKindAsr => 'ASR';

  @override
  String get speechModelKindTts => 'TTS';

  @override
  String get speechModelKindVad => 'VAD';

  @override
  String get speechRuntimeStreaming => 'Streaming';

  @override
  String get speechRuntimeOffline => 'Offline';

  @override
  String get speechProfileBatchAsrTitle => 'Batch ASR';

  @override
  String get speechProfileBatchAsrHelp =>
      'Used for recorded voice transcription. Pick this when you want accurate transcription after the user finishes speaking.';

  @override
  String get speechProfileBatchAsrAction => 'Use for Batch ASR';

  @override
  String get speechProfileRealtimeAsrTitle => 'Realtime ASR';

  @override
  String get speechProfileRealtimeAsrHelp =>
      'Used by call mode and realtime websocket transcription. Pick this when you need partial transcripts while the user is still speaking.';

  @override
  String get speechProfileRealtimeAsrAction => 'Use for Realtime ASR';

  @override
  String get speechProfileTtsTitle => 'TTS';

  @override
  String get speechProfileTtsHelp =>
      'Used for spoken reply playback from the local Bridge. Pick this when you want the assistant to speak through a local model.';

  @override
  String get speechProfileTtsAction => 'Use for TTS';

  @override
  String get speechProfileVadTitle => 'VAD';

  @override
  String get speechProfileVadHelp =>
      'Used to detect when speech starts and ends in realtime mode. Pick this when you want faster turn-taking and cleaner cutoffs.';

  @override
  String get speechProfileVadAction => 'Use for VAD';

  @override
  String get speechProfileWakeWordTitle => 'Wake word';

  @override
  String get speechProfileWakeWordHelp =>
      'Used by Omni Bridge Local to detect the wake word before accepting realtime call-mode speech.';

  @override
  String get speechProfileWakeWordAction => 'Use for Wake word';

  @override
  String get speechDownloadStatusQueued => 'Queued';

  @override
  String get speechDownloadStatusDownloading => 'Downloading';

  @override
  String get speechDownloadStatusExtracting => 'Extracting';

  @override
  String get speechDownloadStatusVerifying => 'Verifying';

  @override
  String get speechDownloadStatusCompleted => 'Completed';

  @override
  String get speechDownloadStatusFailed => 'Failed';

  @override
  String speechActiveDownloadsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count active downloads',
      one: '1 active download',
    );
    return '$_temp0';
  }

  @override
  String speechDownloadProgressPercent(int percent) {
    return '$percent% complete';
  }

  @override
  String speechLocalModelsLoadFailed(Object error) {
    return 'Unable to load local speech models: $error';
  }

  @override
  String speechModelDownloadFailed(Object modelId, Object error) {
    return 'Download failed for $modelId: $error';
  }

  @override
  String speechProfileUpdateFailed(Object profile, Object error) {
    return 'Failed to update $profile: $error';
  }

  @override
  String get appDownloadSection => 'App Download';

  @override
  String get appDownloadHelp => 'Download the latest release from GitHub.';

  @override
  String get openGithubReleases => 'Open GitHub Releases';

  @override
  String get signOut => 'Sign out';

  @override
  String get signOutConfirmTitle => 'Sign out and reauthorize?';

  @override
  String get signOutConfirmBody =>
      'This clears the current device authorization and returns you to the welcome screen. You will need to reconnect Bridge and authorize this device again.';

  @override
  String get sessionFailedGeneric => 'Session failed';
}
