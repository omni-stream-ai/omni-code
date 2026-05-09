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
  String get whisperCompatible => 'Whisper / OpenAI Compatible';

  @override
  String get apiKey => 'API Key';

  @override
  String get baseUrl => 'Base URL';

  @override
  String get aiApprovalSection => 'AI 审批';

  @override
  String get enableAiApproval => '启用 AI 辅助审批';

  @override
  String get enableAiApprovalSubtitle =>
      '通过 OpenAI-compatible endpoint 判断低风险命令';

  @override
  String get aiApprovalMaxRisk => '自动放行最高风险';

  @override
  String get aiApprovalHelp =>
      '保存后会同步到当前 Bridge。建议保持 Low；高风险、调用失败或命中硬阻断规则仍会回退到手机人工审批。';

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
  String get compressReplies => '压缩 AI 回复';

  @override
  String get compressRepliesSubtitle => '开启后，新建会话会要求 AI 简短说明做了什么，尽量不超过 50 字';

  @override
  String get notificationPreviewMaxChars => '通知最大字符数';

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
  String get create => '创建';

  @override
  String get refreshNativeSessions => '刷新原生会话';

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
  String get send => '发送';

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
  String get zhipuApiKeyRequired => '请先在设置中填写智谱 API Key';

  @override
  String zhipuAsrRequestFailed(Object statusCode, Object body) {
    return '智谱 ASR 请求失败 ($statusCode): $body';
  }

  @override
  String get zhipuAsrMissingText => '智谱 ASR 响应缺少 text';

  @override
  String get whisperApiKeyRequired => '请先在设置中填写 Whisper/OpenAI API Key';

  @override
  String whisperAsrRequestFailed(Object statusCode, Object body) {
    return 'Whisper ASR 请求失败 ($statusCode): $body';
  }

  @override
  String get whisperAsrMissingText => 'Whisper ASR 响应缺少 text';

  @override
  String zhipuTtsRequestFailed(Object statusCode, Object body) {
    return '智谱 TTS 请求失败 ($statusCode): $body';
  }

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
  String get speechSystemPreferredHelp => '系统可用时默认使用。如需备份可切换到云服务商。';

  @override
  String get systemTtsUnavailableOnLinux =>
      'Linux 当前还不支持系统 TTS。请切换到云端服务商后再启用播报。';

  @override
  String get systemAsrUnavailableOnLinux =>
      'Linux 当前还不支持系统 ASR。请切换到云端服务商后再启用语音输入。';

  @override
  String get systemAsrMacosPermissionHint => 'macOS 的系统 ASR 需要麦克风和语音识别权限。';

  @override
  String get systemSpeechUnavailable => '当前设备不支持系统语音。请到设置中切换服务商后再使用云端语音。';

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
}
