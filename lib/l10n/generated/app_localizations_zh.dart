// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Omni Code';

  @override
  String get settingsTitle => '设置';

  @override
  String get save => '保存';

  @override
  String get saving => '保存中...';

  @override
  String get systemSection => '系统';

  @override
  String get languageSection => '语言';

  @override
  String get languageLabel => '应用语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => '中文';

  @override
  String get bridgeSection => 'Bridge';

  @override
  String get bridgeUrlLabel => 'Bridge 地址';

  @override
  String get bridgeHelp =>
      '真机通过 adb reverse 时可直接用 127.0.0.1:8787；局域网访问时填电脑 IP。服务端可按 token 和 client id 放行。';

  @override
  String get appUpdateSection => 'App 更新';

  @override
  String get updateManifestUrlLabel => '更新清单 URL';

  @override
  String get updateTargetVersionLabel => '目标版本号';

  @override
  String get updateTargetVersionHelp =>
      '可选。填写如 0.2.1 这样的版本号后，会下载对应 GitHub Release，而不是最新版本。';

  @override
  String get checkingUpdate => '检查中...';

  @override
  String get checkAppUpdate => '检查 App 更新';

  @override
  String get updateHelp =>
      '默认从官方 GitHub Release 的更新清单检查新版本。你也可以手动填写自定义清单 URL，包括自托管 Bridge 的 manifest。发现新版本后会打开下载链接，由系统完成安装。';

  @override
  String get speechSection => '语音服务';

  @override
  String get ttsProviderLabel => 'TTS Provider';

  @override
  String get asrProviderLabel => 'ASR Provider';

  @override
  String get bridgeCloudProxy => 'Bridge / 云端中转';

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
  String get aiApprovalSection => 'AI 审批';

  @override
  String get enableAiApproval => '启用 AI 辅助审批';

  @override
  String get enableAiApprovalSubtitle => '使用已配置的模型判断低风险命令';

  @override
  String get aiApprovalModel => '审批模型';

  @override
  String get aiApprovalProvider => '审批模型服务';

  @override
  String get loadingApprovalModels => '正在加载模型...';

  @override
  String get approvalModelsLoadFailed => '无法获取模型，已显示配置中的默认值';

  @override
  String get noApprovalModels => '该模型服务没有返回可用模型';

  @override
  String get loadingModelProviders => '正在加载已配置模型...';

  @override
  String get noConfiguredModels => '请先配置并启用一个模型服务';

  @override
  String get modelProvidersLoadFailed => '无法加载已配置模型';

  @override
  String get selectAiApprovalModel => '请选择审批模型';

  @override
  String get aiApprovalMaxRisk => '自动放行最高风险';

  @override
  String get aiApprovalHelp =>
      '保存后会同步到当前 Bridge。建议保持 Low；高风险、调用失败或命中硬阻断规则仍会回退到手机人工审批。';

  @override
  String get aiApprovalPrompt => '全局审批 Prompt';

  @override
  String get aiApprovalPromptHint => '添加适用于所有项目的审批判断规则';

  @override
  String get aiApprovalPromptEntrySubtitle => '修改自动审批判断使用的指令';

  @override
  String get projectAiApprovalPrompt => '项目级审批 Prompt';

  @override
  String get projectAiApprovalPromptHint => '添加仅适用于当前项目的审批判断规则';

  @override
  String get alwaysAllowedCommands => '始终允许的命令';

  @override
  String get alwaysAllow => '总是允许';

  @override
  String get autoApprovalAiReviewTitle => 'AI 建议由你确认';

  @override
  String get autoApprovalRiskThresholdTitle => '风险超过自动审批范围';

  @override
  String get autoApprovalHardBlockTitle => '命中安全阻断规则';

  @override
  String get autoApprovalReviewFailedTitle => '自动审批暂时不可用';

  @override
  String get autoApprovalHardBlockReason => '该命令会影响受保护或项目范围外的资源，需要由你确认。';

  @override
  String get autoApprovalReviewFailedReason => '审批模型未能完成判断，因此这次交由你确认。';

  @override
  String get projectApprovalSettingsSaved => '项目审批设置已保存';

  @override
  String get riskLow => 'Low';

  @override
  String get riskMedium => 'Medium';

  @override
  String get riskHigh => 'High';

  @override
  String get autoSpeakReplies => '自动播报 Agent 回复';

  @override
  String get autoSpeakRepliesSubtitle => 'AI 回复完成后自动开始播报';

  @override
  String get speechPlaybackPrompt => '为语音播报优化回复';

  @override
  String get speechPlaybackPromptSubtitle =>
      '当回复会被朗读时，提醒 Agent 避免返回不适合朗读的内容；如果你明确要求，仍会返回。';

  @override
  String get compressReplies => '压缩 AI 回复';

  @override
  String get compressRepliesSubtitle => '开启后，新建会话会要求 AI 简短说明做了什么';

  @override
  String get compressReplyMaxChars => '压缩回复最大字数';

  @override
  String get settingsSaved => '设置已保存';

  @override
  String settingsSaveFailed(Object error) {
    return '保存设置失败：$error';
  }

  @override
  String alreadyLatestVersion(Object version) {
    return '已是最新版本：$version';
  }

  @override
  String newVersionFound(Object versionName) {
    return '发现新版本 $versionName';
  }

  @override
  String targetVersionReady(Object versionName) {
    return '版本 $versionName 已可下载';
  }

  @override
  String targetVersionNotFound(Object version) {
    return '未找到或无法下载版本 $version';
  }

  @override
  String get targetVersionDowngradeWarning =>
      '如果这是比当前已安装版本更旧的包，Android 可能会拦截降级安装。';

  @override
  String currentVersion(Object version) {
    return '当前版本：$version';
  }

  @override
  String get later => '稍后';

  @override
  String get updateNow => '立即更新';

  @override
  String get downloadingUpdate => '正在下载更新';

  @override
  String downloadedBytes(Object received) {
    return '已下载 $received';
  }

  @override
  String downloadProgress(Object received, Object total) {
    return '$received / $total';
  }

  @override
  String get homeManageByProject => '按项目管理 Codex';

  @override
  String homeBridgeAddress(Object address) {
    return '当前 bridge 地址：$address';
  }

  @override
  String get homeIntro => '先进入项目，再选择已有会话或在该项目下新开 Codex 会话。';

  @override
  String get projectsTitle => '项目';

  @override
  String get selectProject => '选择项目';

  @override
  String get createProject => '创建项目';

  @override
  String get createNewProject => '创建新项目';

  @override
  String get newProject => '新建项目';

  @override
  String get retry => '重试';

  @override
  String get editMessage => '编辑';

  @override
  String get withdrawMessage => '撤回';

  @override
  String projectCount(int count) {
    return '$count 个会话';
  }

  @override
  String sessionCount(int count) {
    return '$count 个会话';
  }

  @override
  String projectsCount(int count) {
    return '$count 个项目';
  }

  @override
  String projectUpdatedAt(Object time) {
    return '最近更新 $time';
  }

  @override
  String loadProjectsFailed(Object error) {
    return '加载项目失败：$error';
  }

  @override
  String get noProjectsYet => '当前没有项目';

  @override
  String get noProjectsHelp => '先创建一个项目，填写本机代码目录，然后在项目内新开或恢复 Codex 会话。';

  @override
  String get projectName => '项目名';

  @override
  String get localPath => '本机目录路径';

  @override
  String get cancel => '取消';

  @override
  String get projectIntro => '进入任一会话即可继续历史上下文，也可以在当前项目下创建一个新的 Codex 会话。';

  @override
  String get homePrompt => '远程代理控制台';

  @override
  String get homeCreateProjectHint => '添加本地代码目录';

  @override
  String get homeBrowseProjects => '浏览全部';

  @override
  String get searchSessions => '搜索会话标题或摘要';

  @override
  String get searchProjects => '搜索项目名或路径';

  @override
  String get noSearchResultsTitle => '没有匹配结果';

  @override
  String get noSearchResultsBody => '换一个项目名、路径、会话标题或摘要再试试。';

  @override
  String get themeSection => '主题';

  @override
  String get themeFollowSystem => '跟随系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get sessionsTitle => '最近';

  @override
  String get recentSessionsTitle => '最近会话';

  @override
  String loadSessionsFailed(Object error) {
    return '加载会话失败：$error';
  }

  @override
  String sessionUpdatedAtWithAgent(Object agent, Object time) {
    return '$agent · 最近更新 $time';
  }

  @override
  String forkedFromSession(Object source) {
    return 'Fork 来源：$source';
  }

  @override
  String loadMoreSessions(int count) {
    return '加载更多 ($count 条)';
  }

  @override
  String get loadMoreSessionsLabel => '加载更多';

  @override
  String get newSession => '新会话';

  @override
  String get sessionStatusIdle => '空闲';

  @override
  String get sessionStatusRunning => '回复中';

  @override
  String get sessionStatusAwaitingApproval => '待审批';

  @override
  String get sessionStatusInterrupted => '已中断';

  @override
  String get sessionStatusWaiting => '等待中';

  @override
  String get sessionStatusFailed => '失败';

  @override
  String get noSessionsYet => '当前项目还没有会话';

  @override
  String get noSessionsHelp => '新开一个 Codex 会话后，后续可以回到这个项目继续进入同一条历史会话。';

  @override
  String get noSessionsMatched => '没有匹配的会话，换个关键词试试。';

  @override
  String get sessionTitleOptional => '会话标题（可选）';

  @override
  String get agentLabel => 'Agent';

  @override
  String get agentInstalledStatus => '已安装';

  @override
  String get agentNotInstalledStatus => '未安装';

  @override
  String get installAgent => '安装 Agent';

  @override
  String get installingAgent => '安装中...';

  @override
  String get create => '创建';

  @override
  String get creatingSession => '正在创建会话...';

  @override
  String get waitingApprovalProcessing => '正在等待审批处理...';

  @override
  String get waitingApprovalListening => '正在等待批准...';

  @override
  String get connectHeader => '连接 Bridge';

  @override
  String get connectPrompt => '先连接 Bridge 再开始。';

  @override
  String get connectWelcomeTitle => '欢迎使用 Omni Code';

  @override
  String get connectWelcomeBody => '先在电脑上运行 Bridge 服务，然后授权此设备，以便打开项目并继续会话。';

  @override
  String get connectBridgeHint => '如果手机和电脑在同一个局域网，请使用电脑 IP。';

  @override
  String get connectDownloadTitle => '下载 Bridge 服务';

  @override
  String get connectDownloadBody => '请在托管本地项目的电脑上，从 GitHub 获取该服务。';

  @override
  String get connectDownloadRepo =>
      'github.com/omni-stream-ai/omni-code-bridge';

  @override
  String get authorizeThisDevice => '授权当前设备';

  @override
  String get connectNextStep => '下一步：审批页';

  @override
  String get backToWelcome => '返回欢迎页';

  @override
  String get waitingApprovalHeader => '授权';

  @override
  String get waitingApprovalHeaderSubtitle => '在 Bridge 主机上批准此设备。';

  @override
  String get turnPausedWaiting => '本轮已暂停，正在等待后续结果...';

  @override
  String get speechReadyStatus => '录音转写已就绪';

  @override
  String get waitingProcessApproval => '等待处理审批...';

  @override
  String get stopReply => '停止回答';

  @override
  String get messageInputHint => '输入任务，例如：帮我检查最近一次构建失败原因';

  @override
  String get stopVoice => '停止语音';

  @override
  String get voiceInput => '语音输入';

  @override
  String get keyboardInput => '键盘输入';

  @override
  String get voiceHoldToTalk => '按住说话';

  @override
  String get voiceHoldRecording => '正在聆听...';

  @override
  String get voiceHoldSlideUpHint => '上滑可转文字或取消';

  @override
  String get voiceHoldReleaseHint => '左侧松手转文字，右侧松手取消';

  @override
  String get voiceHoldReleaseToText => '转文字';

  @override
  String get voiceHoldReleaseCancel => '取消';

  @override
  String get voiceChatTitle => '通话模式';

  @override
  String get callModeListening => '可以开始说了，我正在听';

  @override
  String get callModePreparingListening => '正在准备麦克风';

  @override
  String get callModeSpeaking => '正在语音回复';

  @override
  String get callModeWorking => '正在思考你的请求';

  @override
  String get callModeIdleSubtitle => '直接说就行，我会自动听、自动发、再把回复念给你。';

  @override
  String get callModePreparingListeningLabel => '正在准备监听';

  @override
  String get callModePreparingListeningDetail => '麦克风和语音识别正在启动，这时说话可能还不会被捕获。';

  @override
  String get callModeListeningReadyLabel => '正在监听';

  @override
  String get callModeListeningReadyDetail => '可以直接开始说，识别内容会实时显示在这里。';

  @override
  String get callModeWaitingWakeWordLabel => '等待唤醒词';

  @override
  String get callModeWaitingWakeWordDetail => '请把设置里的唤醒词放在这句话的开头或结尾，中间命中会被忽略。';

  @override
  String get callModeWakeWordDetectedLabel => '已检测到唤醒词';

  @override
  String get callModeWakeWordDetectedDetail => '在呢。下一句话会被识别并发送。';

  @override
  String get callModeWakeWordAck => '在呢';

  @override
  String get callModeCommandAccepted => '让我思考一下';

  @override
  String callModeRejectedSpeakerTranscript(String transcript) {
    return '$transcript（非指定说话人）';
  }

  @override
  String callModeRejectedWakeWordTranscript(String transcript) {
    return '$transcript（未匹配唤醒词）';
  }

  @override
  String get callModeSpeechDetectedLabel => '检测到你在说话';

  @override
  String get callModeSpeechDetectedDetail => '继续自然说下去，系统会持续补全这句内容。';

  @override
  String get callModeWaitingForPauseLabel => '等待你这句话结束';

  @override
  String get callModeWaitingForPauseDetail => '你停顿一会儿后，这句会自动发送，无需手动点按钮。';

  @override
  String get callModeOpenChatHistory => '查看对话记录';

  @override
  String get showCallModeSubtitles => '显示字幕';

  @override
  String get hideCallModeSubtitles => '隐藏字幕';

  @override
  String get startCallMode => '开启通话模式';

  @override
  String get stopCallMode => '停止通话模式';

  @override
  String get callModeUnavailable => '语音服务尚未初始化完成，暂时无法使用通话模式。';

  @override
  String get callModeRequiresStreamingAsr =>
      '通话模式需要 Omni Bridge Local 或实时 ASR 插件。';

  @override
  String get callModeSection => '通话模式';

  @override
  String get callModeAllowInterruptionsLabel => '允许说话打断回复';

  @override
  String get callModeAllowInterruptionsHelp =>
      '开启后，通话模式下如果你在回复播报过程中再次开口，会停止当前语音回复并接管这一轮。';

  @override
  String get callModeSpeechPauseLabel => '停顿判定时长';

  @override
  String get callModeSpeechPauseHelp =>
      '检测到静音后，等待多少毫秒自动发送当前这句。建议范围：600-2400 ms。';

  @override
  String callModeSpeechPauseRangeError(int min, int max) {
    return '请输入 $min-$max ms 之间的数值。';
  }

  @override
  String get callModeSpeechPauseBridgeOnlyHint =>
      '这个停顿时长目前会精确作用在 Omni Bridge Local 的实时通话模式上。其他 ASR 提供方可能仍使用各自内置的停顿策略。';

  @override
  String get callModeWakeWordLabel => '需要唤醒词';

  @override
  String get callModeWakeWordHelp =>
      '开启后，Omni Bridge Local 会先用本地关键词检测器识别唤醒词，再处理实时语音。不支持的短语会返回配置错误。';

  @override
  String get callModeWakeWordsLabel => '唤醒词';

  @override
  String get callModeWakeWordsHelp =>
      '多个短语用逗号分隔。支持英文短语和数字声调拼音，例如 ou1 mi3，会自动转换为模型 token；不支持直接输入汉字。';

  @override
  String get callModeWakeWordsEmptyError => '请至少输入一个唤醒词。';

  @override
  String callModeWakeWordsUnsupportedError(String wakeWord, String example) {
    return '本地唤醒词模型不支持“$wakeWord”。请使用英文短语、数字声调拼音或模型 token 序列，例如“$example”。';
  }

  @override
  String get callModeWakeWordModelUnsupported => '当前语音模型不支持唤醒词，已自动关闭唤醒词功能。';

  @override
  String get send => '发送';

  @override
  String get imageAttachment => '上传文件或图片';

  @override
  String get previewImage => '预览';

  @override
  String get imagePreviewTitle => '图片预览';

  @override
  String get imagePreviewLoadFailed => '加载图片预览失败';

  @override
  String get imagePreviewBgDark => '深色';

  @override
  String get imagePreviewBgLight => '浅色';

  @override
  String get imagePreviewBgChecker => '棋盘格';

  @override
  String agentAwaitingPermission(Object agent) {
    return '$agent 等待权限确认';
  }

  @override
  String get desktopOnlyApproval => '这个请求当前只能在桌面端处理。';

  @override
  String get approve => '允许';

  @override
  String get approveForSession => '本会话允许';

  @override
  String get reject => '拒绝';

  @override
  String get processing => '处理中...';

  @override
  String get toolActivity => '工具过程';

  @override
  String get working => '工作中...';

  @override
  String get stopPlayback => '停止播报';

  @override
  String get playback => '播报';

  @override
  String createSessionFailed(Object error) {
    return '创建会话失败：$error';
  }

  @override
  String loadMessagesFailed(Object error) {
    return '加载消息失败：$error';
  }

  @override
  String restoreSessionFailed(Object error) {
    return '恢复会话失败：$error';
  }

  @override
  String approvalSubmitFailed(Object error) {
    return '审批提交失败：$error';
  }

  @override
  String get approvalAccepted => '审批已允许';

  @override
  String get approvalAcceptedForSession => '当前会话已允许后续同类请求';

  @override
  String get approvalAlwaysAllow => '已永久允许此类请求';

  @override
  String get approvalRejected => '审批已拒绝';

  @override
  String get approvalCancelled => '审批已取消';

  @override
  String get microphonePermissionMissing => '当前设备没有录音权限';

  @override
  String recordingInitFailed(Object error) {
    return '录音初始化超时或失败：$error';
  }

  @override
  String ttsFailed(Object error) {
    return 'TTS 失败：$error';
  }

  @override
  String ttsInitFailed(Object error) {
    return 'TTS 初始化超时或失败：$error';
  }

  @override
  String get reinitializingRecording => '正在重新初始化录音...';

  @override
  String get recordingInProgress => '正在录音，点击一次停止并转写...';

  @override
  String startRecordingFailed(Object error) {
    return '启动录音失败：$error';
  }

  @override
  String stopRecordingFailed(Object error) {
    return '停止录音失败：$error';
  }

  @override
  String get uploadingAudio => '正在上传音频并转写...';

  @override
  String get recordingFileMissing => '没有拿到录音文件';

  @override
  String get voiceTranscriptionComplete => '语音转写完成';

  @override
  String voiceTranscriptionFailed(Object error) {
    return '语音转写失败：$error';
  }

  @override
  String get reinitializingTts => '正在重新初始化 TTS...';

  @override
  String get requestingTts => '正在请求 TTS 播报...';

  @override
  String ttsPlaybackFailed(Object error) {
    return 'TTS 播报失败：$error';
  }

  @override
  String get sessionStillCreating => '会话还在创建中，请稍候';

  @override
  String get sessionStillRunning => '当前会话还在处理中，请等这一轮结束后再发送';

  @override
  String get messageInputRequired => '请先输入内容或使用语音识别';

  @override
  String sendFailed(Object error) {
    return '发送失败：$error';
  }

  @override
  String get replyStopped => '已停止本次回答';

  @override
  String get allToolActivity => '全部工具过程';

  @override
  String get close => '关闭';

  @override
  String get toolActivityDetail => '工具过程详情';

  @override
  String get detailType => '类型';

  @override
  String get detailPhase => '阶段';

  @override
  String get detailContent => '内容';

  @override
  String get detailItems => '条目';

  @override
  String get detailExtra => '补充';

  @override
  String get detailRawContent => '原始内容';

  @override
  String get toolKindCommand => '命令';

  @override
  String get toolKindFile => '文件变更';

  @override
  String get toolKindTodo => 'Todo';

  @override
  String get toolKindPlan => '计划';

  @override
  String get toolKindSearch => '搜索';

  @override
  String get toolKindFetch => '抓取';

  @override
  String get toolKindReasoning => '推理';

  @override
  String get toolKindThread => '线程状态';

  @override
  String get toolKindTurn => '轮次状态';

  @override
  String get toolKindApproval => '审批';

  @override
  String get toolKindDebug => '调试事件';

  @override
  String get toolPrimaryCommand => '命令';

  @override
  String get toolSecondaryResult => '结果';

  @override
  String toolExitCode(Object code) {
    return '退出码 $code';
  }

  @override
  String get toolPrimaryFile => '文件';

  @override
  String get toolSecondaryOtherFiles => '其他文件';

  @override
  String toolMoreFiles(Object count) {
    return '还有 $count 个文件未展开';
  }

  @override
  String get toolPrimaryTodoItems => '条目';

  @override
  String get toolSecondaryOtherItems => '其他条目';

  @override
  String get toolPrimarySteps => '步骤';

  @override
  String get toolSecondaryOtherSteps => '其他步骤';

  @override
  String get toolPrimaryIdentifier => '标识';

  @override
  String get toolSecondaryDetail => '详情';

  @override
  String get phaseRunning => '进行中';

  @override
  String get phaseCompleted => '已完成';

  @override
  String get phaseStarted => '已开始';

  @override
  String get draftPending => '待同步';

  @override
  String get draftFailed => '发送失败，点击重发';

  @override
  String get whisperApiKeyRequired => '请先在设置中填写 Whisper/OpenAI API Key';

  @override
  String whisperAsrRequestFailed(Object statusCode, Object body) {
    return 'Whisper ASR 请求失败 ($statusCode): $body';
  }

  @override
  String get whisperAsrMissingText => 'Whisper ASR 响应缺少 text';

  @override
  String get updateManifestUrlRequired => '请先填写更新清单 URL';

  @override
  String get updateManifestUrlInvalid => '更新清单 URL 无效';

  @override
  String updateCheckHttpFailed(Object statusCode) {
    return '更新检查失败：HTTP $statusCode';
  }

  @override
  String get updateManifestMustBeJson => '更新清单必须是 JSON 对象';

  @override
  String updateCheckFailed(Object error) {
    return '更新检查失败：$error';
  }

  @override
  String get apkUrlInvalid => 'APK 下载地址无效';

  @override
  String apkDownloadHttpFailed(Object statusCode) {
    return 'APK 下载失败：HTTP $statusCode';
  }

  @override
  String get cannotOpenInstaller => '无法打开系统安装器';

  @override
  String get updateManifestMissingVersionName => '更新清单缺少 version_name';

  @override
  String get updateManifestInvalidVersionCode => '更新清单 version_code 无效';

  @override
  String get updateManifestMissingApkUrl => '更新清单缺少 apk_url 或 apk_urls';

  @override
  String get copy => '复制';

  @override
  String get copied => '已复制';

  @override
  String get waitingApprovalTitle => '等待批准';

  @override
  String get waitingApprovalBody => '请在 Bridge 主机上批准这次请求。批准后应用会自动继续。';

  @override
  String get waitingApprovalInstallHint => '如果 Bridge 服务尚未运行，请先从 GitHub 下载并启动。';

  @override
  String get waitingApprovalDownloadBridge => '在 GitHub 下载 Bridge 服务';

  @override
  String get waitingApprovalRunCommand => '在 Bridge 主机上运行此命令：';

  @override
  String get waitingApprovalRequestAgain => '重新请求';

  @override
  String voiceInputInitFailed(Object error) {
    return '语音输入初始化超时或失败：$error';
  }

  @override
  String startVoiceInputFailed(Object error) {
    return '启动语音输入失败：$error';
  }

  @override
  String stopVoiceInputFailed(Object error) {
    return '停止语音输入失败：$error';
  }

  @override
  String get voiceInputInProgress => '正在聆听。点击一次停止并转写...';

  @override
  String get reinitializingVoiceInput => '正在重新初始化语音输入...';

  @override
  String get voiceTranscriptionNoResult => '未识别到语音';

  @override
  String get speechSystem => '系统';

  @override
  String get omniBridgeLocal => 'Omni Bridge Local';

  @override
  String get refresh => '刷新';

  @override
  String get refreshing => '刷新中...';

  @override
  String get clear => '清除';

  @override
  String get speechSystemPreferredHelp => '系统可用时默认使用。如需备份可切换到云服务商。';

  @override
  String get systemTtsUnavailableOnLinux =>
      'Linux 系统 TTS 需要 speech-dispatcher（spd-say）或 espeak-ng。请安装后重试，或切换到云端服务商。';

  @override
  String get systemAsrUnavailableOnLinux =>
      'Linux 当前还不支持系统 ASR。请切换到云端服务商后再启用语音输入。';

  @override
  String get systemAsrMacosPermissionHint => 'macOS 的系统 ASR 需要麦克风和语音识别权限。';

  @override
  String get systemSpeechUnavailable => '当前设备不支持系统语音。请到设置中切换服务商后再使用云端语音。';

  @override
  String get localBridgeSpeechSection => '本地 Bridge 语音';

  @override
  String get localBridgeModelsSection => '本地 Bridge 模型';

  @override
  String get localBridgeSpeechIntro =>
      '通过本地 Bridge 在自己的机器上运行离线 ASR、TTS、VAD，并下载所需模型。';

  @override
  String get localBridgeModelsUnavailable => '本地 Bridge 模型状态尚未加载。';

  @override
  String get bridgeDetails => 'Bridge 详情';

  @override
  String get localBridgeModelRoot => '模型目录';

  @override
  String get localBridgeDownloadTasksSection => '下载任务';

  @override
  String get localBridgeTtsVoiceLabel => 'TTS 音色';

  @override
  String get localBridgeTtsVoiceField => '音色';

  @override
  String get localBridgeTtsVoiceHelp => '会用于本地 Bridge 的普通播报、自动播报和通话模式语音回复。';

  @override
  String get localBridgeTtsStreamingLabel => '流式播报本地 Bridge TTS';

  @override
  String get localBridgeTtsStreamingHelp =>
      '开启后，本地 Bridge 还在生成语音时就会开始播放。若你更希望先完整生成再播放，可以关闭它。';

  @override
  String localBridgeTtsVoiceOption(Object voice) {
    return '音色 $voice';
  }

  @override
  String localBridgeTtsVoiceDefault(Object voice) {
    return '音色 $voice（默认）';
  }

  @override
  String localBridgeTtsNamedVoiceDefault(Object voice) {
    return '$voice（默认）';
  }

  @override
  String localBridgeTtsVoiceId(Object voice) {
    return 'ID $voice';
  }

  @override
  String get speechVoiceLanguageChinese => '中文';

  @override
  String get speechVoiceLanguageEnglish => '英文';

  @override
  String get speechVoiceLanguageChineseEnglish => '中文 + 英文';

  @override
  String get speechVoiceLanguageJapanese => '日文';

  @override
  String get speechVoiceLanguageSpanish => '西班牙文';

  @override
  String get speechVoiceLanguageFrench => '法文';

  @override
  String get speechVoiceLanguageHindi => '印地文';

  @override
  String get speechVoiceLanguageItalian => '意大利文';

  @override
  String get speechVoiceLanguagePortugueseBr => '巴西葡萄牙文';

  @override
  String get speechVoiceLanguageUnknown => '未知语言';

  @override
  String get speechVoiceAccentAmericanEnglish => '美式英文';

  @override
  String get speechVoiceAccentBritishEnglish => '英式英文';

  @override
  String get speechVoiceAccentBrazilianPortuguese => '巴西葡萄牙文';

  @override
  String get speechVoiceGenderFemale => '女声';

  @override
  String get speechVoiceGenderMale => '男声';

  @override
  String get bridgeLocalTtsHelp =>
      '通过 bridge-local 的 /v1/audio/speech 接口和下方选中的 TTS 模型进行本地播报。';

  @override
  String get bridgeLocalAsrHelp =>
      '通过 bridge-local 的 /v1/audio/transcriptions 接口处理录音后的语音转写。';

  @override
  String get speechNotSelected => '未选择';

  @override
  String get speechInstalled => '已安装';

  @override
  String get speechNotInstalled => '未安装';

  @override
  String get speechDownload => '下载';

  @override
  String get speechDownloading => '下载中...';

  @override
  String get speechDelete => '删除';

  @override
  String get speechInstalledModels => '已安装模型';

  @override
  String get speechNoInstalledModels => '还没有已安装模型。';

  @override
  String get speechModelKindAsr => 'ASR';

  @override
  String get speechModelKindTts => 'TTS';

  @override
  String get speechModelKindVad => 'VAD';

  @override
  String get speechRuntimeStreaming => '流式';

  @override
  String get speechRuntimeOffline => '离线';

  @override
  String get speechProfileBatchAsrTitle => '批量 ASR';

  @override
  String get speechProfileRealtimeAsrTitle => '实时 ASR';

  @override
  String get speechProfileTtsTitle => 'TTS';

  @override
  String get speechDownloadStatusQueued => '排队中';

  @override
  String get speechDownloadStatusDownloading => '下载中';

  @override
  String get speechDownloadStatusExtracting => '解压中';

  @override
  String get speechDownloadStatusVerifying => '校验中';

  @override
  String get speechDownloadStatusCompleted => '已完成';

  @override
  String get speechDownloadStatusFailed => '失败';

  @override
  String speechActiveDownloadsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个下载任务进行中',
      one: '1 个下载任务进行中',
    );
    return '$_temp0';
  }

  @override
  String speechDownloadProgressPercent(int percent) {
    return '已完成 $percent%';
  }

  @override
  String speechLocalModelsLoadFailed(Object error) {
    return '加载本地语音模型失败：$error';
  }

  @override
  String speechModelDownloadFailed(Object modelId, Object error) {
    return '下载模型 $modelId 失败：$error';
  }

  @override
  String get appDownloadSection => '应用下载';

  @override
  String get appDownloadHelp => '从 GitHub 下载最新版本。';

  @override
  String get openGithubReleases => '打开 GitHub Releases';

  @override
  String get signOut => '退出';

  @override
  String get signOutConfirmTitle => '退出并重新授权？';

  @override
  String get signOutConfirmBody =>
      '退出后会清除当前设备授权并返回欢迎页。你需要重新连接 Bridge 并再次授权此设备。';

  @override
  String get sessionFailedGeneric => '会话已失败';

  @override
  String get modelProvidersSection => '模型供应商';

  @override
  String get modelProvidersHelp => '配置代理使用的模型供应商';

  @override
  String get addProvider => '添加供应商';

  @override
  String get editProvider => '编辑供应商';

  @override
  String get deleteProvider => '删除供应商';

  @override
  String get providerName => '名称';

  @override
  String get providerNameHint => '例如 My OpenAI';

  @override
  String get providerBaseUrl => '基础 URL';

  @override
  String get providerBaseUrlHint => '例如 https://api.openai.com/v1';

  @override
  String get providerApiKey => 'API 密钥';

  @override
  String get providerModel => '模型（可选）';

  @override
  String get providerModelHint => '留空使用默认值';

  @override
  String get providerFormat => 'API 格式';

  @override
  String get providerEnabled => '启用';

  @override
  String get providerPriority => '优先级';

  @override
  String get providerPriorityHelp => '数字越小优先级越高';

  @override
  String get providerAuto => '自动';

  @override
  String get providerDefault => '默认';

  @override
  String get providerOverride => '供应商覆盖';

  @override
  String get noProvidersYet => '尚未配置供应商';

  @override
  String get noProvidersHelp => '添加供应商以使用自定义 LLM 端点';

  @override
  String get providerSaved => '供应商已保存';

  @override
  String get providerDeleted => '供应商已删除';

  @override
  String get providerSessionLabel => '供应商';

  @override
  String get providerOverrideFailed => '供应商选择保存失败';

  @override
  String get reasoningEffortDefault => '默认';

  @override
  String get reasoningEffortLow => '低';

  @override
  String get reasoningEffortMedium => '中';

  @override
  String get reasoningEffortHigh => '高';

  @override
  String get reasoningEffortXhigh => '超高';

  @override
  String get reasoningEffortMax => '最高';

  @override
  String get reasoningEffortOverride => '思考强度';

  @override
  String get reasoningEffortSessionLabel => '思考强度';

  @override
  String get reasoningEffortOverrideFailed => '思考强度保存失败';

  @override
  String get modelDefault => '默认';

  @override
  String get modelSessionLabel => '模型';

  @override
  String get modelOverrideFailed => '模型选择保存失败';

  @override
  String copySessionId(Object agent) {
    return '复制 $agent ID';
  }

  @override
  String get copyResumeCommand => '复制 Resume 命令';

  @override
  String get desktopSessionOverview => '会话概览';

  @override
  String get desktopSessionOverviewSubtitle => '保持状态、上下文和操作可见，无需离开对话。';

  @override
  String get desktopSessionUpdated => '更新';

  @override
  String get desktopSessionStatus => '状态';

  @override
  String get confirm => '确认';

  @override
  String get fieldRequired => '此项为必填';

  @override
  String unknownRoute(Object route) {
    return '未知路由：$route';
  }

  @override
  String get recentProjectsTitle => '最近项目';

  @override
  String get more => '更多';

  @override
  String get subtitles => '字幕';

  @override
  String get stop => '停止';

  @override
  String get hold => '按住';

  @override
  String get microphone => '麦克风';

  @override
  String get end => '结束';

  @override
  String get openNavigation => '打开导航';

  @override
  String get providerOrder => '供应商顺序';

  @override
  String get configured => '已配置';

  @override
  String get enabled => '已启用';

  @override
  String get defaultLabel => '默认';

  @override
  String get none => '无';

  @override
  String get projectDesk => '项目工作台';

  @override
  String get allSessions => '全部会话';

  @override
  String get inMotion => '进行中';

  @override
  String get clearSearch => '清空搜索';

  @override
  String get projectContext => '项目上下文';

  @override
  String get rootPath => '根路径';

  @override
  String get branch => '分支';

  @override
  String get gitState => 'Git 状态';

  @override
  String get statusMix => '状态分布';

  @override
  String get approvals => '审批';

  @override
  String get notes => '备注';

  @override
  String get projectNotesNoActiveSessions => '当前还没有活跃会话。新建一个会话后，这个项目就会成为工作台。';

  @override
  String get projectNotesWaitingApproval => '有会话正在等待审批。建议先处理它们，再开始并行工作。';

  @override
  String get projectNotesActiveWork => '这个项目有正在进行的工作。保持最近会话简洁，方便快速浏览。';

  @override
  String get projectNotesQuiet => '当前会话状态较安静。可以在这里重启停滞的线程，或开始一次聚焦执行。';

  @override
  String get sessionOptions => '会话选项';

  @override
  String get collapseSessionDetails => '收起会话详情';

  @override
  String get customModel => '自定义模型';

  @override
  String get files => '文件';

  @override
  String get scrollToLatest => '滚动到最新';

  @override
  String get project => '项目';

  @override
  String get path => '路径';

  @override
  String get gitSnapshot => 'Git 快照';

  @override
  String get summary => '摘要';

  @override
  String get projectContextUnavailable => '项目上下文不可用。';

  @override
  String get clientId => '客户端 ID';

  @override
  String get replyBehaviorSection => '回复行为';

  @override
  String get currentVersionLabel => '当前版本';

  @override
  String get updateManifest => '更新清单';

  @override
  String get atAGlance => '概览';

  @override
  String get workspaceNote => '工作区备注';

  @override
  String get threads => '线程';

  @override
  String get active => '活跃';

  @override
  String get review => '待审';

  @override
  String get newLabel => '新建';

  @override
  String get inFocus => '焦点';

  @override
  String get upNext => '下一步';

  @override
  String threadsCount(int count) {
    return '$count 个线程';
  }

  @override
  String get nothingUrgentWaiting => '当前没有紧急等待项。';

  @override
  String visibleProjectsCount(int count) {
    return '$count 个可见';
  }

  @override
  String get authorizationNeeded => '需要授权';

  @override
  String connectedBridge(Object address) {
    return '已连接 • $address';
  }

  @override
  String get status => '状态';

  @override
  String get collapseStatus => '收起状态';

  @override
  String get pendingApprovals => '待审批';

  @override
  String waitingActionsNeedReview(int count) {
    return '$count 个等待操作需要审批';
  }

  @override
  String get noApprovalsWaiting => '当前没有等待审批的操作';

  @override
  String get bridgeStatus => 'Bridge 状态';

  @override
  String get voiceDevice => '语音 / 设备';

  @override
  String activeSessionsMicrophoneReady(int count) {
    return '$count 个活跃会话 • 麦克风就绪';
  }

  @override
  String get microphoneReadySystemSpeechAvailable => '麦克风就绪 • 系统语音可用';

  @override
  String get projectsOverview => '项目概览';

  @override
  String activeProjectsCount(int count) {
    return '$count 个活跃项目';
  }

  @override
  String get quickActions => '快捷操作';

  @override
  String get quickActionsBody => '打开项目或调整设置';

  @override
  String get pluginManifest => '插件清单';

  @override
  String get importLabel => '导入';

  @override
  String get systemDefault => '系统默认';

  @override
  String get systemDefaultCapabilitySubtitle => '使用此能力的内置行为。';

  @override
  String get chooseSpeechCapabilityProvider => '选择系统默认，或为这个能力选择一个插件。';

  @override
  String get savingPluginSettings => '正在保存插件设置...';

  @override
  String get savedToSettings => '已保存到设置。';

  @override
  String pluginSettingsSaveFailed(Object error) {
    return '保存插件设置失败。\n\n原始错误：\n$error';
  }

  @override
  String get fillRequiredPluginSettings => '使用此插件前，请先填写下方必填设置。';

  @override
  String get defaultTtsTestText => 'Hello from Omni Code speech settings.';

  @override
  String get systemTtsTestUnavailable => '当前平台无法测试系统 TTS。请选择一个 TTS 插件后在这里测试播放。';

  @override
  String get startingPlaybackTest => '正在开始播放测试...';

  @override
  String get playbackStartedSuccessfully => '播放已成功开始。';

  @override
  String get testTts => '测试 TTS';

  @override
  String get systemDefaultTtsCannotBeTested => '当前平台无法测试系统默认 TTS。';

  @override
  String get ttsTestUsesCurrentConfiguration => 'TTS 测试会使用当前已保存的语音配置。';

  @override
  String get testText => '测试文本';

  @override
  String get playing => '播放中...';

  @override
  String get play => '播放';

  @override
  String batchAsrAuthOrParameterError(Object error) {
    return '认证或参数错误。请确认 APPID 和 API Key（Access Token）正确。\n\n原始错误：\n$error';
  }

  @override
  String batchAsrAuthenticationFailed(Object error) {
    return '认证失败。请确认 API Key 正确，并且已为该服务启用。\n\n原始错误：\n$error';
  }

  @override
  String batchAsrAccessDenied(Object error) {
    return '访问被拒绝。请确认 API Key 拥有所选 Resource ID 的权限。\n\n原始错误：\n$error';
  }

  @override
  String get microphonePermissionRequired => '需要麦克风权限。';

  @override
  String get recordingStartedSpeakThenStop => '录音已开始。说一句短句后停止。';

  @override
  String get transcribingRecordedAudio => '正在转写录音...';

  @override
  String get transcriptionSucceeded => '转写成功。';

  @override
  String transcriptionSucceededWithText(Object text) {
    return '转写成功：$text';
  }

  @override
  String get testBatchAsr => '测试批量 ASR';

  @override
  String get batchAsrTestDescription => '批量 ASR 测试会录制一小段音频，再用当前已保存的语音配置进行转写。';

  @override
  String get record => '录音';

  @override
  String get transcribing => '转写中...';

  @override
  String get stopAndTranscribe => '停止并转写';

  @override
  String get recordingSpeakThenStop => '录音中...说一句短句后停止。';

  @override
  String realtimeAsrAuthenticationRejected(Object error) {
    return '当前服务拒绝了实时语音认证。请检查所选插件凭据，尤其是 API Key 和 Resource ID。\n\n原始错误：\n$error';
  }

  @override
  String realtimeAsrAccessRefused(Object error) {
    return '当前服务拒绝实时语音访问。请确认 API Key 已为所选火山引擎语音资源启用，并且 Resource ID 与购买的时长版或并发版完全一致。\n\n原始错误：\n$error';
  }

  @override
  String realtimeAsrStartFailed(Object error) {
    return '当前服务无法启动实时语音。这通常表示所选插件没有提供有效的实时 websocket 端点。\n\n原始错误：\n$error';
  }

  @override
  String get startingRealtimeSpeechTest => '正在开始实时语音测试...';

  @override
  String get realtimeTranscriptReceived => '已收到实时转写。';

  @override
  String get realtimeSpeechComingThrough => '实时语音已接入。';

  @override
  String realtimeSpeechComingThroughWithText(Object text) {
    return '实时语音已接入：$text';
  }

  @override
  String get listeningSpeakShortSentence => '正在聆听。请说一句短句。';

  @override
  String get testRealtimeAsr => '测试实时 ASR';

  @override
  String get realtimeAsrSystemTestDescription => '实时 ASR 测试会使用当前已保存的系统语音输入。';

  @override
  String get realtimeAsrPluginTestDescription => '实时 ASR 测试会使用当前已保存的插件配置。';

  @override
  String get starting => '启动中...';

  @override
  String get start => '开始';

  @override
  String get use => '使用';

  @override
  String get test => '测试';

  @override
  String get uninstall => '卸载';

  @override
  String get install => '安装';

  @override
  String get getApiKey => '获取 API Key';

  @override
  String get startService => '启动服务';

  @override
  String get stopService => '停止服务';

  @override
  String get sentAsXApiKey => '会按插件的认证配置发送。';

  @override
  String get targetSpeakerOnly => '仅识别目标说话人';

  @override
  String get speakerName => '说话人名称';

  @override
  String get myVoice => '我的声音';

  @override
  String get speaker => '说话人';

  @override
  String get enrollSpeakerBeforeFiltering => '启用过滤前，请先在 Bridge 上录入一个说话人。';

  @override
  String get batchAsrIgnoresUnmatchedSpeaker => '批量 ASR 会忽略与所选声纹不匹配的语音。';

  @override
  String get voiceprintModelInstalled => '声纹模型已安装';

  @override
  String get voiceprintModelRequired => '需要声纹模型';

  @override
  String get savingSpeaker => '正在保存说话人';

  @override
  String get finishEnrollment => '完成录入';

  @override
  String get recordEnrollmentSample => '录制录入样本';

  @override
  String get speechRoutingSystemDefaultIntro =>
      '语音默认使用系统能力。只有需要自定义服务的能力才需要安装插件。';

  @override
  String get realtimeAsrRouteSubtitle => '麦克风流式输入、实时转写和打断检测。';

  @override
  String get realtimeAsrRouteFooter => '适合设备本地听写和打断处理的默认选择。';

  @override
  String get batchAsrRouteSubtitle => '录音片段、上传和非实时识别。';

  @override
  String get batchAsrRouteFooter => '适合云端转写供应商或更高准确率的离线任务。';

  @override
  String get ttsRouteSubtitle => '回复播放、语音输出和通话模式朗读。';

  @override
  String get ttsRouteFooter => '需要云端音色或本地 TTS 服务时使用插件。';

  @override
  String get systemRealtimeAsrTestUnavailable =>
      '当前平台无法测试系统实时 ASR。请选择一个实时 ASR 插件后测试。';

  @override
  String get systemBatchAsrTestUnavailable =>
      '系统默认不提供批量 ASR 测试。请选择一个批量 ASR 插件后测试转写。';

  @override
  String get selectedPluginNotInstalled => '所选插件尚未安装，无法测试。';

  @override
  String selectedPluginMissingCapabilityConfig(Object capability) {
    return '所选插件没有提供 $capability 配置，无法测试。';
  }

  @override
  String get expectedTtsEndpoint => 'OpenAI 兼容 TTS 端点';

  @override
  String get expectedTranscriptionEndpoint => 'OpenAI 兼容转写端点';

  @override
  String get expectedRealtimeWebsocketEndpoint => '实时 websocket 端点';

  @override
  String currentSelectionMissingExpectedEndpoint(Object expected) {
    return '当前选择没有提供 $expected，因此无法测试。';
  }

  @override
  String currentSelectionMissingRequiredSetting(Object setting) {
    return '当前选择缺少 $setting，因此无法测试。';
  }

  @override
  String get currentSelectionMissingRealtimeWebsocketUrl =>
      '当前选择缺少实时 websocket URL，因此无法测试。';

  @override
  String get currentSelectionInvalidRealtimeWebsocketUrl =>
      '当前选择的实时 websocket URL 无效，因此无法测试。';

  @override
  String get currentSelectionNonStreamingEndpoint =>
      '当前选择指向非流式端点，因此无法测试。请先配置实时 websocket URL。';

  @override
  String get installedAndReady => '已安装，可直接使用。';

  @override
  String get installBeforeSelectingPlugin => '请先安装，再选择此插件。';

  @override
  String get fillRequiredPluginSettingsBeforeTesting => '测试前请先填写必填设置。';

  @override
  String commandSucceeded(Object command) {
    return '命令执行成功：$command';
  }

  @override
  String commandFailed(int exitCode, Object stderr) {
    return '命令执行失败（$exitCode）：$stderr';
  }

  @override
  String get missingKey => '缺少密钥';

  @override
  String get keySaved => '密钥已保存';

  @override
  String pluginApiKeyTitle(Object pluginName) {
    return '$pluginName · API Key';
  }

  @override
  String get savePluginSettings => '保存插件设置';

  @override
  String get saveAndUse => '保存并使用';

  @override
  String get additionalPluginSettings => '附加插件设置';

  @override
  String bridgeErrorWithStatus(Object status, Object error) {
    return 'Bridge 错误（$status）：$error';
  }

  @override
  String get noEnrollmentAudioRecorded => '没有录到用于录入的音频。';

  @override
  String defaultSpeakerName(int index) {
    return '说话人 $index';
  }

  @override
  String get gitClean => '干净';

  @override
  String get gitDirty => '有改动';

  @override
  String get gitStaged => '已暂存';

  @override
  String get gitChanged => '已修改';

  @override
  String get gitUntracked => '未跟踪';

  @override
  String gitAhead(int count) {
    return '领先 $count 个提交';
  }

  @override
  String gitBehind(int count) {
    return '落后 $count 个提交';
  }

  @override
  String gitChangedCount(int count) {
    return '$count 项变更';
  }

  @override
  String gitStagedCount(int count) {
    return '$count 个暂存';
  }

  @override
  String gitUnstagedCount(int count) {
    return '$count 个修改';
  }

  @override
  String get notificationSound => '通知声音';

  @override
  String get notificationSoundAll => '全部通知';

  @override
  String get notificationSoundImportantOnly => '仅重要消息';

  @override
  String get notificationSoundMuted => '静音';

  @override
  String get errorReportingTitle => '错误诊断上报';

  @override
  String get errorReportingDescription =>
      '在程序发生错误时上传匿名诊断信息，帮助我们定位问题并改进稳定性。不会上传对话内容、输入文本或凭据。';

  @override
  String get piPluginsTitle => 'Pi 插件';

  @override
  String get piPluginsSubtitle => '安装和管理 Pi 会话加载的扩展';

  @override
  String get piPluginEmpty => '尚未安装 Pi 插件';

  @override
  String get piPluginAdd => '安装插件';

  @override
  String get piPluginSource => '来源';

  @override
  String get piPluginSourceNpm => 'npm 包';

  @override
  String get piPluginSourceUrl => '直接 URL';

  @override
  String get piPluginSourceGit => 'Git 仓库';

  @override
  String get piPluginSourceUpload => '上传文件';

  @override
  String get piPluginSourceLocal => 'Bridge 本地路径';

  @override
  String get piPluginId => '插件 ID（可选）';

  @override
  String get piPluginChecksum => 'SHA-256（建议填写）';

  @override
  String get piPluginScope => '作用范围';

  @override
  String get piPluginGlobal => '所有项目';

  @override
  String get piPluginSelectedProjects => '指定项目';

  @override
  String get piPluginConfig => '配置（JSON）';

  @override
  String get piPluginValidate => '重新校验';

  @override
  String get piPluginValidationFailed => '校验失败';

  @override
  String piPluginLoadFailed(Object error) {
    return '无法加载 Pi 插件：$error';
  }

  @override
  String piPluginOperationFailed(Object error) {
    return '插件操作失败：$error';
  }

  @override
  String get piPluginPermissionWarning => '扩展会以 Pi 的权限在 Bridge 主机运行。请只安装可信代码。';

  @override
  String piPluginRemoveConfirm(Object name) {
    return '卸载 $name？';
  }

  @override
  String get piPluginNextTurnHint => '更改会从下一轮 Pi 会话起生效。';

  @override
  String gitUntrackedCount(int count) {
    return '$count 个未跟踪';
  }
}
