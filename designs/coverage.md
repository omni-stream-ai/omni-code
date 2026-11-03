# 移动端改版 · 功能核对表

核对日期：2026-11-03。依据当前工作区 Flutter 源码；示例数据不代表实际服务状态。

共 413 个功能组，296 个页面 / 弹层 / 状态画面。每条记录包含设计节点和源码中的依据，条件性入口不能作为始终可用的操作。

## lib/src/screens/home_screen.dart

| 功能组 | 画稿位置 | 源码依据 | 显示条件 |
| --- | --- | --- | --- |
| home.navigation | Action / menu_rounded | [L1088](../lib/src/screens/home_screen.dart) · openDrawer | 始终可见 |
| home.bridge | ● 已连接 · 192.168.1.8:8787 | [L50](../lib/src/screens/home_screen.dart) · bridgeUrl | 始终可见 |
| home.status | Row | [L836](../lib/src/screens/home_screen.dart) · SessionStatus.awaitingApproval | 从已加载会话摘要计算，仅统计当前列表 |
| home.review-entry | Card | [L836](../lib/src/screens/home_screen.dart) · SessionStatus.awaitingApproval | 进入会话读取请求详情；首页不预先展示审批命令 |
| home.search | Search / 搜索项目、会话标题或摘要 | [L1118](../lib/src/screens/home_screen.dart) · _buildDashboardSearchBar | 始终可见 |
| home.profile-filter | Section / 最近会话 | [L238](../lib/src/screens/home_screen.dart) · _selectProfile | 有配置档时显示；不是运行状态筛选 |
| home.sessions | Column | [L788](../lib/src/screens/home_screen.dart) · _buildRecentSessionsContent | 始终可见 |
| home.projects | Column | [L1151](../lib/src/screens/home_screen.dart) · _HomeProjectsPanel | 始终可见 |
| home.create-session | Button / 新建会话 | [L563](../lib/src/screens/home_screen.dart) · _newSession | 始终可见 |
| projects.search | Search / 搜索项目名或路径 | [L1353](../lib/src/screens/home_screen.dart) · searchProjects | 始终可见 |
| projects.open | Column | [L540](../lib/src/screens/home_screen.dart) · _openProject | 始终可见 |
| projects.new-session | 每个项目右侧可直接创建会话 | [L572](../lib/src/screens/home_screen.dart) · _newSessionForProject | 始终可见 |
| projects.create | Action / add_rounded | [L1600](../lib/src/screens/home_screen.dart) · _createProject | 始终可见 |
| connect.download | Card | [L905](../lib/src/screens/home_screen.dart) · waitingApprovalDownloadBridge | 始终可见 |
| connect.address | Field / Bridge 地址 | [L50](../lib/src/screens/home_screen.dart) · _bridgeUrlController | 始终可见 |
| connect.authorize | Button / 授权当前设备 | [L932](../lib/src/screens/home_screen.dart) · authorizeThisDevice | 始终可见 |
| connect.approval-command | Card | [L1000](../lib/src/screens/home_screen.dart) · waitingApprovalRunCommand | 始终可见 |
| connect.polling | Row | [L1022](../lib/src/screens/home_screen.dart) · waitingApprovalListening | 始终可见 |
| connect.re-request | Button / 重新请求 | [L1049](../lib/src/screens/home_screen.dart) · waitingApprovalRequestAgain | 始终可见 |
| connect.back | Button / 返回欢迎页 | [L956](../lib/src/screens/home_screen.dart) · backToWelcome | 始终可见 |
| state.home-loading | Column | [L626](../lib/src/screens/home_screen.dart) · _HomeSurfaceState.loading | 首页尚未取得首次会话 / 项目结果 |
| state.home-connect | Column | [L632](../lib/src/screens/home_screen.dart) · _HomeSurfaceState.connect | 尚未配置可用的 Bridge 或未授权 |
| state.home-authorization | Column | [L629](../lib/src/screens/home_screen.dart) · _HomeSurfaceState.waitingApproval | 已取得授权请求 ID，等待主机批准 |
| state.home-auth-error | Column | [L58](../lib/src/screens/home_screen.dart) · _authError | 授权请求或轮询返回错误 |
| state.home-saving-bridge | Column | [L64](../lib/src/screens/home_screen.dart) · _isSavingBridgeConfig | Bridge 配置保存请求尚未结束 |
| state.home-refreshing | Column | [L60](../lib/src/screens/home_screen.dart) · _isRefreshing | 已存在数据，再次刷新中 |
| state.home-session-error | Column | [L57](../lib/src/screens/home_screen.dart) · _recentSessionsError | 会话接口失败，项目可以独立展示 |
| state.home-project-error | Column | [L56](../lib/src/screens/home_screen.dart) · _projectsError | 项目接口失败，已有会话内容可保留 |
| state.home-no-sessions | Column | [L812](../lib/src/screens/home_screen.dart) · noSessionsYet | 项目存在，但会话列表为空 |
| state.home-search-empty | Column | [L1363](../lib/src/screens/home_screen.dart) · noSearchResultsTitle | 查询非空，匹配会话与项目均为空 |
| state.projects-loading | Column | [L723](../lib/src/screens/home_screen.dart) · _SearchBarSkeleton | 首次项目请求尚未返回 |
| state.projects-empty | Column | [L1830](../lib/src/screens/home_screen.dart) · noProjectsYet | 项目请求成功且列表为空 |
| state.projects-error | Column | [L1122](../lib/src/screens/home_screen.dart) · loadProjectsFailed | 列表接口返回错误 |

## lib/src/screens/project_detail_screen.dart

| 功能组 | 画稿位置 | 源码依据 | 显示条件 |
| --- | --- | --- | --- |
| project.summary | Card | [L390](../lib/src/screens/project_detail_screen.dart) · _buildProjectSummaryCard | 始终可见 |
| project.acceptance | Card | [L396](../lib/src/screens/project_detail_screen.dart) · _openAcceptance | 当前项目入口使用 automatic=false；自动验收从会话或设置进入 |
| project.approval-prompt | Open / 项目级审批 Prompt | [L398](../lib/src/screens/project_detail_screen.dart) · _buildAiApprovalSettingsCard | 始终可见 |
| project.search | Search / 搜索会话标题或摘要 | [L400](../lib/src/screens/project_detail_screen.dart) · _buildSearchSection | 始终可见 |
| project.sessions | Column | [L402](../lib/src/screens/project_detail_screen.dart) · _buildSessionsSection | 始终可见 |
| project.load-more | Button / 加载更多 | [L810](../lib/src/screens/project_detail_screen.dart) · loadMoreSessionsLabel | 还有未显示会话时展示 |
| project.create-session | Action / add_rounded | [L311](../lib/src/screens/project_detail_screen.dart) · _createSession | 始终可见 |
| state.project-empty | Column | [L763](../lib/src/screens/project_detail_screen.dart) · _ProjectEmptyCard | 当前项目会话请求成功且列表为空 |
| state.project-search-empty | Column | [L768](../lib/src/screens/project_detail_screen.dart) · _ProjectSearchEmptyCard | 该项目有会话，但没有匹配当前查询 |
| state.project-error | Column | [L757](../lib/src/screens/project_detail_screen.dart) · _ProjectErrorCard | 当前项目会话接口返回错误 |
| state.project-refreshing | Column | [L51](../lib/src/screens/project_detail_screen.dart) · _isRefreshing | 已有会话，周期刷新或下拉刷新中 |

## lib/src/screens/session_detail_screen.dart

| 功能组 | 画稿位置 | 源码依据 | 显示条件 |
| --- | --- | --- | --- |
| session.call | Action / phone | [L1991](../lib/src/screens/session_detail_screen.dart) · _buildCallModeActionButton | 实时 ASR 可用时启用 |
| session.menu | Action / more | [L2154](../lib/src/screens/session_detail_screen.dart) · _buildSessionHeaderOptionsPanel | 始终可见 |
| session.navigation | Row | [L2001](../lib/src/screens/session_detail_screen.dart) · _buildMobileSessionTopBar | 始终可见 |
| session.user-message | User message / reading surface | [L2366](../lib/src/screens/session_detail_screen.dart) · _buildConversationPane | 始终可见 |
| session.assistant | 已调整信息层次，正文、工具结果与文件变更各自清晰呈现。 | [L2366](../lib/src/screens/session_detail_screen.dart) · _buildConversationPane | 始终可见 |
| session.tools | Row | [L10784](../lib/src/screens/session_detail_screen.dart) · _showToolMessageDetail | 始终可见 |
| session.diff | File diff summary | [L5187](../lib/src/screens/session_detail_screen.dart) · _DiffViewer | 始终可见 |
| session.message-actions | Row | [L312](../lib/src/screens/session_detail_screen.dart) · _speak | 播报操作受 TTS 可用性控制 |
| session.approval | Approval request / compact hierarchy | [L2546](../lib/src/screens/session_detail_screen.dart) · _buildPendingApprovalCard | 本会话允许 / 取消由请求能力决定；始终允许仅在命令非空时出现 |
| session.composer | Message composer / quiet surface | [L2377](../lib/src/screens/session_detail_screen.dart) · _buildMessageComposer | 始终可见 |
| session.menu-new | Open / 在当前项目新建会话 | [L2083](../lib/src/screens/session_detail_screen.dart) · _startNewSessionFromCurrentProject | 始终可见 |
| session.menu-acceptance | Open / 应用验收 | [L2199](../lib/src/screens/session_detail_screen.dart) · AcceptanceScreen | 始终可见 |
| session.copy-id | Open / 复制 Codex 会话 ID | [L2231](../lib/src/screens/session_detail_screen.dart) · _copySessionId | 仅存在非空 runtimeSessionRef 时显示 |
| session.copy-resume | Open / 复制恢复命令 | [L2243](../lib/src/screens/session_detail_screen.dart) · _copyResumeCommand | 仅 Codex 且有运行时会话引用时显示 |
| session.history | Open / 加载更早消息 | [L10703](../lib/src/screens/session_detail_screen.dart) · _expandVisibleHistory | 始终可见 |
| session.latest | Open / 回到最新消息 | [L12066](../lib/src/screens/session_detail_screen.dart) · scrollToLatest | 始终可见 |
| session.provider-override | Field / 模型供应商 | [L3438](../lib/src/screens/session_detail_screen.dart) · _applyProviderOverride | 始终可见 |
| session.model-override | Field / 模型 | [L3477](../lib/src/screens/session_detail_screen.dart) · _applyModelOverride | 始终可见 |
| session.reasoning | Field / 推理强度 | [L3461](../lib/src/screens/session_detail_screen.dart) · _applyReasoningOverride | 按 Agent 实际支持的推理能力显示 |
| session.at-mention | Card | [L229](../lib/src/screens/session_detail_screen.dart) · _composerSuggestionsOverlayController | 始终可见 |
| session.attachments | Card | [L290](../lib/src/screens/session_detail_screen.dart) · _uploadingAttachments | 始终可见 |
| session.all-tools | Section / 当前轮次 · 3 条活动 | [L10777](../lib/src/screens/session_detail_screen.dart) · allToolActivity | 始终可见 |
| session.tool-details | Card | [L10867](../lib/src/screens/session_detail_screen.dart) · _buildStructuredToolDetail | 始终可见 |
| session.diff-files | Section / 本轮文件变更 | [L957](../lib/src/screens/session_detail_screen.dart) · _splitSessionDiffByFile | 始终可见 |
| session.diff-preview | Open / 查看完整 Diff | [L5187](../lib/src/screens/session_detail_screen.dart) · _DiffViewer | 始终可见 |
| state.session-creating | Column | [L361](../lib/src/screens/session_detail_screen.dart) · _creatingSession | creatingSession=true |
| state.session-loading | Column | [L305](../lib/src/screens/session_detail_screen.dart) · _loadingMessages | loadingMessages=true，显示消息骨架 |
| state.session-empty | Column | [L620](../lib/src/screens/session_detail_screen.dart) · SessionStatus.idle | idle，历史轮次为空 |
| state.session-idle | Column | [L620](../lib/src/screens/session_detail_screen.dart) · SessionStatus.idle | idle，已存在完成的回复 |
| state.session-running | Column | [L637](../lib/src/screens/session_detail_screen.dart) · SessionStatus.running | status=running，有活跃轮次 |
| state.session-waiting | Column | [L638](../lib/src/screens/session_detail_screen.dart) · SessionStatus.waiting | status=waiting，已提交且等待回复 |
| state.session-awaiting-approval | Column | [L537](../lib/src/screens/session_detail_screen.dart) · SessionStatus.awaitingApproval | 存在可处理的 pendingApproval |
| state.session-interrupted | Column | [L660](../lib/src/screens/session_detail_screen.dart) · SessionStatus.interrupted | status=interrupted |
| state.session-failed | Column | [L970](../lib/src/screens/session_detail_screen.dart) · SessionStatus.failed | status=failed，错误横幅不可直接关闭 |
| state.session-restore-failed | Column | [L354](../lib/src/screens/session_detail_screen.dart) · _sessionRestoreError | 恢复失败：标题显示错误提示，保留已加载内容 |
| state.session-create-failed | Column | [L6779](../lib/src/screens/session_detail_screen.dart) · createSessionFailed | 初始化 Future 失败，保留错误原因 |
| state.session-keyboard | Column | [L726](../lib/src/screens/session_detail_screen.dart) · _composerHasInteractiveFocus | 输入框聚焦且软键盘显示；键盘为 Android 示例 |
| state.session-keyboard-approval | Column | [L2546](../lib/src/screens/session_detail_screen.dart) · _buildPendingApprovalCard | 软键盘显示；示例请求无命令且不支持会话允许 / 取消 |
| state.approval-command | Column | [L4596](../lib/src/screens/session_detail_screen.dart) · allowAcceptForSession | resolvable=true，命令非空，支持会话允许与取消 |
| state.approval-limited | Column | [L4634](../lib/src/screens/session_detail_screen.dart) · approval.allowCancel | 不支持本会话允许与取消，仍包含命令 |
| state.approval-no-command | Column | [L4560](../lib/src/screens/session_detail_screen.dart) · approval.command | command 为空，不展示始终允许 |
| state.approval-submitting | Column | [L363](../lib/src/screens/session_detail_screen.dart) · _submittingApprovalChoice | 已点击审批选项，提交尚未返回 |
| state.approval-resolution-pending | Column | [L534](../lib/src/screens/session_detail_screen.dart) · _isAwaitingSubmittedApprovalResolution | 已记录 submittedApprovalRequestId，但请求尚未从服务状态消失 |
| state.approval-submit-error | Column | [L8045](../lib/src/screens/session_detail_screen.dart) · approvalSubmitFailed | 提交失败，原审批请求仍存在 |
| state.approval-desktop-only | Column | [L4722](../lib/src/screens/session_detail_screen.dart) · desktopOnlyApproval | resolvable=false |
| state.approval-ai-block | Column | [L7999](../lib/src/screens/session_detail_screen.dart) · 'hard_block' | autoApprovalReason=hard_block，仍按 resolvable 决定人工操作 |
| state.approval-ai-error | Column | [L8000](../lib/src/screens/session_detail_screen.dart) · 'review_failed' | autoApprovalReason=review_failed |
| state.approval-cleared | Column | [L7487](../lib/src/screens/session_detail_screen.dart) · _pendingApproval = null | 服务确认审批已解决，pendingApproval 清空 |
| state.composer-empty | Column | [L2810](../lib/src/screens/session_detail_screen.dart) · hasSendableDraft | 无文本、无附件、未聚焦 |
| state.composer-focused | Column | [L726](../lib/src/screens/session_detail_screen.dart) · _composerHasInteractiveFocus | 移动端输入获得焦点，无文本草稿 |
| state.composer-draft | Column | [L2810](../lib/src/screens/session_detail_screen.dart) · hasSendableDraft | 文本 trim 后非空 |
| state.composer-running | Column | [L1881](../lib/src/screens/session_detail_screen.dart) · hasActiveTurn | 有活跃轮次，且存在可发送草稿 |
| state.composer-attachments | Column | [L2811](../lib/src/screens/session_detail_screen.dart) · _pendingAttachments.isNotEmpty | 已选择图片，文本可以为空 |
| state.composer-uploading | Column | [L290](../lib/src/screens/session_detail_screen.dart) · _uploadingAttachments | isSessionBusy=true |
| state.composer-voice-mode | Column | [L329](../lib/src/screens/session_detail_screen.dart) · _voiceComposerMode | voiceComposerMode=true |
| state.composer-voice-starting | Column | [L309](../lib/src/screens/session_detail_screen.dart) · _voiceInputStarting | 语音初始化尚未完成 |
| state.composer-voice-recording | Column | [L330](../lib/src/screens/session_detail_screen.dart) · _voiceHoldActive | 按住按钮，语音录制中 |
| state.composer-voice-lifted | Column | [L331](../lib/src/screens/session_detail_screen.dart) · _voiceHoldLifted | 按住录音后已上滑离开按钮区域 |
| state.composer-transcribing | Column | [L8651](../lib/src/screens/session_detail_screen.dart) · uploadingAudio | 批量 ASR 已提交录音，尚未返回文本 |
| state.composer-voice-unavailable | Column | [L8145](../lib/src/screens/session_detail_screen.dart) · microphonePermissionMissing | 语音启动时检测到麦克风权限缺失 |
| state.composer-at-files | Column | [L229](../lib/src/screens/session_detail_screen.dart) · _composerSuggestionsOverlayController | 输入 @ 后显示当前项目文件候选 |
| state.composer-stopping | Column | [L367](../lib/src/screens/session_detail_screen.dart) · _cancellingReply | 已请求取消当前活跃轮次 |
| state.composer-hold-send | Column | [L8450](../lib/src/screens/session_detail_screen.dart) · _VoiceHoldAction.send | 按住录音后，当前松手动作=send |
| state.composer-hold-insert | Column | [L3183](../lib/src/screens/session_detail_screen.dart) · _VoiceHoldAction.insert | 按住录音后，当前松手动作=insert |
| state.composer-hold-cancel | Column | [L3196](../lib/src/screens/session_detail_screen.dart) · _VoiceHoldAction.cancel | 按住录音后，当前松手动作=cancel |
| state.composer-select-provider | Column | [L3432](../lib/src/screens/session_detail_screen.dart) · _ComposerSettingsPanelSection.provider | 已打开输入区的模型供应商子面板 |
| state.composer-select-reasoning | Column | [L3455](../lib/src/screens/session_detail_screen.dart) · _ComposerSettingsPanelSection.reasoning | 已打开输入区的推理强度子面板 |
| state.composer-select-model | Column | [L3472](../lib/src/screens/session_detail_screen.dart) · _ComposerSettingsPanelSection.model | 已打开输入区的模型子面板 |
| state.message-queued | Column | [L4959](../lib/src/screens/session_detail_screen.dart) · _LocalMessageState.queued | 本地消息状态=queued |
| state.message-pending | Column | [L984](../lib/src/screens/session_detail_screen.dart) · _LocalMessageState.pending | 本地消息状态=pending |
| state.message-submitted | Column | [L985](../lib/src/screens/session_detail_screen.dart) · _LocalMessageState.submitted | 本地消息状态=submitted |
| state.message-failed | Column | [L4958](../lib/src/screens/session_detail_screen.dart) · _LocalMessageState.failed | 本地消息状态=failed |
| state.message-streaming | Column | [L7640](../lib/src/screens/session_detail_screen.dart) · _mergeAssistantStreamContent | 同一 assistant 消息持续返回增量内容 |
| state.message-tools | Column | [L10784](../lib/src/screens/session_detail_screen.dart) · _showToolMessageDetail | 工具调用已开始或返回结果，可查看详情 |
| state.message-diff | Column | [L337](../lib/src/screens/session_detail_screen.dart) · _expandedDiffTurnIds | 本轮存在一项或多项文件 diff |
| state.message-history-loading | Column | [L355](../lib/src/screens/session_detail_screen.dart) · _expandingHistory | 滚动至历史顶部，扩展更早消息中 |
| state.message-scroll-latest | Column | [L368](../lib/src/screens/session_detail_screen.dart) · _showScrollToBottomAction | 当前滚动位置已离开底部 |
| state.message-image-preview | Column | [L6097](../lib/src/screens/session_detail_screen.dart) · _ImagePreviewBackdropMode | 打开消息中的图片预览 |
| state.message-media-error | Column | [L6136](../lib/src/screens/session_detail_screen.dart) · imagePreviewLoadFailed | 图片或视频加载失败 |
| state.message-speaking | Column | [L311](../lib/src/screens/session_detail_screen.dart) · _isSpeaking | TTS 正在播放当前回复 |
| state.image-backdrop-dark | Column | [L6097](../lib/src/screens/session_detail_screen.dart) · _ImagePreviewBackdropMode.dark | 图片预览背景选为深色 |
| state.image-backdrop-light | Column | [L6323](../lib/src/screens/session_detail_screen.dart) · _ImagePreviewBackdropMode.light | 图片预览背景选为浅色 |
| state.image-backdrop-checker | Column | [L6325](../lib/src/screens/session_detail_screen.dart) · _ImagePreviewBackdropMode.checker | 图片预览背景选为棋盘格 |
| state.call-preparing | Column | [L3882](../lib/src/screens/session_detail_screen.dart) · _showVoiceInputStartingAsPrimary | 正在初始化实时 ASR |
| state.call-idle | Column | [L4005](../lib/src/screens/session_detail_screen.dart) · startCallMode | 通话模式已打开但未聆听 |
| state.call-listening | Column | [L321](../lib/src/screens/session_detail_screen.dart) · _streamingAsrActive | isListening 或 streamingAsrActive |
| state.call-detected | Column | [L4030](../lib/src/screens/session_detail_screen.dart) · _CallModeSpeechHintState.speaking | speechHintState=speaking |
| state.call-pause | Column | [L4036](../lib/src/screens/session_detail_screen.dart) · _CallModeSpeechHintState.waitingForPause | speechHintState=waitingForPause |
| state.call-working | Column | [L991](../lib/src/screens/session_detail_screen.dart) · _session.status == SessionStatus.running | status=running |
| state.call-waiting | Column | [L992](../lib/src/screens/session_detail_screen.dart) · _session.status == SessionStatus.waiting | status=waiting |
| state.call-approval | Column | [L1883](../lib/src/screens/session_detail_screen.dart) · _session.status == SessionStatus.awaitingApproval | status=awaitingApproval |
| state.call-speaking | Column | [L315](../lib/src/screens/session_detail_screen.dart) · _callModeAwaitingPlaybackCompletion | isSpeaking 或等待音频播放完成 |
| state.call-speaker-check | Column | [L299](../lib/src/screens/session_detail_screen.dart) · _recognizedSpeechPendingSpeakerVerification | 转写内容尚在等待说话人核实 |
| state.call-rejected-speaker | Column | [L300](../lib/src/screens/session_detail_screen.dart) · _recognizedSpeechRejectedSpeaker | 语音不属于所选说话人 |
| state.call-rejected-other | Column | [L302](../lib/src/screens/session_detail_screen.dart) · _recognizedSpeechRejectedOther | 转写未通过当前输入校验 |
| state.call-error | Column | [L3923](../lib/src/screens/session_detail_screen.dart) · statusIsError | speechError 非空或会话失败 |
| state.call-subtitles-off | Column | [L314](../lib/src/screens/session_detail_screen.dart) · _callModeSubtitlesVisible | subtitlesVisible=false |
| state.pi-ui-confirm | Column | [L7812](../lib/src/screens/session_detail_screen.dart) · _showPiConfirm | 插件发出 confirm / custom 请求 |
| state.pi-ui-capability | Column | [L7850](../lib/src/screens/session_detail_screen.dart) · isCapability | 请求包含 capability、permission 或 persist |
| state.pi-ui-select | Column | [L7816](../lib/src/screens/session_detail_screen.dart) · _showPiSelect | 插件发出 select 请求 |
| state.pi-ui-input | Column | [L7926](../lib/src/screens/session_detail_screen.dart) · request.method == 'editor' | 插件发出 input 请求 |
| state.pi-ui-editor | Column | [L7821](../lib/src/screens/session_detail_screen.dart) · _showPiTextInput | 插件发出 editor 请求，保留多行输入 |
| state.render-headings | Parsed output | [L5553](../lib/src/screens/session_detail_screen.dart) · MarkdownBody( | 返回 Markdown 标题与普通段落 |
| state.render-emphasis | Parsed output | [L5486](../lib/src/screens/session_detail_screen.dart) · strong: | 内容包含强调语法 |
| state.render-inline-code | Parsed output | [L5477](../lib/src/screens/session_detail_screen.dart) · code: codeStyle | 段落包含反引号代码 |
| state.render-code | Parsed output | [L5560](../lib/src/screens/session_detail_screen.dart) · _AssistantCodeSyntaxHighlighter(theme) | 返回 fenced code block |
| state.render-code-wide | Parsed output | [L5560](../lib/src/screens/session_detail_screen.dart) · _AssistantCodeSyntaxHighlighter(theme) | 长行代码超出正文宽度 |
| state.render-unordered-list | Parsed output | [L5494](../lib/src/screens/session_detail_screen.dart) · listBullet: | 内容包含无序列表 |
| state.render-ordered-list | Parsed output | [L5494](../lib/src/screens/session_detail_screen.dart) · listBullet: | 内容包含有序列表 |
| state.render-table | Parsed output | [L5553](../lib/src/screens/session_detail_screen.dart) · MarkdownBody( | MarkdownBody 以默认 Markdown 规则渲染表格 |
| state.render-quote | Parsed output | [L5498](../lib/src/screens/session_detail_screen.dart) · blockquoteDecoration: | 内容以 > 引用标记开头 |
| state.render-quote-nested | Parsed output | [L5506](../lib/src/screens/session_detail_screen.dart) · blockquotePadding: | 引用内容包含嵌套引用 |
| state.render-divider | Parsed output | [L5586](../lib/src/screens/session_detail_screen.dart) · markdown-horizontal-rule | 正文包含独立的 --- 分隔行 |
| state.render-consecutive | Parsed output | [L4937](../lib/src/screens/session_detail_screen.dart) · assistant-message-divider | 同一轮中相邻的助手消息分别展示 |
| state.render-streaming-markdown | Parsed output | [L5284](../lib/src/screens/session_detail_screen.dart) · isLoadingReply | 正文持续增长，Markdown 按当前已收到的文本渲染 |
| state.render-external-link | Parsed output | [L5652](../lib/src/screens/session_detail_screen.dart) · unawaited(launchUrl(uri)) | 链接既不是媒体引用，也不是客户端可访问的本地文件 |
| state.render-autolink | Parsed output | [L5562](../lib/src/screens/session_detail_screen.dart) · onTapLink: | 返回尖括号包裹的 URL |
| state.render-file-relative | Parsed output | [L5642](../lib/src/screens/session_detail_screen.dart) · _resolveMarkdownFile(href) | 客户端能访问项目根路径，且目标文件在本机存在 |
| state.render-file-uri | Parsed output | [L5659](../lib/src/screens/session_detail_screen.dart) · uri.toFilePath() | file URI 解析为存在的客户端本地文件 |
| state.render-file-preview | Parsed output | [L5735](../lib/src/screens/session_detail_screen.dart) · markdown-file-preview-content | 文件存在、大小不超过 2 MiB，且不包含 0 字节 |
| state.render-file-too-large | Parsed output | [L5678](../lib/src/screens/session_detail_screen.dart) · File is too large to preview | 客户端本地文件大于 2 MiB |
| state.render-file-binary | Parsed output | [L5684](../lib/src/screens/session_detail_screen.dart) · Binary files cannot be previewed | 文件字节包含 0，判定为二进制 |
| state.render-image-link | Parsed output | [L5636](../lib/src/screens/session_detail_screen.dart) · MessageImageReference.tryParse(href) | 普通 Markdown 链接指向支持的媒体路径 |
| state.render-image-remote | Parsed output | [L5895](../lib/src/screens/session_detail_screen.dart) · reference.isRemoteUrl | 引用为 http / https 图片地址 |
| state.render-image-svg | Parsed output | [L5928](../lib/src/screens/session_detail_screen.dart) · reference.isSvg | 媒体引用识别为 SVG |
| state.render-media-mixed | Parsed output | [L5536](../lib/src/screens/session_detail_screen.dart) · buildImageReferences() | 同一消息提取到图片、MP4 与 SVG |
| state.render-media-user | Parsed output | [L4984](../lib/src/screens/session_detail_screen.dart) · imageWrapAlignment: WrapAlignment.end | 用户消息同时包含正文与图片 |
| state.render-image-loading | Parsed output | [L11957](../lib/src/screens/session_detail_screen.dart) · widget.loadingBuilder() | Bridge 文件 Future 尚未完成 |
| state.render-image-hidden-error | Parsed output | [L6224](../lib/src/screens/session_detail_screen.dart) · snapshot.hasError  /  /  !snapshot.hasData | Bridge 读取失败或没有数据，缩略图分支返回 SizedBox.shrink |
| state.render-image-decode-error | Parsed output | [L5937](../lib/src/screens/session_detail_screen.dart) · errorBuilder: (context, _, __) => const SizedBox.shrink() | 图片字节不可解码，缩略图内容收起 |
| state.render-image-preview-loading | Parsed output | [L6215](../lib/src/screens/session_detail_screen.dart) · snapshot.connectionState != ConnectionState.done | 打开本地图片预览，文件 Future 尚未完成 |
| state.render-image-preview-failed | Parsed output | [L6135](../lib/src/screens/session_detail_screen.dart) · _buildImagePreviewError( | 全屏读取或图片解码失败 |
| state.render-gallery-0 | Parsed output | [L6496](../lib/src/screens/session_detail_screen.dart) · image-preview-previous | 同一消息有 3 个媒体引用，当前索引为 0 |
| state.render-gallery-1 | Parsed output | [L6496](../lib/src/screens/session_detail_screen.dart) · image-preview-previous | 同一消息有 3 个媒体引用，当前索引为 1 |
| state.render-gallery-2 | Parsed output | [L6496](../lib/src/screens/session_detail_screen.dart) · image-preview-previous | 同一消息有 3 个媒体引用，当前索引为 2 |
| state.render-video-fallback | Parsed output | [L5982](../lib/src/screens/session_detail_screen.dart) · _buildVideoThumbnailFallback | 缩略图未初始化、初始化失败，或平台不支持内联视频帧 |
| state.render-video-thumbnail | Parsed output | [L6052](../lib/src/screens/session_detail_screen.dart) · video-thumbnail-icon- | 支持内联视频帧且缩略图已完成初始化 |
| state.render-video-loading | Parsed output | [L13392](../lib/src/screens/session_detail_screen.dart) · initializeFuture == null  /  /  controller == null | 视频文件读取或播放器初始化尚未完成 |
| state.render-video-playing-muted | Parsed output | [L13441](../lib/src/screens/session_detail_screen.dart) · video-preview-toggle-play | 播放器已初始化，isPlaying=true，muted=true |
| state.render-video-playing-sound | Parsed output | [L13441](../lib/src/screens/session_detail_screen.dart) · video-preview-toggle-play | 播放器已初始化，isPlaying=true，muted=false |
| state.render-video-paused-muted | Parsed output | [L13441](../lib/src/screens/session_detail_screen.dart) · video-preview-toggle-play | 播放器已初始化，isPlaying=false，muted=true |
| state.render-video-paused-sound | Parsed output | [L13441](../lib/src/screens/session_detail_screen.dart) · video-preview-toggle-play | 播放器已初始化，isPlaying=false，muted=false |
| state.render-video-portrait | Parsed output | [L13420](../lib/src/screens/session_detail_screen.dart) · controller.value.aspectRatio | 视频已初始化，采用播放器返回的原始宽高比 |
| state.render-video-error | Parsed output | [L13387](../lib/src/screens/session_detail_screen.dart) · _buildPreviewError(errorMessage) | 视频读取或初始化失败 |
| state.render-video-external | Parsed output | [L6084](../lib/src/screens/session_detail_screen.dart) · _openVideoExternally( | Linux / Windows 点击视频引用，进入外部打开流程 |
| state.render-diff-single | Parsed output | [L5040](../lib/src/screens/session_detail_screen.dart) · diffs.length == 1 | 当前轮次只有一个文件变更 |
| state.render-diff-collapsed | Parsed output | [L5043](../lib/src/screens/session_detail_screen.dart) · _expandedDiffTurnIds.contains(turn.id) | 当前轮次有多个变更，expanded=false |
| state.render-diff-expanded | Parsed output | [L5082](../lib/src/screens/session_detail_screen.dart) · for (final diff in diffs.skip(1)) | 当前轮次有多个变更，expanded=true |
| state.render-diff-detail | Parsed output | [L12597](../lib/src/screens/session_detail_screen.dart) · _buildLineSpan( | 点击文件变更摘要，打开全屏 Diff |
| state.render-diff-summary-only | Parsed output | [L5189](../lib/src/screens/session_detail_screen.dart) · diff.summary ?? 'No diff details' | patch 为空，优先显示 summary，否则显示 No diff details |
| state.render-diff-long | Parsed output | [L12557](../lib/src/screens/session_detail_screen.dart) · _virtualizedLineThreshold = 1000 | 解析后行数大于 1000，使用固定行高的虚拟列表 |
| state.render-diff-fenced-text | Parsed output | [L5560](../lib/src/screens/session_detail_screen.dart) · syntaxHighlighter: | 助手在普通 Markdown 回复中返回 diff 代码块 |
| state.render-task-list | Parsed output | [L5553](../lib/src/screens/session_detail_screen.dart) · MarkdownBody( | 默认 GitHub Flavored Markdown 解析任务列表 |
| state.render-strikethrough | Parsed output | [L5553](../lib/src/screens/session_detail_screen.dart) · MarkdownBody( | 默认 GitHub Flavored Markdown 解析删除线 |

## lib/src/screens/settings_screen.dart

| 功能组 | 画稿位置 | 源码依据 | 显示条件 |
| --- | --- | --- | --- |
| settings.speech | Card | [L382](../lib/src/screens/settings_screen.dart) · _buildSpeechSection | 始终可见 |
| settings.acceptance | Card | [L384](../lib/src/screens/settings_screen.dart) · _buildAcceptanceSection | 始终可见 |
| settings.pi | Open / Pi 插件 | [L386](../lib/src/screens/settings_screen.dart) · _buildPiPluginsSection | 始终可见 |
| settings.providers | Open / 模型供应商 | [L390](../lib/src/screens/settings_screen.dart) · _buildModelProvidersSection | 始终可见 |
| settings.ai | Open / AI 辅助审批 | [L388](../lib/src/screens/settings_screen.dart) · _buildAiApprovalSection | 始终可见 |
| settings.reply | Open / 回复行为 | [L392](../lib/src/screens/settings_screen.dart) · _buildReplyBehaviorSection | 始终可见 |
| settings.system | Open / 系统与更新 | [L394](../lib/src/screens/settings_screen.dart) · _buildSystemSection | 始终可见 |
| settings.save | Button / 保存 | [L494](../lib/src/screens/settings_screen.dart) · _save | 始终可见 |
| settings.ai-enable | Setting / 启用 AI 辅助审批 | [L885](../lib/src/screens/settings_screen.dart) · enableAiApproval | 始终可见 |
| settings.ai-provider | Field / 审批模型服务 | [L55](../lib/src/screens/settings_screen.dart) · aiApprovalProvider | 始终可见 |
| settings.ai-model | Field / 审批模型 | [L57](../lib/src/screens/settings_screen.dart) · aiApprovalModel | 始终可见 |
| settings.ai-risk | Field / 自动放行最高风险 | [L54](../lib/src/screens/settings_screen.dart) · aiApprovalMaxRisk | 始终可见 |
| settings.global-prompt-entry | Open / 全局审批 Prompt | [L51](../lib/src/screens/settings_screen.dart) · aiApprovalPrompt | 始终可见 |
| settings.notification | Field / 通知声音 | [L1063](../lib/src/screens/settings_screen.dart) · notificationSoundAll | 始终可见 |
| settings.autospeak | Setting / 自动播报 Agent 回复 | [L65](../lib/src/screens/settings_screen.dart) · autoSpeakReplies | 始终可见 |
| settings.compress | Setting / 压缩 AI 回复 | [L1113](../lib/src/screens/settings_screen.dart) · compressReplies | 始终可见 |
| settings.compress-length | Field / 压缩回复最大字数 | [L1126](../lib/src/screens/settings_screen.dart) · compressReplyMaxChars | 始终可见 |
| settings.language | Field / 应用语言 | [L778](../lib/src/screens/settings_screen.dart) · languageSystem | 始终可见 |
| settings.theme | Field / 主题 | [L806](../lib/src/screens/settings_screen.dart) · themeFollowSystem | 始终可见 |
| settings.error-reporting | Setting / 错误报告 | [L826](../lib/src/screens/settings_screen.dart) · error-reporting-toggle | 始终可见 |
| settings.bridge | Field / Bridge 地址 | [L836](../lib/src/screens/settings_screen.dart) · settings-bridge-url | 始终可见 |
| settings.client-id | Row | [L859](../lib/src/screens/settings_screen.dart) · _regenerateClientId | 始终可见 |
| settings.update | Card | [L1184](../lib/src/screens/settings_screen.dart) · checkAppUpdate | 始终可见 |
| state.settings-saving | Column | [L71](../lib/src/screens/settings_screen.dart) · _saving | 设置保存请求未结束 |
| state.settings-ai-providers-loading | Column | [L59](../lib/src/screens/settings_screen.dart) · _loadingModelProviders | 正在读取已配置且可用的模型服务 |
| state.settings-ai-providers-error | Column | [L62](../lib/src/screens/settings_screen.dart) · _modelProvidersError | 已配置服务列表请求失败 |
| state.settings-no-model-service | Column | [L902](../lib/src/screens/settings_screen.dart) · noConfiguredModels | 没有已启用的模型服务 |
| state.settings-ai-models-loading | Column | [L60](../lib/src/screens/settings_screen.dart) · _loadingAiApprovalModels | 已选模型服务，其模型列表尚未返回 |
| state.settings-no-ai-models | Column | [L957](../lib/src/screens/settings_screen.dart) · noApprovalModels | 已选服务未返回模型 |
| state.update-checking | Column | [L74](../lib/src/screens/settings_screen.dart) · _checkingUpdate | 更新检查请求未结束 |
| state.update-not-found | Column | [L1539](../lib/src/screens/settings_screen.dart) · targetVersionNotFound | 目标版本不存在或不可下载 |
| state.update-force | Column | [L1587](../lib/src/screens/settings_screen.dart) · update.force | 服务返回 force=true |
| state.update-web | Column | [L1182](../lib/src/screens/settings_screen.dart) · onPressed: kIsWeb | 当前运行在 Web 平台 |
| state.update-available | Column | [L1547](../lib/src/screens/settings_screen.dart) · _showUpdateDialog | 发现新版本且 force=false |
| state.update-downloading | Column | [L1621](../lib/src/screens/settings_screen.dart) · _downloadAndInstallUpdate | 已确认更新，Android 正在下载应用包 |
| state.update-downgrade | Column | [L1603](../lib/src/screens/settings_screen.dart) · targetVersionDowngradeWarning | 指定版本比当前已安装版本更旧 |

## lib/src/widgets/new_session_flow.dart

| 功能组 | 画稿位置 | 源码依据 | 显示条件 |
| --- | --- | --- | --- |
| create.choose-project | Column | [L53](../lib/src/widgets/new_session_flow.dart) · SelectProjectDialog | 始终可见 |
| create.new-project-entry | Button / 创建新项目 | [L178](../lib/src/widgets/new_session_flow.dart) · createNewProject | 始终可见 |
| create.project-name | Field / 项目名称 | [L222](../lib/src/widgets/new_session_flow.dart) · _nameController | 始终可见 |
| create.project-path | Field / 项目根路径 | [L223](../lib/src/widgets/new_session_flow.dart) · _pathController | 始终可见 |
| create.project-submit | Button / 创建项目 | [L46](../lib/src/widgets/new_session_flow.dart) · createProject | 始终可见 |

## lib/src/widgets/create_session_dialog.dart

| 功能组 | 画稿位置 | 源码依据 | 显示条件 |
| --- | --- | --- | --- |
| create.session-title | Field / 会话标题（可选） | [L32](../lib/src/widgets/create_session_dialog.dart) · _titleController | 始终可见 |
| create.agent | Field / Agent | [L38](../lib/src/widgets/create_session_dialog.dart) · _agentOptions | 始终可见 |
| create.provider | Field / 模型供应商 | [L55](../lib/src/widgets/create_session_dialog.dart) · _providers | 始终可见 |
| create.model | Field / 模型（可选） | [L37](../lib/src/widgets/create_session_dialog.dart) · _providerModels | 始终可见 |
| create.agent-install | Card | [L42](../lib/src/widgets/create_session_dialog.dart) · _installingAgent | 仅 Agent 未安装、安装中或出错时出现 |
| create.session-submit | Button / 创建会话 | [L99](../lib/src/widgets/create_session_dialog.dart) · _selectedAgentInstalled | Agent 可用且必需信息有效时启用 |
| state.create-agents-loading | Column | [L41](../lib/src/widgets/create_session_dialog.dart) · _loadingAgents | Agent 列表首次加载中 |
| state.create-agent-missing | Column | [L99](../lib/src/widgets/create_session_dialog.dart) · _selectedAgentInstalled | 选中的 Agent installed=false |
| state.create-agent-installing | Column | [L42](../lib/src/widgets/create_session_dialog.dart) · _installingAgent | 安装请求尚未完成 |
| state.create-agent-install-error | Column | [L43](../lib/src/widgets/create_session_dialog.dart) · _agentError | 安装返回失败或网络异常 |
| state.create-models-loading | Column | [L40](../lib/src/widgets/create_session_dialog.dart) · _loadingModels | 选择供应商后正在读取其模型 |
| state.create-provider-default | Column | [L74](../lib/src/widgets/create_session_dialog.dart) · _normalizeProviderSelection | 没有符合所选 Agent 格式的供应商 |

## lib/src/widgets/navigation_panel.dart

| 功能组 | 画稿位置 | 源码依据 | 显示条件 |
| --- | --- | --- | --- |
| navigation.routes | Card | [L16](../lib/src/widgets/navigation_panel.dart) · onNavigateHome | 始终可见 |
| navigation.recent-sessions | Column | [L20](../lib/src/widgets/navigation_panel.dart) · recentSessions | 始终可见 |
| navigation.recent-projects | Column | [L19](../lib/src/widgets/navigation_panel.dart) · recentProjects | 始终可见 |
| navigation.context-actions | Card | [L293](../lib/src/widgets/navigation_panel.dart) · copySessionId | 会话 ID 只在有运行时引用时显示 |
| navigation.new-session | Button / 新建会话 | [L25](../lib/src/widgets/navigation_panel.dart) · onNewSession | 始终可见 |

## lib/src/screens/ai_approval_prompt_screen.dart

| 功能组 | 画稿位置 | 源码依据 | 显示条件 |
| --- | --- | --- | --- |
| settings.global-prompt | Field / 审批 Prompt | [L10](../lib/src/screens/ai_approval_prompt_screen.dart) · initialPrompt | 始终可见 |

## lib/src/screens/project_ai_approval_prompt_screen.dart

| 功能组 | 画稿位置 | 源码依据 | 显示条件 |
| --- | --- | --- | --- |
| project.prompt-edit | Field / 项目级审批 Prompt | [L96](../lib/src/screens/project_ai_approval_prompt_screen.dart) · projectAiApprovalPrompt | 始终可见 |

## lib/src/screens/speech_settings_screen.dart

| 功能组 | 画稿位置 | 源码依据 | 显示条件 |
| --- | --- | --- | --- |
| speech.routes | Column | [L609](../lib/src/screens/speech_settings_screen.dart) · _buildSpeechRoutingContent | 始终可见 |
| speech.import | Button / 导入插件清单 | [L996](../lib/src/screens/speech_settings_screen.dart) · pluginManifest | 始终可见 |
| speech.playback-prompt | Setting / 为语音播报优化回复 | [L124](../lib/src/screens/speech_settings_screen.dart) · speechPlaybackPrompt | 始终可见 |
| speech.credentials | Card | [L2501](../lib/src/screens/speech_settings_screen.dart) · _buildSpeechPluginApiKeyCard | 始终可见 |
| speech.plugin-lifecycle | Row | [L2385](../lib/src/screens/speech_settings_screen.dart) · uninstall | 始终可见 |
| speech.service-lifecycle | Row | [L2853](../lib/src/screens/speech_settings_screen.dart) · startService | 仅带有对应服务动作的插件显示 |
| speech.tests | Card | [L2125](../lib/src/screens/speech_settings_screen.dart) · testRealtimeAsr | 始终可见 |
| speech.test-feedback | 请先补充插件要求的必填设置。 | [L1449](../lib/src/screens/speech_settings_screen.dart) · fillRequiredPluginSettings | 始终可见 |
| speech.bridge-details | Card | [L3455](../lib/src/screens/speech_settings_screen.dart) · _buildLocalBridgeModelsPanel | 始终可见 |
| speech.speaker | Card | [L3541](../lib/src/screens/speech_settings_screen.dart) · _buildSpeakerFilterTile | 需先安装声纹模型并录入说话人；无模型时提供下载 |
| speech.voice | Card | [L630](../lib/src/screens/speech_settings_screen.dart) · _buildLocalBridgeTtsVoiceContent | 仅选择本地 Bridge TTS 时显示 |
| speech.call-settings | Card | [L646](../lib/src/screens/speech_settings_screen.dart) · _buildCallModeContent | 始终可见 |
| speech.test-realtime-controls | Card | [L1959](../lib/src/screens/speech_settings_screen.dart) · startingRealtimeSpeechTest | 始终可见 |
| speech.test-batch-controls | Card | [L1747](../lib/src/screens/speech_settings_screen.dart) · stopAndTranscribe | 始终可见 |
| speech.test-tts-controls | Card | [L1639](../lib/src/screens/speech_settings_screen.dart) · testText | 始终可见 |
| speech.model-details | Card | [L3537](../lib/src/screens/speech_settings_screen.dart) · _buildBridgeDetailsTile | 始终可见 |
| speech.delete-model | Card | [L3775](../lib/src/screens/speech_settings_screen.dart) · _deleteSpeechModel | 始终可见 |
| speech.download-speaker-model | Card | [L3863](../lib/src/screens/speech_settings_screen.dart) · _downloadSpeechModel | 始终可见 |
| speech.speaker-enable | Setting / 仅识别目标说话人 | [L3820](../lib/src/screens/speech_settings_screen.dart) · targetSpeakerOnly | 始终可见 |
| speech.speaker-enroll | Card | [L3891](../lib/src/screens/speech_settings_screen.dart) · _toggleSpeakerEnrollmentRecording | 始终可见 |
| speech.speaker-delete | Card | [L3946](../lib/src/screens/speech_settings_screen.dart) · _deleteSpeaker | 始终可见 |
| speech.speaker-threshold | Card | [L3830](../lib/src/screens/speech_settings_screen.dart) · _speakerFilter.threshold | 始终可见 |
| state.speech-system-unavailable | Column | [L171](../lib/src/screens/speech_settings_screen.dart) · _systemAsrSupportedOnPlatform | 当前平台不支持所选系统语音能力 |
| state.speech-plugin-missing | Column | [L1147](../lib/src/screens/speech_settings_screen.dart) · selectedPluginNotInstalled | 选择的插件尚未安装 |
| state.speech-credentials-required | Column | [L1449](../lib/src/screens/speech_settings_screen.dart) · fillRequiredPluginSettings | 插件清单要求的配置项缺失 |
| state.speech-credentials-saving | Column | [L105](../lib/src/screens/speech_settings_screen.dart) · _savingPluginConfigurationIds | 插件配置正在保存 |
| state.speech-service-error | Column | [L1920](../lib/src/screens/speech_settings_screen.dart) · realtimeAsrAuthenticationRejected | 实时 ASR 认证被服务拒绝 |
| state.speech-test-recording | Column | [L1845](../lib/src/screens/speech_settings_screen.dart) · recordingSpeakThenStop | 已开始录音，尚未停止 |
| state.speech-test-transcribing | Column | [L1756](../lib/src/screens/speech_settings_screen.dart) · transcribingRecordedAudio | 录音已停止，正在等待转写结果 |
| state.speech-test-playing | Column | [L1593](../lib/src/screens/speech_settings_screen.dart) · playbackStartedSuccessfully | 测试语音已成功开始播放 |
| state.speech-local-unreachable | Column | [L145](../lib/src/screens/speech_settings_screen.dart) · _speechStatusError | 本地语音状态接口失败 |
| state.speech-no-speaker | Column | [L3822](../lib/src/screens/speech_settings_screen.dart) · enrollSpeakerBeforeFiltering | 说话人列表为空 |
| state.speech-speaker-recording | Column | [L136](../lib/src/screens/speech_settings_screen.dart) · _speakerEnrollmentRecording | 正在录制声纹样本 |
| state.speech-speaker-saving | Column | [L137](../lib/src/screens/speech_settings_screen.dart) · _speakerEnrollmentSaving | 声纹录入请求未完成 |
| state.speech-model-queued | Column | [L5012](../lib/src/screens/speech_settings_screen.dart) · speechDownloadStatusQueued | 模型任务状态为 queued |
| state.speech-model-downloading | Column | [L5013](../lib/src/screens/speech_settings_screen.dart) · speechDownloadStatusDownloading | 模型任务状态为 downloading |
| state.speech-model-extracting | Column | [L5014](../lib/src/screens/speech_settings_screen.dart) · speechDownloadStatusExtracting | 模型任务状态为 extracting |
| state.speech-model-verifying | Column | [L5015](../lib/src/screens/speech_settings_screen.dart) · speechDownloadStatusVerifying | 模型任务状态为 verifying |
| state.speech-model-ready | Column | [L5016](../lib/src/screens/speech_settings_screen.dart) · speechDownloadStatusCompleted | 模型任务状态为 completed |
| state.speech-realtime-starting | Column | [L1959](../lib/src/screens/speech_settings_screen.dart) · startingRealtimeSpeechTest | 测试正在连接实时语音服务 |
| state.speech-realtime-listening | Column | [L2085](../lib/src/screens/speech_settings_screen.dart) · listeningSpeakShortSentence | 实时语音测试已开始并等待转写 |

## lib/src/screens/model_provider_screen.dart

| 功能组 | 画稿位置 | 源码依据 | 显示条件 |
| --- | --- | --- | --- |
| provider.list | Card | [L309](../lib/src/screens/model_provider_screen.dart) · _buildProviderList | 始终可见 |
| provider.order | Card | [L147](../lib/src/screens/model_provider_screen.dart) · _onReorderItem | 始终可见 |
| provider.add | Button / 添加供应商 | [L75](../lib/src/screens/model_provider_screen.dart) · _addProvider | 始终可见 |
| provider.name | Field / 名称 | [L774](../lib/src/screens/model_provider_screen.dart) · _nameController | 始终可见 |
| provider.baseurl | Field / 基础 URL | [L775](../lib/src/screens/model_provider_screen.dart) · _baseUrlController | 始终可见 |
| provider.key | Field / API 密钥 | [L776](../lib/src/screens/model_provider_screen.dart) · _apiKeyController | 始终可见 |
| provider.model | Field / 模型（可选） | [L777](../lib/src/screens/model_provider_screen.dart) · _modelController | 始终可见 |
| provider.format | Field / API 格式 | [L899](../lib/src/screens/model_provider_screen.dart) · ApiFormat.values | 始终可见 |
| provider.enabled | Setting / 启用 | [L779](../lib/src/screens/model_provider_screen.dart) · _enabled | 始终可见 |
| state.provider-loading | Column | [L31](../lib/src/screens/model_provider_screen.dart) · _loading | 首次读取模型供应商中 |
| state.provider-empty | Column | [L429](../lib/src/screens/model_provider_screen.dart) · noProvidersYet | 读取成功且供应商列表为空 |
| state.provider-load-error | Column | [L304](../lib/src/screens/model_provider_screen.dart) · _buildErrorState | 模型供应商接口失败 |
| state.provider-required | Column | [L854](../lib/src/screens/model_provider_screen.dart) · fieldRequired | 名称或基础 URL 为空 |
| state.provider-delete-confirm | Column | [L104](../lib/src/screens/model_provider_screen.dart) · _deleteProvider | 已选择删除某个供应商，尚未确认 |

## lib/src/screens/pi_plugins_screen.dart

| 功能组 | 画稿位置 | 源码依据 | 显示条件 |
| --- | --- | --- | --- |
| pi.permissions | Card | [L127](../lib/src/screens/pi_plugins_screen.dart) · piPluginPermissionWarning | 始终可见 |
| pi.list | Card | [L197](../lib/src/screens/pi_plugins_screen.dart) · _pluginCard | 始终可见 |
| pi.feedback | 更改在下一个 turn 生效。 | [L282](../lib/src/screens/pi_plugins_screen.dart) · piPluginNextTurnHint | 始终可见 |
| pi.refresh | Button / 刷新列表 | [L26](../lib/src/screens/pi_plugins_screen.dart) · _load | 始终可见 |
| pi.install-entry | Button / 安装插件 | [L81](../lib/src/screens/pi_plugins_screen.dart) · _install | 始终可见 |
| pi.source | Field / 来源 | [L395](../lib/src/screens/pi_plugins_screen.dart) · piPluginSource | 始终可见 |
| pi.upload | Button / 上传插件文件 | [L341](../lib/src/screens/pi_plugins_screen.dart) · chooseFile | 始终可见 |
| pi.scope | Card | [L404](../lib/src/screens/pi_plugins_screen.dart) · _ScopeFields | 始终可见 |
| pi.config | Field / 配置（JSON 对象） | [L353](../lib/src/screens/pi_plugins_screen.dart) · jsonDecode(config.text) | 始终可见 |
| state.pi-loading | Column | [L178](../lib/src/screens/pi_plugins_screen.dart) · if (_loading) | 首次读取插件列表中 |
| state.pi-empty | Column | [L192](../lib/src/screens/pi_plugins_screen.dart) · piPluginEmpty | 插件接口成功返回空列表 |
| state.pi-load-error | Column | [L183](../lib/src/screens/pi_plugins_screen.dart) · piPluginLoadFailed | 插件列表接口失败 |
| state.pi-installing | Column | [L157](../lib/src/screens/pi_plugins_screen.dart) · _busy.contains('__install__') | 安装请求未完成 |
| state.pi-plugin-busy | Column | [L205](../lib/src/screens/pi_plugins_screen.dart) · final busy = _busy.contains(plugin.id) | 启用、校验、配置或卸载当前插件的请求未完成 |
| state.pi-validation-error | Column | [L254](../lib/src/screens/pi_plugins_screen.dart) · plugin.validationError | 插件返回非空的校验错误 |
| state.pi-json-error | Column | [L355](../lib/src/screens/pi_plugins_screen.dart) · Configuration must be a JSON object | 安装或编辑时的配置解析失败 |

## lib/src/screens/acceptance_screen.dart

| 功能组 | 画稿位置 | 源码依据 | 显示条件 |
| --- | --- | --- | --- |
| acceptance.installation | Card | [L89](../lib/src/screens/acceptance_screen.dart) · getAcceptanceInstallation | 始终可见 |
| acceptance.history | Card | [L342](../lib/src/screens/acceptance_screen.dart) · acceptanceHistory | 始终可见 |
| acceptance.start-entry | Button / 开始验收 | [L32](../lib/src/screens/acceptance_screen.dart) · acceptanceStart | 环境就绪且有可用项目时启用 |
| acceptance.project | Field / 项目 | [L503](../lib/src/screens/acceptance_screen.dart) · acceptanceProject | 始终可见 |
| acceptance.requirements | Field / 本次验收重点（可选） | [L538](../lib/src/screens/acceptance_screen.dart) · acceptanceRequirementsInput | 始终可见 |
| acceptance.advanced | Card | [L547](../lib/src/screens/acceptance_screen.dart) · acceptanceAdvanced | 始终可见 |
| acceptance.manual | Open / 打开远程桌面 | [L217](../lib/src/screens/acceptance_screen.dart) · acceptanceRemoteDesktop | 始终可见 |
| plan.retry | Button / 重新生成测试用例 | [L1001](../lib/src/screens/acceptance_screen.dart) · retryAcceptanceTestPlan | 生成失败时提供重新生成入口 |
| acceptance.requirement-summary | Card | [L918](../lib/src/screens/acceptance_screen.dart) · acceptanceRequirementsTitle | 始终可见 |
| acceptance.desktop | Card | [L697](../lib/src/screens/acceptance_screen.dart) · acceptanceTakeControl | 始终可见 |
| acceptance.checklist | Card | [L1060](../lib/src/screens/acceptance_screen.dart) · acceptanceChecks | 始终可见 |
| acceptance.release | Button / 交还自动化控制权 | [L1052](../lib/src/screens/acceptance_screen.dart) · acceptanceReleaseControl | 手动接管后显示 |
| acceptance.stop | Button / 停止验收 | [L35](../lib/src/screens/acceptance_screen.dart) · acceptanceStop | 始终可见 |
| acceptance.review | Card | [L1186](../lib/src/screens/acceptance_screen.dart) · acceptanceReview | 始终可见 |
| acceptance.artifacts | Card | [L1088](../lib/src/screens/acceptance_screen.dart) · acceptanceDownload | 始终可见 |
| acceptance.run-details | Open / 运行详情 | [L1210](../lib/src/screens/acceptance_screen.dart) · acceptanceDetails | 始终可见 |
| state.acceptance-phase-not_installed | Column | [L27](../lib/src/screens/acceptance_screen.dart) · 'not_installed' | phase=not_installed |
| state.acceptance-phase-checking | Column | [L28](../lib/src/screens/acceptance_screen.dart) · 'checking' | phase=checking |
| state.acceptance-phase-preparing | Column | [L29](../lib/src/screens/acceptance_screen.dart) · 'preparing' | phase=preparing |
| state.acceptance-phase-verifying | Column | [L30](../lib/src/screens/acceptance_screen.dart) · 'verifying' | phase=verifying |
| state.acceptance-phase-ready | Column | [L31](../lib/src/screens/acceptance_screen.dart) · 'ready' | phase=ready |
| state.acceptance-phase-starting | Column | [L32](../lib/src/screens/acceptance_screen.dart) · 'starting' | phase=starting |
| state.acceptance-phase-planning | Column | [L33](../lib/src/screens/acceptance_screen.dart) · 'planning' | phase=planning |
| state.acceptance-phase-running | Column | [L34](../lib/src/screens/acceptance_screen.dart) · 'running' | phase=running |
| state.acceptance-phase-stopping | Column | [L35](../lib/src/screens/acceptance_screen.dart) · 'stopping' | phase=stopping |
| state.acceptance-phase-completed | Column | [L36](../lib/src/screens/acceptance_screen.dart) · 'completed' | phase=completed |
| state.acceptance-phase-failed | Column | [L37](../lib/src/screens/acceptance_screen.dart) · 'failed' | phase=failed |
| state.acceptance-creating-blocked | Column | [L433](../lib/src/screens/acceptance_screen.dart) · acceptance-creation-loading | creating=true，显示阻止点击与返回的进度遮罩 |
| state.acceptance-empty | Column | [L333](../lib/src/screens/acceptance_screen.dart) · acceptanceEmpty | 读取成功且 runs 为空 |
| state.plan-generation-error | Column | [L1001](../lib/src/screens/acceptance_screen.dart) · retryAcceptanceTestPlan | planning 阶段生成失败且无 testPlan |
| state.desktop-manual-control | Column | [L1052](../lib/src/screens/acceptance_screen.dart) · acceptanceReleaseControl | 已从自动化切换至手动桌面控制 |
| state.desktop-automation-error | Column | [L980](../lib/src/screens/acceptance_screen.dart) · acceptanceAutomationFailedHint | 自动检查失败，但运行仍在进行 |
| state.acceptance-human-review | Column | [L796](../lib/src/screens/acceptance_screen.dart) · acceptanceAwaitingReview | 已产生运行结果，尚未人工确认 |
| state.acceptance-evidence-empty | Column | [L1125](../lib/src/screens/acceptance_screen.dart) · acceptanceNoEvidence | 没有可展示的证据附件 |
| state.acceptance-evidence-exporting | Column | [L1120](../lib/src/screens/acceptance_screen.dart) · acceptanceExportEvidence | 生成录像与报告请求未返回 |

## lib/src/screens/acceptance_environment_screen.dart

| 功能组 | 画稿位置 | 源码依据 | 显示条件 |
| --- | --- | --- | --- |
| environment.mode | Field / 环境模式 | [L139](../lib/src/screens/acceptance_environment_screen.dart) · acceptance-environment-mode | 始终可见 |
| environment.dockerfile | Field / Dockerfile | [L177](../lib/src/screens/acceptance_environment_screen.dart) · acceptance-environment-dockerfile | 仅 Dockerfile 模式显示 |
| environment.image | Field / 已有镜像 | [L194](../lib/src/screens/acceptance_environment_screen.dart) · available | 仅 image 模式显示 |
| environment.rebuild | Setting / 下次重新识别并准备环境 | [L237](../lib/src/screens/acceptance_environment_screen.dart) · acceptanceEnvironmentRebuild | 始终可见 |
| environment.logs | Open / 运行详情 | [L347](../lib/src/screens/acceptance_environment_screen.dart) · acceptanceEnvironmentLogs | 始终可见 |
| environment.save | Button / 保存环境配置 | [L87](../lib/src/screens/acceptance_environment_screen.dart) · acceptanceEnvironmentSave | 始终可见 |
| state.environment-invalid | Column | [L70](../lib/src/screens/acceptance_environment_screen.dart) · acceptanceEnvironmentRequired | Dockerfile 或已有镜像模式缺少必填内容 |

## lib/src/screens/acceptance_plan_card.dart

| 功能组 | 画稿位置 | 源码依据 | 显示条件 |
| --- | --- | --- | --- |
| plan.cases | Card | [L120](../lib/src/screens/acceptance_plan_card.dart) · acceptance-case-edit- | 审批前可编辑，最多 32 条用例 |
| plan.revise | Card | [L201](../lib/src/screens/acceptance_plan_card.dart) · acceptance-plan-send | 始终可见 |
| plan.approve | Button / 确认用例并开始验收 | [L225](../lib/src/screens/acceptance_plan_card.dart) · confirmAcceptanceTestPlan | 始终可见 |
| plan.case-title | Field / 用例标题 | [L287](../lib/src/screens/acceptance_plan_card.dart) · acceptance-case-title | 始终可见 |
| plan.case-steps | Field / 操作步骤 · 每行一步 | [L295](../lib/src/screens/acceptance_plan_card.dart) · acceptance-case-steps | 始终可见 |
| plan.case-expected | Field / 预期结果 | [L317](../lib/src/screens/acceptance_plan_card.dart) · acceptance-case-expected | 始终可见 |
| plan.case-save | Button / 保存 | [L330](../lib/src/screens/acceptance_plan_card.dart) · acceptance-case-save | 始终可见 |
| state.plan-awaiting-confirmation | Column | [L221](../lib/src/screens/acceptance_plan_card.dart) · acceptance-plan-confirm | 测试计划已生成且尚未 approved |
| state.plan-revising | Column | [L78](../lib/src/screens/acceptance_plan_card.dart) · revising_plan | automation=revising_plan |
| state.plan-case-invalid | Column | [L312](../lib/src/screens/acceptance_plan_card.dart) · acceptancePlanStepsLimit | 标题 / 预期缺失，或步骤数量、长度超出限制 |

## lib/src/screens/acceptance_video_screen.dart

| 功能组 | 画稿位置 | 源码依据 | 显示条件 |
| --- | --- | --- | --- |
| acceptance.playback | 回放支持播放 / 暂停、重播与进度拖动。 | [L129](../lib/src/screens/acceptance_video_screen.dart) · allowScrubbing | 仅已生成录像可回放 |
| video.scrub | Column | [L129](../lib/src/screens/acceptance_video_screen.dart) · allowScrubbing | 始终可见 |
| video.controls | Row | [L152](../lib/src/screens/acceptance_video_screen.dart) · player.seekTo | 始终可见 |
| video.error | Card | [L108](../lib/src/screens/acceptance_video_screen.dart) · acceptanceVideoError | 加载失败时替代播放器 |
| state.recording-loading | Column | [L115](../lib/src/screens/acceptance_video_screen.dart) · !player.value.isInitialized | 播放器未创建或尚未完成初始化 |
| state.recording-error | Column | [L108](../lib/src/screens/acceptance_video_screen.dart) · acceptanceVideoError | 下载、初始化或读取录像失败 |

## lib/src/widgets/session_execution_status_card.dart

| 功能组 | 画稿位置 | 源码依据 | 显示条件 |
| --- | --- | --- | --- |
| state.execution-starting | Column | [L111](../lib/src/widgets/session_execution_status_card.dart) · ExecutionPhase.starting | phase=starting；阶段与最近进展均超过 60 秒 才提示长等待 |
| state.execution-thinking | Column | [L112](../lib/src/widgets/session_execution_status_card.dart) · ExecutionPhase.thinking | phase=thinking；阶段与最近进展均超过 180 秒 才提示长等待 |
| state.execution-runningCommand | Column | [L113](../lib/src/widgets/session_execution_status_card.dart) · ExecutionPhase.runningCommand | phase=runningCommand；阶段与最近进展均超过 300 秒 才提示长等待 |
| state.execution-awaitingApproval | Column | [L114](../lib/src/widgets/session_execution_status_card.dart) · ExecutionPhase.awaitingApproval | phase=awaitingApproval；此阶段不触发长等待提醒 |
| state.execution-retrying | Column | [L115](../lib/src/widgets/session_execution_status_card.dart) · ExecutionPhase.retrying | phase=retrying；阶段与最近进展均超过 120 秒 才提示长等待 |
| state.execution-waitingForTool | Column | [L116](../lib/src/widgets/session_execution_status_card.dart) · ExecutionPhase.waitingForTool | phase=waitingForTool；阶段与最近进展均超过 120 秒 才提示长等待 |
| state.execution-background | Column | [L117](../lib/src/widgets/session_execution_status_card.dart) · ExecutionPhase.background | phase=background；阶段与最近进展均超过 300 秒 才提示长等待 |
| state.execution-unconfirmed | Column | [L118](../lib/src/widgets/session_execution_status_card.dart) · ExecutionPhase.unconfirmed | phase=unconfirmed；阶段与最近进展均超过 30 秒 才提示长等待 |
| state.execution-attention | Column | [L102](../lib/src/widgets/session_execution_status_card.dart) · health.needsAttention | 阶段与最近进展均超过对应阈值，且提醒未暂缓 |
| state.execution-checking | Column | [L30](../lib/src/widgets/session_execution_status_card.dart) · _checking | _checking=true，且长等待提醒可见 |
| state.execution-check-pending | Column | [L120](../lib/src/widgets/session_execution_status_card.dart) · checkPending | checkPending=true，_checking=false，长等待提醒可见 |
| state.execution-quiet | Column | [L32](../lib/src/widgets/session_execution_status_card.dart) · _quietUntil | 选择继续等待后，5 分钟内暂缓长等待提醒 |
| state.execution-recovering | Column | [L31](../lib/src/widgets/session_execution_status_card.dart) · _recovering | 恢复任务请求处理中 |
| state.execution-check-provider_waiting_on_approval | Column | [L124](../lib/src/widgets/session_execution_status_card.dart) · provider_waiting_on_approval | checkError=provider_waiting_on_approval，且长等待提醒可见 |
| state.execution-check-provider_waiting_on_user_input | Column | [L125](../lib/src/widgets/session_execution_status_card.dart) · provider_waiting_on_user_input | checkError=provider_waiting_on_user_input，且长等待提醒可见 |
| state.execution-check-provider_idle_without_turn_completion | Column | [L126](../lib/src/widgets/session_execution_status_card.dart) · provider_idle_without_turn_completion | checkError=provider_idle_without_turn_completion，且长等待提醒可见 |
| state.execution-check-provider_system_error | Column | [L127](../lib/src/widgets/session_execution_status_card.dart) · provider_system_error | checkError=provider_system_error，且长等待提醒可见 |
| state.execution-check-timeout | Column | [L131](../lib/src/widgets/session_execution_status_card.dart) · timeout | checkError=timeout，且长等待提醒可见 |
| state.execution-check-unavailable | Column | [L69](../lib/src/widgets/session_execution_status_card.dart) · executionCheckUnavailable | 主动检查不可用，已刷新现有会话状态 |
| state.execution-recovery-failed | Column | [L90](../lib/src/widgets/session_execution_status_card.dart) · executionRecoveryFailed | stopAndContinue 请求失败，保留当前执行状态 |

## lib/src/message_image_paths.dart

| 功能组 | 画稿位置 | 源码依据 | 显示条件 |
| --- | --- | --- | --- |
| state.render-image-markdown | Parsed output | [L89](../lib/src/message_image_paths.dart) · _markdownLinkPattern | 消息包含标准 Markdown 图片标记 |
| state.render-image-bare | Parsed output | [L111](../lib/src/message_image_paths.dart) · _bareImagePathPattern | 正文出现支持的图片文件路径 |
| state.render-image-inline-path | Parsed output | [L97](../lib/src/message_image_paths.dart) · _inlineCodePattern | 行内代码的值可以解析为媒体路径 |
| state.render-image-data | Parsed output | [L60](../lib/src/message_image_paths.dart) · _tryParseDataUri | data:image/*;base64, 后的内容可成功解码 |
| state.render-image-animated | Parsed output | [L44](../lib/src/message_image_paths.dart) · isAnimatedImage | GIF 或 WebP 引用进入预览 |
| state.render-image-deduplicate | Parsed output | [L86](../lib/src/message_image_paths.dart) · matches.putIfAbsent | 同一路径被多种语法重复引用 |

## 核对边界

- 移动端功能采用新的信息组织；底部导航复用现有路由，部分设置分组在稿件中单独展开。
- 项目页的当前入口为手动远程桌面（automatic=false）；会话及全局设置保留自动验收入口。
- 审批中的本会话允许、始终允许、取消、远程可处理状态按请求能力显示；已提交时等待服务确认。
- 原生平台、Web、Agent 能力及插件清单会限制可用操作，具体条件记录于表中及对应画板说明。
- 宽屏侧栏展开 / 折叠属于桌面布局，本次移动端稿不将其新增为手机功能。
- sourceSha256 和 nodeIds 存于 coverage.json；核对表记录的源码变化后，应重新核对相关画面。
