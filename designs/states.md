# Omni Code · 独立状态清单

核对日期：2026-11-03。共 247 个独立状态。可在 [状态浏览器](states.html) 按分类查看图片和条件。

每项分别记录触发、操作、禁用和隐藏内容。源码行号与节点 ID 存在 states.json；状态设计按当前工作区代码核对，不穷举所有状态交叉组合。

## 会话主状态

| 状态 | 触发条件 | 可用操作 | 禁用 | 隐藏 | 源码依据 |
| --- | --- | --- | --- | --- | --- |
| [正在创建会话](states.html?id=session-creating#session-creating) | creatingSession=true | — | 附件、语音、输入 | 发送 | [lib/src/screens/session_detail_screen.dart:361](../lib/src/screens/session_detail_screen.dart#L361) · _creatingSession |
| [加载历史消息](states.html?id=session-loading#session-loading) | loadingMessages=true，显示消息骨架 | — | — | 发送 | [lib/src/screens/session_detail_screen.dart:305](../lib/src/screens/session_detail_screen.dart#L305) · _loadingMessages |
| [空会话 / 尚未开始](states.html?id=session-empty#session-empty) | idle，历史轮次为空 | 输入文字、录音、选择附件 | — | 停止、空草稿发送 | [lib/src/screens/session_detail_screen.dart:620](../lib/src/screens/session_detail_screen.dart#L620) · SessionStatus.idle |
| [本轮完成 / 空闲](states.html?id=session-idle#session-idle) | idle，已存在完成的回复 | 复制、播报、继续输入 | — | 停止 | [lib/src/screens/session_detail_screen.dart:620](../lib/src/screens/session_detail_screen.dart#L620) · SessionStatus.idle |
| [回复进行中](states.html?id=session-running#session-running) | status=running，有活跃轮次 | 停止、发送后续消息 | — | — | [lib/src/screens/session_detail_screen.dart:637](../lib/src/screens/session_detail_screen.dart#L637) · SessionStatus.running |
| [等待 Bridge 回复](states.html?id=session-waiting#session-waiting) | status=waiting，已提交且等待回复 | 停止、继续输入 | — | — | [lib/src/screens/session_detail_screen.dart:638](../lib/src/screens/session_detail_screen.dart#L638) · SessionStatus.waiting |
| [等待审批](states.html?id=session-awaiting-approval#session-awaiting-approval) | 存在可处理的 pendingApproval | 按请求能力处理审批、停止 | — | — | [lib/src/screens/session_detail_screen.dart:537](../lib/src/screens/session_detail_screen.dart#L537) · SessionStatus.awaitingApproval |
| [已中断](states.html?id=session-interrupted#session-interrupted) | status=interrupted | 发送新消息 | — | 停止 | [lib/src/screens/session_detail_screen.dart:660](../lib/src/screens/session_detail_screen.dart#L660) · SessionStatus.interrupted |
| [本轮失败](states.html?id=session-failed#session-failed) | status=failed，错误横幅不可直接关闭 | 查看实际错误、继续输入 | — | 关闭失败横幅 | [lib/src/screens/session_detail_screen.dart:970](../lib/src/screens/session_detail_screen.dart#L970) · SessionStatus.failed |
| [会话恢复异常](states.html?id=session-restore-failed#session-restore-failed) | 恢复失败：标题显示错误提示，保留已加载内容 | — | — | 虚构的恢复按钮 | [lib/src/screens/session_detail_screen.dart:354](../lib/src/screens/session_detail_screen.dart#L354) · _sessionRestoreError |
| [创建会话失败](states.html?id=session-create-failed#session-create-failed) | 初始化 Future 失败，保留错误原因 | — | — | 重复的创建提交 | [lib/src/screens/session_detail_screen.dart:6779](../lib/src/screens/session_detail_screen.dart#L6779) · createSessionFailed |
| [软键盘打开](states.html?id=session-keyboard#session-keyboard) | 输入框聚焦且软键盘显示；键盘为 Android 示例 | 发送、输入区设置、附件 | — | — | [lib/src/screens/session_detail_screen.dart:726](../lib/src/screens/session_detail_screen.dart#L726) · _composerHasInteractiveFocus |
| [软键盘与审批共存](states.html?id=session-keyboard-approval#session-keyboard-approval) | 软键盘显示；示例请求无命令且不支持会话允许 / 取消 | 批准、拒绝、发送、停止 | — | — | [lib/src/screens/session_detail_screen.dart:2546](../lib/src/screens/session_detail_screen.dart#L2546) · _buildPendingApprovalCard |

## 执行阶段

| 状态 | 触发条件 | 可用操作 | 禁用 | 隐藏 | 源码依据 |
| --- | --- | --- | --- | --- | --- |
| [等待任务启动](states.html?id=execution-starting#execution-starting) | phase=starting；阶段与最近进展均超过 60 秒 才提示长等待 | 重新检查 | — | — | [lib/src/widgets/session_execution_status_card.dart:111](../lib/src/widgets/session_execution_status_card.dart#L111) · ExecutionPhase.starting |
| [正在处理](states.html?id=execution-thinking#execution-thinking) | phase=thinking；阶段与最近进展均超过 180 秒 才提示长等待 | 重新检查 | — | — | [lib/src/widgets/session_execution_status_card.dart:112](../lib/src/widgets/session_execution_status_card.dart#L112) · ExecutionPhase.thinking |
| [命令执行中](states.html?id=execution-runningCommand#execution-runningCommand) | phase=runningCommand；阶段与最近进展均超过 300 秒 才提示长等待 | 重新检查 | — | — | [lib/src/widgets/session_execution_status_card.dart:113](../lib/src/widgets/session_execution_status_card.dart#L113) · ExecutionPhase.runningCommand |
| [等待审批](states.html?id=execution-awaitingApproval#execution-awaitingApproval) | phase=awaitingApproval；此阶段不触发长等待提醒 | 重新检查 | — | — | [lib/src/widgets/session_execution_status_card.dart:114](../lib/src/widgets/session_execution_status_card.dart#L114) · ExecutionPhase.awaitingApproval |
| [网络重试中](states.html?id=execution-retrying#execution-retrying) | phase=retrying；阶段与最近进展均超过 120 秒 才提示长等待 | 重新检查 | — | — | [lib/src/widgets/session_execution_status_card.dart:115](../lib/src/widgets/session_execution_status_card.dart#L115) · ExecutionPhase.retrying |
| [等待工具结果](states.html?id=execution-waitingForTool#execution-waitingForTool) | phase=waitingForTool；阶段与最近进展均超过 120 秒 才提示长等待 | 重新检查 | — | — | [lib/src/widgets/session_execution_status_card.dart:116](../lib/src/widgets/session_execution_status_card.dart#L116) · ExecutionPhase.waitingForTool |
| [等待后台任务](states.html?id=execution-background#execution-background) | phase=background；阶段与最近进展均超过 300 秒 才提示长等待 | 重新检查 | — | — | [lib/src/widgets/session_execution_status_card.dart:117](../lib/src/widgets/session_execution_status_card.dart#L117) · ExecutionPhase.background |
| [执行状态待确认](states.html?id=execution-unconfirmed#execution-unconfirmed) | phase=unconfirmed；阶段与最近进展均超过 30 秒 才提示长等待 | 重新检查 | — | — | [lib/src/widgets/session_execution_status_card.dart:118](../lib/src/widgets/session_execution_status_card.dart#L118) · ExecutionPhase.unconfirmed |
| [长时间没有新进展](states.html?id=execution-attention#execution-attention) | 阶段与最近进展均超过对应阈值，且提醒未暂缓 | 重新检查、继续等待、停止本轮后继续 | — | — | [lib/src/widgets/session_execution_status_card.dart:102](../lib/src/widgets/session_execution_status_card.dart#L102) · health.needsAttention |
| [主动检查请求处理中](states.html?id=execution-checking#execution-checking) | _checking=true，且长等待提醒可见 | — | 重新检查、继续等待、停止本轮后继续 | — | [lib/src/widgets/session_execution_status_card.dart:30](../lib/src/widgets/session_execution_status_card.dart#L30) · _checking |
| [检查已发出 / 等待结果](states.html?id=execution-check-pending#execution-check-pending) | checkPending=true，_checking=false，长等待提醒可见 | 继续等待、停止本轮后继续 | 重新检查 | — | [lib/src/widgets/session_execution_status_card.dart:120](../lib/src/widgets/session_execution_status_card.dart#L120) · checkPending |
| [继续等待 / 提醒暂缓](states.html?id=execution-quiet#execution-quiet) | 选择继续等待后，5 分钟内暂缓长等待提醒 | 重新检查 | — | 长等待强调样式 | [lib/src/widgets/session_execution_status_card.dart:32](../lib/src/widgets/session_execution_status_card.dart#L32) · _quietUntil |
| [停止并继续中](states.html?id=execution-recovering#execution-recovering) | 恢复任务请求处理中 | — | 全部执行恢复操作 | — | [lib/src/widgets/session_execution_status_card.dart:31](../lib/src/widgets/session_execution_status_card.dart#L31) · _recovering |
| [执行端等待审批](states.html?id=execution-check-provider_waiting_on_approval#execution-check-provider_waiting_on_approval) | checkError=provider_waiting_on_approval，且长等待提醒可见 | 重新检查、继续等待、停止本轮后继续 | — | — | [lib/src/widgets/session_execution_status_card.dart:124](../lib/src/widgets/session_execution_status_card.dart#L124) · provider_waiting_on_approval |
| [执行端等待补充信息](states.html?id=execution-check-provider_waiting_on_user_input#execution-check-provider_waiting_on_user_input) | checkError=provider_waiting_on_user_input，且长等待提醒可见 | 重新检查、继续等待、停止本轮后继续 | — | — | [lib/src/widgets/session_execution_status_card.dart:125](../lib/src/widgets/session_execution_status_card.dart#L125) · provider_waiting_on_user_input |
| [执行端已空闲](states.html?id=execution-check-provider_idle_without_turn_completion#execution-check-provider_idle_without_turn_completion) | checkError=provider_idle_without_turn_completion，且长等待提醒可见 | 重新检查、继续等待、停止本轮后继续 | — | — | [lib/src/widgets/session_execution_status_card.dart:126](../lib/src/widgets/session_execution_status_card.dart#L126) · provider_idle_without_turn_completion |
| [执行端发生异常](states.html?id=execution-check-provider_system_error#execution-check-provider_system_error) | checkError=provider_system_error，且长等待提醒可见 | 重新检查、继续等待、停止本轮后继续 | — | — | [lib/src/widgets/session_execution_status_card.dart:127](../lib/src/widgets/session_execution_status_card.dart#L127) · provider_system_error |
| [状态检查超时](states.html?id=execution-check-timeout#execution-check-timeout) | checkError=timeout，且长等待提醒可见 | 重新检查、继续等待、停止本轮后继续 | — | — | [lib/src/widgets/session_execution_status_card.dart:131](../lib/src/widgets/session_execution_status_card.dart#L131) · timeout |
| [暂时无法主动核实](states.html?id=execution-check-unavailable#execution-check-unavailable) | 主动检查不可用，已刷新现有会话状态 | 重新检查、继续等待 | — | — | [lib/src/widgets/session_execution_status_card.dart:69](../lib/src/widgets/session_execution_status_card.dart#L69) · executionCheckUnavailable |
| [继续任务失败](states.html?id=execution-recovery-failed#execution-recovery-failed) | stopAndContinue 请求失败，保留当前执行状态 | 重新检查、停止本轮后继续 | — | — | [lib/src/widgets/session_execution_status_card.dart:90](../lib/src/widgets/session_execution_status_card.dart#L90) · executionRecoveryFailed |

## 审批请求

| 状态 | 触发条件 | 可用操作 | 禁用 | 隐藏 | 源码依据 |
| --- | --- | --- | --- | --- | --- |
| [命令审批 / 完整能力](states.html?id=approval-command#approval-command) | resolvable=true，命令非空，支持会话允许与取消 | 批准、在本会话允许、始终允许、拒绝、取消 | — | — | [lib/src/screens/session_detail_screen.dart:4596](../lib/src/screens/session_detail_screen.dart#L4596) · allowAcceptForSession |
| [命令审批 / 有限能力](states.html?id=approval-limited#approval-limited) | 不支持本会话允许与取消，仍包含命令 | 批准、始终允许、拒绝 | — | 在本会话允许、取消 | [lib/src/screens/session_detail_screen.dart:4634](../lib/src/screens/session_detail_screen.dart#L4634) · approval.allowCancel |
| [非命令审批](states.html?id=approval-no-command#approval-no-command) | command 为空，不展示始终允许 | 批准、在本会话允许、拒绝 | — | 始终允许 | [lib/src/screens/session_detail_screen.dart:4560](../lib/src/screens/session_detail_screen.dart#L4560) · approval.command |
| [审批正在提交](states.html?id=approval-submitting#approval-submitting) | 已点击审批选项，提交尚未返回 | — | 批准、在本会话允许、始终允许、拒绝、取消 | — | [lib/src/screens/session_detail_screen.dart:363](../lib/src/screens/session_detail_screen.dart#L363) · _submittingApprovalChoice |
| [已提交 / 等待执行端确认](states.html?id=approval-resolution-pending#approval-resolution-pending) | 已记录 submittedApprovalRequestId，但请求尚未从服务状态消失 | — | — | 批准、在本会话允许、始终允许、拒绝、取消 | [lib/src/screens/session_detail_screen.dart:534](../lib/src/screens/session_detail_screen.dart#L534) · _isAwaitingSubmittedApprovalResolution |
| [审批提交失败](states.html?id=approval-submit-error#approval-submit-error) | 提交失败，原审批请求仍存在 | 重新选择可用审批操作 | — | — | [lib/src/screens/session_detail_screen.dart:8045](../lib/src/screens/session_detail_screen.dart#L8045) · approvalSubmitFailed |
| [仅桌面可处理](states.html?id=approval-desktop-only#approval-desktop-only) | resolvable=false | — | 所有审批操作 | — | [lib/src/screens/session_detail_screen.dart:4722](../lib/src/screens/session_detail_screen.dart#L4722) · desktopOnlyApproval |
| [AI 审查 / 高风险需人工确认](states.html?id=approval-ai-block#approval-ai-block) | autoApprovalReason=hard_block，仍按 resolvable 决定人工操作 | 请求允许的人工审批操作 | — | — | [lib/src/screens/session_detail_screen.dart:7999](../lib/src/screens/session_detail_screen.dart#L7999) · 'hard_block' |
| [AI 审查失败](states.html?id=approval-ai-error#approval-ai-error) | autoApprovalReason=review_failed | 请求允许的人工审批操作 | — | — | [lib/src/screens/session_detail_screen.dart:8000](../lib/src/screens/session_detail_screen.dart#L8000) · 'review_failed' |
| [请求已解决](states.html?id=approval-cleared#approval-cleared) | 服务确认审批已解决，pendingApproval 清空 | — | — | 已解决的审批卡片 | [lib/src/screens/session_detail_screen.dart:7487](../lib/src/screens/session_detail_screen.dart#L7487) · _pendingApproval = null |

## 消息与输入

| 状态 | 触发条件 | 可用操作 | 禁用 | 隐藏 | 源码依据 |
| --- | --- | --- | --- | --- | --- |
| [空草稿 / 收起输入区](states.html?id=composer-empty#composer-empty) | 无文本、无附件、未聚焦 | 语音模式、附件、录音 | — | 发送、会话设置 | [lib/src/screens/session_detail_screen.dart:2810](../lib/src/screens/session_detail_screen.dart#L2810) · hasSendableDraft |
| [聚焦 / 展开输入区](states.html?id=composer-focused#composer-focused) | 移动端输入获得焦点，无文本草稿 | 附件、会话设置、录音 | — | 发送 | [lib/src/screens/session_detail_screen.dart:726](../lib/src/screens/session_detail_screen.dart#L726) · _composerHasInteractiveFocus |
| [有文本草稿](states.html?id=composer-draft#composer-draft) | 文本 trim 后非空 | 发送、附件、会话设置 | — | 非语音来源草稿的录音按钮 | [lib/src/screens/session_detail_screen.dart:2810](../lib/src/screens/session_detail_screen.dart#L2810) · hasSendableDraft |
| [执行中仍可输入](states.html?id=composer-running#composer-running) | 有活跃轮次，且存在可发送草稿 | 停止、发送后续消息、附件、会话设置 | — | — | [lib/src/screens/session_detail_screen.dart:1881](../lib/src/screens/session_detail_screen.dart#L1881) · hasActiveTurn |
| [有待发送图片](states.html?id=composer-attachments#composer-attachments) | 已选择图片，文本可以为空 | 预览附件、移除附件、发送 | — | — | [lib/src/screens/session_detail_screen.dart:2811](../lib/src/screens/session_detail_screen.dart#L2811) · _pendingAttachments.isNotEmpty |
| [附件正在上传](states.html?id=composer-uploading#composer-uploading) | isSessionBusy=true | — | 输入、发送、附件选择、语音 | — | [lib/src/screens/session_detail_screen.dart:290](../lib/src/screens/session_detail_screen.dart#L290) · _uploadingAttachments |
| [按住说话模式](states.html?id=composer-voice-mode#composer-voice-mode) | voiceComposerMode=true | 切换键盘、按住录音 | — | — | [lib/src/screens/session_detail_screen.dart:329](../lib/src/screens/session_detail_screen.dart#L329) · _voiceComposerMode |
| [正在初始化录音](states.html?id=composer-voice-starting#composer-voice-starting) | 语音初始化尚未完成 | — | 重复启动语音 | — | [lib/src/screens/session_detail_screen.dart:309](../lib/src/screens/session_detail_screen.dart#L309) · _voiceInputStarting |
| [正在录音](states.html?id=composer-voice-recording#composer-voice-recording) | 按住按钮，语音录制中 | 松开发送、上滑选择动作 | — | — | [lib/src/screens/session_detail_screen.dart:330](../lib/src/screens/session_detail_screen.dart#L330) · _voiceHoldActive |
| [上滑选择：发送 / 转文字 / 取消](states.html?id=composer-voice-lifted#composer-voice-lifted) | 按住录音后已上滑离开按钮区域 | 松开发送、转为文字、取消录音 | — | — | [lib/src/screens/session_detail_screen.dart:331](../lib/src/screens/session_detail_screen.dart#L331) · _voiceHoldLifted |
| [录音已结束 / 正在转写](states.html?id=composer-transcribing#composer-transcribing) | 批量 ASR 已提交录音，尚未返回文本 | — | 重复发送录音 | — | [lib/src/screens/session_detail_screen.dart:8651](../lib/src/screens/session_detail_screen.dart#L8651) · uploadingAudio |
| [语音权限缺失](states.html?id=composer-voice-unavailable#composer-voice-unavailable) | 语音启动时检测到麦克风权限缺失 | 键盘输入 | 本次录音 | — | [lib/src/screens/session_detail_screen.dart:8145](../lib/src/screens/session_detail_screen.dart#L8145) · microphonePermissionMissing |
| [文件引用候选](states.html?id=composer-at-files#composer-at-files) | 输入 @ 后显示当前项目文件候选 | 选择文件或目录候选 | — | — | [lib/src/screens/session_detail_screen.dart:229](../lib/src/screens/session_detail_screen.dart#L229) · _composerSuggestionsOverlayController |
| [正在停止回复](states.html?id=composer-stopping#composer-stopping) | 已请求取消当前活跃轮次 | — | 重复停止 | — | [lib/src/screens/session_detail_screen.dart:367](../lib/src/screens/session_detail_screen.dart#L367) · _cancellingReply |
| [录音手势 / 松开发送](states.html?id=composer-hold-send#composer-hold-send) | 按住录音后，当前松手动作=send | 松开发送 | — | — | [lib/src/screens/session_detail_screen.dart:8450](../lib/src/screens/session_detail_screen.dart#L8450) · _VoiceHoldAction.send |
| [录音手势 / 松开转为文字](states.html?id=composer-hold-insert#composer-hold-insert) | 按住录音后，当前松手动作=insert | 松开转为文字 | — | — | [lib/src/screens/session_detail_screen.dart:3183](../lib/src/screens/session_detail_screen.dart#L3183) · _VoiceHoldAction.insert |
| [录音手势 / 松开取消录音](states.html?id=composer-hold-cancel#composer-hold-cancel) | 按住录音后，当前松手动作=cancel | 松开取消录音 | — | — | [lib/src/screens/session_detail_screen.dart:3196](../lib/src/screens/session_detail_screen.dart#L3196) · _VoiceHoldAction.cancel |
| [选择模型供应商](states.html?id=composer-select-provider#composer-select-provider) | 已打开输入区的模型供应商子面板 | 选择模型供应商 | — | — | [lib/src/screens/session_detail_screen.dart:3432](../lib/src/screens/session_detail_screen.dart#L3432) · _ComposerSettingsPanelSection.provider |
| [选择推理强度](states.html?id=composer-select-reasoning#composer-select-reasoning) | 已打开输入区的推理强度子面板 | 选择推理强度 | — | — | [lib/src/screens/session_detail_screen.dart:3455](../lib/src/screens/session_detail_screen.dart#L3455) · _ComposerSettingsPanelSection.reasoning |
| [选择模型](states.html?id=composer-select-model#composer-select-model) | 已打开输入区的模型子面板 | 选择模型 | — | — | [lib/src/screens/session_detail_screen.dart:3472](../lib/src/screens/session_detail_screen.dart#L3472) · _ComposerSettingsPanelSection.model |

## 消息与内容

| 状态 | 触发条件 | 可用操作 | 禁用 | 隐藏 | 源码依据 |
| --- | --- | --- | --- | --- | --- |
| [排队中的用户消息](states.html?id=message-queued#message-queued) | 本地消息状态=queued | 撤回、编辑 | — | 重试 | [lib/src/screens/session_detail_screen.dart:4959](../lib/src/screens/session_detail_screen.dart#L4959) · _LocalMessageState.queued |
| [正在提交的用户消息](states.html?id=message-pending#message-pending) | 本地消息状态=pending | — | — | 撤回、编辑、重试 | [lib/src/screens/session_detail_screen.dart:984](../lib/src/screens/session_detail_screen.dart#L984) · _LocalMessageState.pending |
| [已提交 / 等待消息确认](states.html?id=message-submitted#message-submitted) | 本地消息状态=submitted | — | — | 撤回、编辑、重试 | [lib/src/screens/session_detail_screen.dart:985](../lib/src/screens/session_detail_screen.dart#L985) · _LocalMessageState.submitted |
| [发送失败的用户消息](states.html?id=message-failed#message-failed) | 本地消息状态=failed | 重试 | — | 撤回、编辑 | [lib/src/screens/session_detail_screen.dart:4958](../lib/src/screens/session_detail_screen.dart#L4958) · _LocalMessageState.failed |
| [Agent 流式回复](states.html?id=message-streaming#message-streaming) | 同一 assistant 消息持续返回增量内容 | — | — | — | [lib/src/screens/session_detail_screen.dart:7640](../lib/src/screens/session_detail_screen.dart#L7640) · _mergeAssistantStreamContent |
| [工具活动进行中 / 展开](states.html?id=message-tools#message-tools) | 工具调用已开始或返回结果，可查看详情 | 展开工具活动、查看原始内容 | — | — | [lib/src/screens/session_detail_screen.dart:10784](../lib/src/screens/session_detail_screen.dart#L10784) · _showToolMessageDetail |
| [文件变更折叠 / 展开](states.html?id=message-diff#message-diff) | 本轮存在一项或多项文件 diff | 展开或折叠文件、查看完整 Diff | — | — | [lib/src/screens/session_detail_screen.dart:337](../lib/src/screens/session_detail_screen.dart#L337) · _expandedDiffTurnIds |
| [加载更早消息](states.html?id=message-history-loading#message-history-loading) | 滚动至历史顶部，扩展更早消息中 | — | — | — | [lib/src/screens/session_detail_screen.dart:355](../lib/src/screens/session_detail_screen.dart#L355) · _expandingHistory |
| [离开最新位置](states.html?id=message-scroll-latest#message-scroll-latest) | 当前滚动位置已离开底部 | 回到最新消息 | — | — | [lib/src/screens/session_detail_screen.dart:368](../lib/src/screens/session_detail_screen.dart#L368) · _showScrollToBottomAction |
| [媒体预览 / 背景选择](states.html?id=message-image-preview#message-image-preview) | 打开消息中的图片预览 | 缩放预览、切换深色 / 浅色 / 棋盘背景、关闭 | — | — | [lib/src/screens/session_detail_screen.dart:6097](../lib/src/screens/session_detail_screen.dart#L6097) · _ImagePreviewBackdropMode |
| [媒体预览失败](states.html?id=message-media-error#message-media-error) | 图片或视频加载失败 | — | — | — | [lib/src/screens/session_detail_screen.dart:6136](../lib/src/screens/session_detail_screen.dart#L6136) · imagePreviewLoadFailed |
| [正在播报回复](states.html?id=message-speaking#message-speaking) | TTS 正在播放当前回复 | 停止播报 | — | — | [lib/src/screens/session_detail_screen.dart:311](../lib/src/screens/session_detail_screen.dart#L311) · _isSpeaking |
| [图片背景 / 深色](states.html?id=image-backdrop-dark#image-backdrop-dark) | 图片预览背景选为深色 | 缩放、切换背景、关闭 | — | — | [lib/src/screens/session_detail_screen.dart:6097](../lib/src/screens/session_detail_screen.dart#L6097) · _ImagePreviewBackdropMode.dark |
| [图片背景 / 浅色](states.html?id=image-backdrop-light#image-backdrop-light) | 图片预览背景选为浅色 | 缩放、切换背景、关闭 | — | — | [lib/src/screens/session_detail_screen.dart:6323](../lib/src/screens/session_detail_screen.dart#L6323) · _ImagePreviewBackdropMode.light |
| [图片背景 / 棋盘格](states.html?id=image-backdrop-checker#image-backdrop-checker) | 图片预览背景选为棋盘格 | 缩放、切换背景、关闭 | — | — | [lib/src/screens/session_detail_screen.dart:6325](../lib/src/screens/session_detail_screen.dart#L6325) · _ImagePreviewBackdropMode.checker |

## 语音通话

| 状态 | 触发条件 | 可用操作 | 禁用 | 隐藏 | 源码依据 |
| --- | --- | --- | --- | --- | --- |
| [准备聆听](states.html?id=call-preparing#call-preparing) | 正在初始化实时 ASR | 切换字幕、当前主操作、结束通话 | — | — | [lib/src/screens/session_detail_screen.dart:3882](../lib/src/screens/session_detail_screen.dart#L3882) · _showVoiceInputStartingAsPrimary |
| [尚未开始聆听](states.html?id=call-idle#call-idle) | 通话模式已打开但未聆听 | 切换字幕、当前主操作、结束通话 | — | — | [lib/src/screens/session_detail_screen.dart:4005](../lib/src/screens/session_detail_screen.dart#L4005) · startCallMode |
| [正在聆听](states.html?id=call-listening#call-listening) | isListening 或 streamingAsrActive | 切换字幕、当前主操作、结束通话 | — | — | [lib/src/screens/session_detail_screen.dart:321](../lib/src/screens/session_detail_screen.dart#L321) · _streamingAsrActive |
| [检测到说话](states.html?id=call-detected#call-detected) | speechHintState=speaking | 切换字幕、当前主操作、结束通话 | — | — | [lib/src/screens/session_detail_screen.dart:4030](../lib/src/screens/session_detail_screen.dart#L4030) · _CallModeSpeechHintState.speaking |
| [等待停顿确认](states.html?id=call-pause#call-pause) | speechHintState=waitingForPause | 切换字幕、当前主操作、结束通话 | — | — | [lib/src/screens/session_detail_screen.dart:4036](../lib/src/screens/session_detail_screen.dart#L4036) · _CallModeSpeechHintState.waitingForPause |
| [Agent 正在处理](states.html?id=call-working#call-working) | status=running | 切换字幕、当前主操作、结束通话 | — | — | [lib/src/screens/session_detail_screen.dart:991](../lib/src/screens/session_detail_screen.dart#L991) · _session.status == SessionStatus.running |
| [等待执行结果](states.html?id=call-waiting#call-waiting) | status=waiting | 切换字幕、当前主操作、结束通话 | — | — | [lib/src/screens/session_detail_screen.dart:992](../lib/src/screens/session_detail_screen.dart#L992) · _session.status == SessionStatus.waiting |
| [等待审批](states.html?id=call-approval#call-approval) | status=awaitingApproval | 切换字幕、当前主操作、结束通话 | — | — | [lib/src/screens/session_detail_screen.dart:1883](../lib/src/screens/session_detail_screen.dart#L1883) · _session.status == SessionStatus.awaitingApproval |
| [正在播报](states.html?id=call-speaking#call-speaking) | isSpeaking 或等待音频播放完成 | 切换字幕、当前主操作、结束通话 | — | — | [lib/src/screens/session_detail_screen.dart:315](../lib/src/screens/session_detail_screen.dart#L315) · _callModeAwaitingPlaybackCompletion |
| [声纹待核实](states.html?id=call-speaker-check#call-speaker-check) | 转写内容尚在等待说话人核实 | 切换字幕、当前主操作、结束通话 | — | — | [lib/src/screens/session_detail_screen.dart:299](../lib/src/screens/session_detail_screen.dart#L299) · _recognizedSpeechPendingSpeakerVerification |
| [说话人不匹配](states.html?id=call-rejected-speaker#call-rejected-speaker) | 语音不属于所选说话人 | 切换字幕、当前主操作、结束通话 | — | — | [lib/src/screens/session_detail_screen.dart:300](../lib/src/screens/session_detail_screen.dart#L300) · _recognizedSpeechRejectedSpeaker |
| [输入被过滤](states.html?id=call-rejected-other#call-rejected-other) | 转写未通过当前输入校验 | 切换字幕、当前主操作、结束通话 | — | — | [lib/src/screens/session_detail_screen.dart:302](../lib/src/screens/session_detail_screen.dart#L302) · _recognizedSpeechRejectedOther |
| [语音或会话错误](states.html?id=call-error#call-error) | speechError 非空或会话失败 | 切换字幕、当前主操作、结束通话 | — | — | [lib/src/screens/session_detail_screen.dart:3923](../lib/src/screens/session_detail_screen.dart#L3923) · statusIsError |
| [字幕已隐藏](states.html?id=call-subtitles-off#call-subtitles-off) | subtitlesVisible=false | 切换字幕、当前主操作、结束通话 | — | — | [lib/src/screens/session_detail_screen.dart:314](../lib/src/screens/session_detail_screen.dart#L314) · _callModeSubtitlesVisible |

## 连接、首页与项目

| 状态 | 触发条件 | 可用操作 | 禁用 | 隐藏 | 源码依据 |
| --- | --- | --- | --- | --- | --- |
| [首页正在加载](states.html?id=home-loading#home-loading) | 首页尚未取得首次会话 / 项目结果 | — | — | 旧的空态提示 | [lib/src/screens/home_screen.dart:626](../lib/src/screens/home_screen.dart#L626) · _HomeSurfaceState.loading |
| [尚未连接 Bridge](states.html?id=home-connect#home-connect) | 尚未配置可用的 Bridge 或未授权 | 下载 Bridge、填写地址、授权当前设备 | — | — | [lib/src/screens/home_screen.dart:632](../lib/src/screens/home_screen.dart#L632) · _HomeSurfaceState.connect |
| [等待设备授权](states.html?id=home-authorization#home-authorization) | 已取得授权请求 ID，等待主机批准 | 复制批准命令、重新请求、返回欢迎页 | — | — | [lib/src/screens/home_screen.dart:629](../lib/src/screens/home_screen.dart#L629) · _HomeSurfaceState.waitingApproval |
| [设备授权请求失败](states.html?id=home-auth-error#home-auth-error) | 授权请求或轮询返回错误 | 重新请求、更换 Bridge | — | — | [lib/src/screens/home_screen.dart:58](../lib/src/screens/home_screen.dart#L58) · _authError |
| [正在保存 Bridge 地址](states.html?id=home-saving-bridge#home-saving-bridge) | Bridge 配置保存请求尚未结束 | 保存地址 | 保存地址 | — | [lib/src/screens/home_screen.dart:64](../lib/src/screens/home_screen.dart#L64) · _isSavingBridgeConfig |
| [首页正在刷新](states.html?id=home-refreshing#home-refreshing) | 已存在数据，再次刷新中 | — | — | 首次加载骨架 | [lib/src/screens/home_screen.dart:60](../lib/src/screens/home_screen.dart#L60) · _isRefreshing |
| [首页会话加载失败](states.html?id=home-session-error#home-session-error) | 会话接口失败，项目可以独立展示 | 重试 | — | — | [lib/src/screens/home_screen.dart:57](../lib/src/screens/home_screen.dart#L57) · _recentSessionsError |
| [首页项目加载失败](states.html?id=home-project-error#home-project-error) | 项目接口失败，已有会话内容可保留 | 重试、打开设置 | — | — | [lib/src/screens/home_screen.dart:56](../lib/src/screens/home_screen.dart#L56) · _projectsError |
| [已有项目 / 尚无会话](states.html?id=home-no-sessions#home-no-sessions) | 项目存在，但会话列表为空 | 新建会话 | — | — | [lib/src/screens/home_screen.dart:812](../lib/src/screens/home_screen.dart#L812) · noSessionsYet |
| [首页搜索无结果](states.html?id=home-search-empty#home-search-empty) | 查询非空，匹配会话与项目均为空 | 清空搜索 | — | — | [lib/src/screens/home_screen.dart:1363](../lib/src/screens/home_screen.dart#L1363) · noSearchResultsTitle |
| [项目列表加载中](states.html?id=projects-loading#projects-loading) | 首次项目请求尚未返回 | — | — | 空项目提示 | [lib/src/screens/home_screen.dart:723](../lib/src/screens/home_screen.dart#L723) · _SearchBarSkeleton |
| [项目列表为空](states.html?id=projects-empty#projects-empty) | 项目请求成功且列表为空 | 创建项目 | — | — | [lib/src/screens/home_screen.dart:1830](../lib/src/screens/home_screen.dart#L1830) · noProjectsYet |
| [项目列表请求失败](states.html?id=projects-error#projects-error) | 列表接口返回错误 | 重试、更换 Bridge | — | — | [lib/src/screens/home_screen.dart:1122](../lib/src/screens/home_screen.dart#L1122) · loadProjectsFailed |
| [项目内尚无会话](states.html?id=project-empty#project-empty) | 当前项目会话请求成功且列表为空 | 新建会话 | — | — | [lib/src/screens/project_detail_screen.dart:763](../lib/src/screens/project_detail_screen.dart#L763) · _ProjectEmptyCard |
| [项目内搜索无结果](states.html?id=project-search-empty#project-search-empty) | 该项目有会话，但没有匹配当前查询 | 清空搜索 | — | — | [lib/src/screens/project_detail_screen.dart:768](../lib/src/screens/project_detail_screen.dart#L768) · _ProjectSearchEmptyCard |
| [项目会话请求失败](states.html?id=project-error#project-error) | 当前项目会话接口返回错误 | 重试 | — | — | [lib/src/screens/project_detail_screen.dart:757](../lib/src/screens/project_detail_screen.dart#L757) · _ProjectErrorCard |
| [项目会话刷新中](states.html?id=project-refreshing#project-refreshing) | 已有会话，周期刷新或下拉刷新中 | — | — | 首次加载空态 | [lib/src/screens/project_detail_screen.dart:51](../lib/src/screens/project_detail_screen.dart#L51) · _isRefreshing |

## 创建、设置与模型供应商

| 状态 | 触发条件 | 可用操作 | 禁用 | 隐藏 | 源码依据 |
| --- | --- | --- | --- | --- | --- |
| [正在读取 Agent](states.html?id=create-agents-loading#create-agents-loading) | Agent 列表首次加载中 | 选择 Agent、创建会话 | 选择 Agent、创建会话 | — | [lib/src/widgets/create_session_dialog.dart:41](../lib/src/widgets/create_session_dialog.dart#L41) · _loadingAgents |
| [Agent 尚未安装](states.html?id=create-agent-missing#create-agent-missing) | 选中的 Agent installed=false | 安装 Agent | — | 可直接创建的状态 | [lib/src/widgets/create_session_dialog.dart:99](../lib/src/widgets/create_session_dialog.dart#L99) · _selectedAgentInstalled |
| [Agent 正在安装](states.html?id=create-agent-installing#create-agent-installing) | 安装请求尚未完成 | 安装 Agent、创建会话 | 安装 Agent、创建会话 | — | [lib/src/widgets/create_session_dialog.dart:42](../lib/src/widgets/create_session_dialog.dart#L42) · _installingAgent |
| [Agent 安装失败](states.html?id=create-agent-install-error#create-agent-install-error) | 安装返回失败或网络异常 | 重新安装、切换 Agent | — | — | [lib/src/widgets/create_session_dialog.dart:43](../lib/src/widgets/create_session_dialog.dart#L43) · _agentError |
| [模型列表读取中](states.html?id=create-models-loading#create-models-loading) | 选择供应商后正在读取其模型 | 选择模型 | 选择模型 | — | [lib/src/widgets/create_session_dialog.dart:40](../lib/src/widgets/create_session_dialog.dart#L40) · _loadingModels |
| [没有兼容供应商](states.html?id=create-provider-default#create-provider-default) | 没有符合所选 Agent 格式的供应商 | 使用默认配置 | — | — | [lib/src/widgets/create_session_dialog.dart:74](../lib/src/widgets/create_session_dialog.dart#L74) · _normalizeProviderSelection |
| [设置正在保存](states.html?id=settings-saving#settings-saving) | 设置保存请求未结束 | 保存 | 保存 | — | [lib/src/screens/settings_screen.dart:71](../lib/src/screens/settings_screen.dart#L71) · _saving |
| [审批供应商加载中](states.html?id=settings-ai-providers-loading#settings-ai-providers-loading) | 正在读取已配置且可用的模型服务 | 选择审批模型服务 | 选择审批模型服务 | — | [lib/src/screens/settings_screen.dart:59](../lib/src/screens/settings_screen.dart#L59) · _loadingModelProviders |
| [审批供应商加载失败](states.html?id=settings-ai-providers-error#settings-ai-providers-error) | 已配置服务列表请求失败 | 重试加载 | — | — | [lib/src/screens/settings_screen.dart:62](../lib/src/screens/settings_screen.dart#L62) · _modelProvidersError |
| [未配置审批模型服务](states.html?id=settings-no-model-service#settings-no-model-service) | 没有已启用的模型服务 | 打开模型供应商 | — | — | [lib/src/screens/settings_screen.dart:902](../lib/src/screens/settings_screen.dart#L902) · noConfiguredModels |
| [审批模型加载中](states.html?id=settings-ai-models-loading#settings-ai-models-loading) | 已选模型服务，其模型列表尚未返回 | 选择审批模型 | 选择审批模型 | — | [lib/src/screens/settings_screen.dart:60](../lib/src/screens/settings_screen.dart#L60) · _loadingAiApprovalModels |
| [供应商无可用审批模型](states.html?id=settings-no-ai-models#settings-no-ai-models) | 已选服务未返回模型 | 切换服务、重试模型加载 | — | — | [lib/src/screens/settings_screen.dart:957](../lib/src/screens/settings_screen.dart#L957) · noApprovalModels |
| [供应商列表加载中](states.html?id=provider-loading#provider-loading) | 首次读取模型供应商中 | — | — | — | [lib/src/screens/model_provider_screen.dart:31](../lib/src/screens/model_provider_screen.dart#L31) · _loading |
| [尚无模型供应商](states.html?id=provider-empty#provider-empty) | 读取成功且供应商列表为空 | 添加供应商 | — | — | [lib/src/screens/model_provider_screen.dart:429](../lib/src/screens/model_provider_screen.dart#L429) · noProvidersYet |
| [供应商读取失败](states.html?id=provider-load-error#provider-load-error) | 模型供应商接口失败 | 重试 | — | — | [lib/src/screens/model_provider_screen.dart:304](../lib/src/screens/model_provider_screen.dart#L304) · _buildErrorState |
| [供应商必填字段缺失](states.html?id=provider-required#provider-required) | 名称或基础 URL 为空 | 补充字段、保存 | 保存 | — | [lib/src/screens/model_provider_screen.dart:854](../lib/src/screens/model_provider_screen.dart#L854) · fieldRequired |
| [删除供应商确认](states.html?id=provider-delete-confirm#provider-delete-confirm) | 已选择删除某个供应商，尚未确认 | 确认删除、取消 | — | — | [lib/src/screens/model_provider_screen.dart:104](../lib/src/screens/model_provider_screen.dart#L104) · _deleteProvider |
| [正在检查更新](states.html?id=update-checking#update-checking) | 更新检查请求未结束 | 检查更新 | 检查更新 | — | [lib/src/screens/settings_screen.dart:74](../lib/src/screens/settings_screen.dart#L74) · _checkingUpdate |
| [指定版本未找到](states.html?id=update-not-found#update-not-found) | 目标版本不存在或不可下载 | 修改版本号、重新检查 | — | — | [lib/src/screens/settings_screen.dart:1539](../lib/src/screens/settings_screen.dart#L1539) · targetVersionNotFound |
| [强制更新提示](states.html?id=update-force#update-force) | 服务返回 force=true | 立即更新 | — | 稍后、直接关闭更新对话框 | [lib/src/screens/settings_screen.dart:1587](../lib/src/screens/settings_screen.dart#L1587) · update.force |
| [Web 不提供应用包更新](states.html?id=update-web#update-web) | 当前运行在 Web 平台 | 检查 App 更新 | 检查 App 更新 | — | [lib/src/screens/settings_screen.dart:1182](../lib/src/screens/settings_screen.dart#L1182) · onPressed: kIsWeb |
| [可选更新提示](states.html?id=update-available#update-available) | 发现新版本且 force=false | 立即更新、稍后 | — | — | [lib/src/screens/settings_screen.dart:1547](../lib/src/screens/settings_screen.dart#L1547) · _showUpdateDialog |
| [Android 更新下载中](states.html?id=update-downloading#update-downloading) | 已确认更新，Android 正在下载应用包 | — | 重复下载 | — | [lib/src/screens/settings_screen.dart:1621](../lib/src/screens/settings_screen.dart#L1621) · _downloadAndInstallUpdate |
| [目标版本为降级包](states.html?id=update-downgrade#update-downgrade) | 指定版本比当前已安装版本更旧 | 立即更新、稍后 | — | — | [lib/src/screens/settings_screen.dart:1603](../lib/src/screens/settings_screen.dart#L1603) · targetVersionDowngradeWarning |

## 语音服务与 Pi 插件

| 状态 | 触发条件 | 可用操作 | 禁用 | 隐藏 | 源码依据 |
| --- | --- | --- | --- | --- | --- |
| [系统语音能力不可用](states.html?id=speech-system-unavailable#speech-system-unavailable) | 当前平台不支持所选系统语音能力 | 选择语音服务 | — | — | [lib/src/screens/speech_settings_screen.dart:171](../lib/src/screens/speech_settings_screen.dart#L171) · _systemAsrSupportedOnPlatform |
| [所选语音插件未安装](states.html?id=speech-plugin-missing#speech-plugin-missing) | 选择的插件尚未安装 | 安装插件、测试 | 测试 | — | [lib/src/screens/speech_settings_screen.dart:1147](../lib/src/screens/speech_settings_screen.dart#L1147) · selectedPluginNotInstalled |
| [语音插件缺少必填参数](states.html?id=speech-credentials-required#speech-credentials-required) | 插件清单要求的配置项缺失 | 填写配置、保存并使用、测试 | 测试 | — | [lib/src/screens/speech_settings_screen.dart:1449](../lib/src/screens/speech_settings_screen.dart#L1449) · fillRequiredPluginSettings |
| [语音插件配置保存中](states.html?id=speech-credentials-saving#speech-credentials-saving) | 插件配置正在保存 | 保存插件设置 | 保存插件设置 | — | [lib/src/screens/speech_settings_screen.dart:105](../lib/src/screens/speech_settings_screen.dart#L105) · _savingPluginConfigurationIds |
| [语音服务测试被拒绝](states.html?id=speech-service-error#speech-service-error) | 实时 ASR 认证被服务拒绝 | 修改配置、重新测试 | — | — | [lib/src/screens/speech_settings_screen.dart:1920](../lib/src/screens/speech_settings_screen.dart#L1920) · realtimeAsrAuthenticationRejected |
| [批量 ASR 测试录音中](states.html?id=speech-test-recording#speech-test-recording) | 已开始录音，尚未停止 | 录音、停止并转写 | 录音 | — | [lib/src/screens/speech_settings_screen.dart:1845](../lib/src/screens/speech_settings_screen.dart#L1845) · recordingSpeakThenStop |
| [批量 ASR 测试转写中](states.html?id=speech-test-transcribing#speech-test-transcribing) | 录音已停止，正在等待转写结果 | 录音、停止并转写 | 录音、停止并转写 | — | [lib/src/screens/speech_settings_screen.dart:1756](../lib/src/screens/speech_settings_screen.dart#L1756) · transcribingRecordedAudio |
| [TTS 测试播放中](states.html?id=speech-test-playing#speech-test-playing) | 测试语音已成功开始播放 | 播放、停止 | 播放 | — | [lib/src/screens/speech_settings_screen.dart:1593](../lib/src/screens/speech_settings_screen.dart#L1593) · playbackStartedSuccessfully |
| [本地 Bridge 语音状态读取失败](states.html?id=speech-local-unreachable#speech-local-unreachable) | 本地语音状态接口失败 | 刷新状态 | — | — | [lib/src/screens/speech_settings_screen.dart:145](../lib/src/screens/speech_settings_screen.dart#L145) · _speechStatusError |
| [尚未录入说话人](states.html?id=speech-no-speaker#speech-no-speaker) | 说话人列表为空 | 下载声纹模型、录入说话人、启用过滤 | 启用过滤 | — | [lib/src/screens/speech_settings_screen.dart:3822](../lib/src/screens/speech_settings_screen.dart#L3822) · enrollSpeakerBeforeFiltering |
| [说话人样本录制中](states.html?id=speech-speaker-recording#speech-speaker-recording) | 正在录制声纹样本 | 完成录入 | — | 重复开始录制 | [lib/src/screens/speech_settings_screen.dart:136](../lib/src/screens/speech_settings_screen.dart#L136) · _speakerEnrollmentRecording |
| [说话人样本保存中](states.html?id=speech-speaker-saving#speech-speaker-saving) | 声纹录入请求未完成 | 正在保存说话人 | 正在保存说话人 | — | [lib/src/screens/speech_settings_screen.dart:137](../lib/src/screens/speech_settings_screen.dart#L137) · _speakerEnrollmentSaving |
| [模型下载排队中](states.html?id=speech-model-queued#speech-model-queued) | 模型任务状态为 queued | — | 重复下载 | — | [lib/src/screens/speech_settings_screen.dart:5012](../lib/src/screens/speech_settings_screen.dart#L5012) · speechDownloadStatusQueued |
| [模型正在下载](states.html?id=speech-model-downloading#speech-model-downloading) | 模型任务状态为 downloading | — | 重复下载 | — | [lib/src/screens/speech_settings_screen.dart:5013](../lib/src/screens/speech_settings_screen.dart#L5013) · speechDownloadStatusDownloading |
| [模型正在解压](states.html?id=speech-model-extracting#speech-model-extracting) | 模型任务状态为 extracting | — | 重复下载 | — | [lib/src/screens/speech_settings_screen.dart:5014](../lib/src/screens/speech_settings_screen.dart#L5014) · speechDownloadStatusExtracting |
| [模型正在校验](states.html?id=speech-model-verifying#speech-model-verifying) | 模型任务状态为 verifying | — | 重复下载 | — | [lib/src/screens/speech_settings_screen.dart:5015](../lib/src/screens/speech_settings_screen.dart#L5015) · speechDownloadStatusVerifying |
| [模型下载完成](states.html?id=speech-model-ready#speech-model-ready) | 模型任务状态为 completed | — | — | — | [lib/src/screens/speech_settings_screen.dart:5016](../lib/src/screens/speech_settings_screen.dart#L5016) · speechDownloadStatusCompleted |
| [实时 ASR 测试启动中](states.html?id=speech-realtime-starting#speech-realtime-starting) | 测试正在连接实时语音服务 | 开始测试 | 开始测试 | — | [lib/src/screens/speech_settings_screen.dart:1959](../lib/src/screens/speech_settings_screen.dart#L1959) · startingRealtimeSpeechTest |
| [实时 ASR 测试聆听中](states.html?id=speech-realtime-listening#speech-realtime-listening) | 实时语音测试已开始并等待转写 | 停止测试 | — | — | [lib/src/screens/speech_settings_screen.dart:2085](../lib/src/screens/speech_settings_screen.dart#L2085) · listeningSpeakShortSentence |
| [Pi 插件列表加载中](states.html?id=pi-loading#pi-loading) | 首次读取插件列表中 | — | — | — | [lib/src/screens/pi_plugins_screen.dart:178](../lib/src/screens/pi_plugins_screen.dart#L178) · if (_loading) |
| [尚未安装 Pi 插件](states.html?id=pi-empty#pi-empty) | 插件接口成功返回空列表 | 安装插件 | — | — | [lib/src/screens/pi_plugins_screen.dart:192](../lib/src/screens/pi_plugins_screen.dart#L192) · piPluginEmpty |
| [Pi 插件列表读取失败](states.html?id=pi-load-error#pi-load-error) | 插件列表接口失败 | 重试 | — | — | [lib/src/screens/pi_plugins_screen.dart:183](../lib/src/screens/pi_plugins_screen.dart#L183) · piPluginLoadFailed |
| [Pi 插件正在安装](states.html?id=pi-installing#pi-installing) | 安装请求未完成 | 安装插件 | 安装插件 | — | [lib/src/screens/pi_plugins_screen.dart:157](../lib/src/screens/pi_plugins_screen.dart#L157) · _busy.contains('__install__') |
| [当前插件操作处理中](states.html?id=pi-plugin-busy#pi-plugin-busy) | 启用、校验、配置或卸载当前插件的请求未完成 | 启用、校验、配置、卸载 | 启用、校验、配置、卸载 | — | [lib/src/screens/pi_plugins_screen.dart:205](../lib/src/screens/pi_plugins_screen.dart#L205) · final busy = _busy.contains(plugin.id) |
| [Pi 插件校验失败](states.html?id=pi-validation-error#pi-validation-error) | 插件返回非空的校验错误 | 配置、校验、卸载 | — | — | [lib/src/screens/pi_plugins_screen.dart:254](../lib/src/screens/pi_plugins_screen.dart#L254) · plugin.validationError |
| [插件配置不是 JSON 对象](states.html?id=pi-json-error#pi-json-error) | 安装或编辑时的配置解析失败 | 编辑配置、安装 | 安装 | — | [lib/src/screens/pi_plugins_screen.dart:355](../lib/src/screens/pi_plugins_screen.dart#L355) · Configuration must be a JSON object |

## Pi 扩展交互

| 状态 | 触发条件 | 可用操作 | 禁用 | 隐藏 | 源码依据 |
| --- | --- | --- | --- | --- | --- |
| [插件请求确认](states.html?id=pi-ui-confirm#pi-ui-confirm) | 插件发出 confirm / custom 请求 | 批准、拒绝 | — | 非能力请求的始终允许 | [lib/src/screens/session_detail_screen.dart:7812](../lib/src/screens/session_detail_screen.dart#L7812) · _showPiConfirm |
| [插件请求能力权限](states.html?id=pi-ui-capability#pi-ui-capability) | 请求包含 capability、permission 或 persist | 批准、始终允许、拒绝 | — | — | [lib/src/screens/session_detail_screen.dart:7850](../lib/src/screens/session_detail_screen.dart#L7850) · isCapability |
| [插件请求选择选项](states.html?id=pi-ui-select#pi-ui-select) | 插件发出 select 请求 | 选择服务提供的选项 | — | — | [lib/src/screens/session_detail_screen.dart:7816](../lib/src/screens/session_detail_screen.dart#L7816) · _showPiSelect |
| [插件请求单行输入](states.html?id=pi-ui-input#pi-ui-input) | 插件发出 input 请求 | 输入、确认、取消 | — | — | [lib/src/screens/session_detail_screen.dart:7926](../lib/src/screens/session_detail_screen.dart#L7926) · request.method == 'editor' |
| [插件请求多行编辑](states.html?id=pi-ui-editor#pi-ui-editor) | 插件发出 editor 请求，保留多行输入 | 编辑、确认、取消 | — | — | [lib/src/screens/session_detail_screen.dart:7821](../lib/src/screens/session_detail_screen.dart#L7821) · _showPiTextInput |

## 验收运行

| 状态 | 触发条件 | 可用操作 | 禁用 | 隐藏 | 源码依据 |
| --- | --- | --- | --- | --- | --- |
| [验收环境未安装](states.html?id=acceptance-phase-not_installed#acceptance-phase-not_installed) | phase=not_installed | 安装验收环境 | — | — | [lib/src/screens/acceptance_screen.dart:27](../lib/src/screens/acceptance_screen.dart#L27) · 'not_installed' |
| [正在检查环境](states.html?id=acceptance-phase-checking#acceptance-phase-checking) | phase=checking | — | 重复启动对应操作 | — | [lib/src/screens/acceptance_screen.dart:28](../lib/src/screens/acceptance_screen.dart#L28) · 'checking' |
| [正在准备环境](states.html?id=acceptance-phase-preparing#acceptance-phase-preparing) | phase=preparing | — | 重复启动对应操作 | — | [lib/src/screens/acceptance_screen.dart:29](../lib/src/screens/acceptance_screen.dart#L29) · 'preparing' |
| [正在验证桌面](states.html?id=acceptance-phase-verifying#acceptance-phase-verifying) | phase=verifying | — | 重复启动对应操作 | — | [lib/src/screens/acceptance_screen.dart:30](../lib/src/screens/acceptance_screen.dart#L30) · 'verifying' |
| [验收环境已就绪](states.html?id=acceptance-phase-ready#acceptance-phase-ready) | phase=ready | 开始验收 | — | — | [lib/src/screens/acceptance_screen.dart:31](../lib/src/screens/acceptance_screen.dart#L31) · 'ready' |
| [正在启动验收](states.html?id=acceptance-phase-starting#acceptance-phase-starting) | phase=starting | — | 重复启动对应操作 | — | [lib/src/screens/acceptance_screen.dart:32](../lib/src/screens/acceptance_screen.dart#L32) · 'starting' |
| [正在生成测试用例](states.html?id=acceptance-phase-planning#acceptance-phase-planning) | phase=planning | — | 重复启动对应操作 | — | [lib/src/screens/acceptance_screen.dart:33](../lib/src/screens/acceptance_screen.dart#L33) · 'planning' |
| [自动验收执行中](states.html?id=acceptance-phase-running#acceptance-phase-running) | phase=running | 停止验收 | — | — | [lib/src/screens/acceptance_screen.dart:34](../lib/src/screens/acceptance_screen.dart#L34) · 'running' |
| [正在停止验收](states.html?id=acceptance-phase-stopping#acceptance-phase-stopping) | phase=stopping | — | 重复启动对应操作 | — | [lib/src/screens/acceptance_screen.dart:35](../lib/src/screens/acceptance_screen.dart#L35) · 'stopping' |
| [验收运行已结束](states.html?id=acceptance-phase-completed#acceptance-phase-completed) | phase=completed | 查看证据 | — | — | [lib/src/screens/acceptance_screen.dart:36](../lib/src/screens/acceptance_screen.dart#L36) · 'completed' |
| [验收运行失败](states.html?id=acceptance-phase-failed#acceptance-phase-failed) | phase=failed | 查看错误 | — | — | [lib/src/screens/acceptance_screen.dart:37](../lib/src/screens/acceptance_screen.dart#L37) · 'failed' |

## 验收计划、桌面与证据

| 状态 | 触发条件 | 可用操作 | 禁用 | 隐藏 | 源码依据 |
| --- | --- | --- | --- | --- | --- |
| [验收正在创建 / 禁止退出](states.html?id=acceptance-creating-blocked#acceptance-creating-blocked) | creating=true，显示阻止点击与返回的进度遮罩 | — | 返回、重复创建 | — | [lib/src/screens/acceptance_screen.dart:433](../lib/src/screens/acceptance_screen.dart#L433) · acceptance-creation-loading |
| [尚无验收记录](states.html?id=acceptance-empty#acceptance-empty) | 读取成功且 runs 为空 | 开始验收 | — | — | [lib/src/screens/acceptance_screen.dart:333](../lib/src/screens/acceptance_screen.dart#L333) · acceptanceEmpty |
| [测试用例等待确认](states.html?id=plan-awaiting-confirmation#plan-awaiting-confirmation) | 测试计划已生成且尚未 approved | 新增用例、编辑用例、删除用例、补充要求、确认用例 | — | — | [lib/src/screens/acceptance_plan_card.dart:221](../lib/src/screens/acceptance_plan_card.dart#L221) · acceptance-plan-confirm |
| [Agent 正在修改测试计划](states.html?id=plan-revising#plan-revising) | automation=revising_plan | 编辑用例、确认用例、发送要求 | 编辑用例、确认用例、发送要求 | — | [lib/src/screens/acceptance_plan_card.dart:78](../lib/src/screens/acceptance_plan_card.dart#L78) · revising_plan |
| [测试计划生成失败](states.html?id=plan-generation-error#plan-generation-error) | planning 阶段生成失败且无 testPlan | 重新生成测试用例 | — | — | [lib/src/screens/acceptance_screen.dart:1001](../lib/src/screens/acceptance_screen.dart#L1001) · retryAcceptanceTestPlan |
| [测试用例校验未通过](states.html?id=plan-case-invalid#plan-case-invalid) | 标题 / 预期缺失，或步骤数量、长度超出限制 | 编辑用例、保存 | 保存 | — | [lib/src/screens/acceptance_plan_card.dart:312](../lib/src/screens/acceptance_plan_card.dart#L312) · acceptancePlanStepsLimit |
| [手动接管远程桌面](states.html?id=desktop-manual-control#desktop-manual-control) | 已从自动化切换至手动桌面控制 | 保存截图、切换方向、全屏、交还自动化控制权 | — | — | [lib/src/screens/acceptance_screen.dart:1052](../lib/src/screens/acceptance_screen.dart#L1052) · acceptanceReleaseControl |
| [自动化失败但桌面仍可用](states.html?id=desktop-automation-error#desktop-automation-error) | 自动检查失败，但运行仍在进行 | 接管桌面、停止验收 | — | — | [lib/src/screens/acceptance_screen.dart:980](../lib/src/screens/acceptance_screen.dart#L980) · acceptanceAutomationFailedHint |
| [等待人工验收结果](states.html?id=acceptance-human-review#acceptance-human-review) | 已产生运行结果，尚未人工确认 | 填写说明、验收通过、报告问题 | — | — | [lib/src/screens/acceptance_screen.dart:796](../lib/src/screens/acceptance_screen.dart#L796) · acceptanceAwaitingReview |
| [验收证据尚未生成](states.html?id=acceptance-evidence-empty#acceptance-evidence-empty) | 没有可展示的证据附件 | 生成录像与报告 | — | — | [lib/src/screens/acceptance_screen.dart:1125](../lib/src/screens/acceptance_screen.dart#L1125) · acceptanceNoEvidence |
| [证据正在导出](states.html?id=acceptance-evidence-exporting#acceptance-evidence-exporting) | 生成录像与报告请求未返回 | 生成录像与报告 | 生成录像与报告 | — | [lib/src/screens/acceptance_screen.dart:1120](../lib/src/screens/acceptance_screen.dart#L1120) · acceptanceExportEvidence |
| [运行环境配置无效](states.html?id=environment-invalid#environment-invalid) | Dockerfile 或已有镜像模式缺少必填内容 | 补充配置、保存环境 | 保存环境 | — | [lib/src/screens/acceptance_environment_screen.dart:70](../lib/src/screens/acceptance_environment_screen.dart#L70) · acceptanceEnvironmentRequired |
| [录像正在加载](states.html?id=recording-loading#recording-loading) | 播放器未创建或尚未完成初始化 | — | 播放、进度拖动 | — | [lib/src/screens/acceptance_video_screen.dart:115](../lib/src/screens/acceptance_video_screen.dart#L115) · !player.value.isInitialized |
| [录像加载失败](states.html?id=recording-error#recording-error) | 下载、初始化或读取录像失败 | 重试 | — | — | [lib/src/screens/acceptance_video_screen.dart:108](../lib/src/screens/acceptance_video_screen.dart#L108) · acceptanceVideoError |

## Markdown 正文

| 状态 | 触发条件 | 可用操作 | 禁用 | 隐藏 | 源码依据 |
| --- | --- | --- | --- | --- | --- |
| [标题与段落层次](states.html?id=render-headings#render-headings) | 返回 Markdown 标题与普通段落 | — | — | — | [lib/src/screens/session_detail_screen.dart:5553](../lib/src/screens/session_detail_screen.dart#L5553) · MarkdownBody( |
| [加粗与斜体](states.html?id=render-emphasis#render-emphasis) | 内容包含强调语法 | — | — | — | [lib/src/screens/session_detail_screen.dart:5486](../lib/src/screens/session_detail_screen.dart#L5486) · strong: |
| [行内代码与路径](states.html?id=render-inline-code#render-inline-code) | 段落包含反引号代码 | — | — | — | [lib/src/screens/session_detail_screen.dart:5477](../lib/src/screens/session_detail_screen.dart#L5477) · code: codeStyle |
| [代码块与语法高亮](states.html?id=render-code#render-code) | 返回 fenced code block | 选择文本 | — | — | [lib/src/screens/session_detail_screen.dart:5560](../lib/src/screens/session_detail_screen.dart#L5560) · _AssistantCodeSyntaxHighlighter(theme) |
| [长代码横向阅读](states.html?id=render-code-wide#render-code-wide) | 长行代码超出正文宽度 | 选择文本 | — | — | [lib/src/screens/session_detail_screen.dart:5560](../lib/src/screens/session_detail_screen.dart#L5560) · _AssistantCodeSyntaxHighlighter(theme) |
| [无序列表](states.html?id=render-unordered-list#render-unordered-list) | 内容包含无序列表 | — | — | — | [lib/src/screens/session_detail_screen.dart:5494](../lib/src/screens/session_detail_screen.dart#L5494) · listBullet: |
| [有序步骤](states.html?id=render-ordered-list#render-ordered-list) | 内容包含有序列表 | — | — | — | [lib/src/screens/session_detail_screen.dart:5494](../lib/src/screens/session_detail_screen.dart#L5494) · listBullet: |
| [Markdown 表格](states.html?id=render-table#render-table) | MarkdownBody 以默认 Markdown 规则渲染表格 | — | — | — | [lib/src/screens/session_detail_screen.dart:5553](../lib/src/screens/session_detail_screen.dart#L5553) · MarkdownBody( |
| [引用块](states.html?id=render-quote#render-quote) | 内容以 &gt; 引用标记开头 | — | — | — | [lib/src/screens/session_detail_screen.dart:5498](../lib/src/screens/session_detail_screen.dart#L5498) · blockquoteDecoration: |
| [嵌套引用](states.html?id=render-quote-nested#render-quote-nested) | 引用内容包含嵌套引用 | — | — | — | [lib/src/screens/session_detail_screen.dart:5506](../lib/src/screens/session_detail_screen.dart#L5506) · blockquotePadding: |
| [消息内分隔线](states.html?id=render-divider#render-divider) | 正文包含独立的 --- 分隔行 | — | — | — | [lib/src/screens/session_detail_screen.dart:5586](../lib/src/screens/session_detail_screen.dart#L5586) · markdown-horizontal-rule |
| [连续助手消息分隔](states.html?id=render-consecutive#render-consecutive) | 同一轮中相邻的助手消息分别展示 | — | — | — | [lib/src/screens/session_detail_screen.dart:4937](../lib/src/screens/session_detail_screen.dart#L4937) · assistant-message-divider |
| [流式内容尚未返回完整](states.html?id=render-streaming-markdown#render-streaming-markdown) | 正文持续增长，Markdown 按当前已收到的文本渲染 | — | — | — | [lib/src/screens/session_detail_screen.dart:5284](../lib/src/screens/session_detail_screen.dart#L5284) · isLoadingReply |
| [任务列表 / 只读勾选状态](states.html?id=render-task-list#render-task-list) | 默认 GitHub Flavored Markdown 解析任务列表 | — | — | 交互式修改勾选状态 | [lib/src/screens/session_detail_screen.dart:5553](../lib/src/screens/session_detail_screen.dart#L5553) · MarkdownBody( |
| [删除线与修订说明](states.html?id=render-strikethrough#render-strikethrough) | 默认 GitHub Flavored Markdown 解析删除线 | — | — | — | [lib/src/screens/session_detail_screen.dart:5553](../lib/src/screens/session_detail_screen.dart#L5553) · MarkdownBody( |

## 链接与文件

| 状态 | 触发条件 | 可用操作 | 禁用 | 隐藏 | 源码依据 |
| --- | --- | --- | --- | --- | --- |
| [外部网页链接](states.html?id=render-external-link#render-external-link) | 链接既不是媒体引用，也不是客户端可访问的本地文件 | 打开系统链接 | — | 网页抓取摘要、网页预览卡片 | [lib/src/screens/session_detail_screen.dart:5652](../lib/src/screens/session_detail_screen.dart#L5652) · unawaited(launchUrl(uri)) |
| [尖括号自动链接](states.html?id=render-autolink#render-autolink) | 返回尖括号包裹的 URL | 打开系统链接 | — | — | [lib/src/screens/session_detail_screen.dart:5562](../lib/src/screens/session_detail_screen.dart#L5562) · onTapLink: |
| [项目内相对文件链接](states.html?id=render-file-relative#render-file-relative) | 客户端能访问项目根路径，且目标文件在本机存在 | 打开本地文件预览 | — | — | [lib/src/screens/session_detail_screen.dart:5642](../lib/src/screens/session_detail_screen.dart#L5642) · _resolveMarkdownFile(href) |
| [file URI 与绝对路径](states.html?id=render-file-uri#render-file-uri) | file URI 解析为存在的客户端本地文件 | 打开本地文件预览 | — | — | [lib/src/screens/session_detail_screen.dart:5659](../lib/src/screens/session_detail_screen.dart#L5659) · uri.toFilePath() |
| [文本文件全文预览](states.html?id=render-file-preview#render-file-preview) | 文件存在、大小不超过 2 MiB，且不包含 0 字节 | 关闭、选择文本、横向与纵向滚动 | — | 编辑、保存文件 | [lib/src/screens/session_detail_screen.dart:5735](../lib/src/screens/session_detail_screen.dart#L5735) · markdown-file-preview-content |
| [文件过大提示](states.html?id=render-file-too-large#render-file-too-large) | 客户端本地文件大于 2 MiB | — | — | — | [lib/src/screens/session_detail_screen.dart:5678](../lib/src/screens/session_detail_screen.dart#L5678) · File is too large to preview |
| [二进制文件提示](states.html?id=render-file-binary#render-file-binary) | 文件字节包含 0，判定为二进制 | — | — | — | [lib/src/screens/session_detail_screen.dart:5684](../lib/src/screens/session_detail_screen.dart#L5684) · Binary files cannot be previewed |

## 图片与媒体解析

| 状态 | 触发条件 | 可用操作 | 禁用 | 隐藏 | 源码依据 |
| --- | --- | --- | --- | --- | --- |
| [Markdown 图片](states.html?id=render-image-markdown#render-image-markdown) | 消息包含标准 Markdown 图片标记 | 打开全屏预览 | — | — | [lib/src/message_image_paths.dart:89](../lib/src/message_image_paths.dart#L89) · _markdownLinkPattern |
| [指向图片的普通链接](states.html?id=render-image-link#render-image-link) | 普通 Markdown 链接指向支持的媒体路径 | 点击链接或缩略图打开媒体 | — | 按普通网页链接打开 | [lib/src/screens/session_detail_screen.dart:5636](../lib/src/screens/session_detail_screen.dart#L5636) · MessageImageReference.tryParse(href) |
| [裸路径提取](states.html?id=render-image-bare#render-image-bare) | 正文出现支持的图片文件路径 | 打开媒体预览 | — | — | [lib/src/message_image_paths.dart:111](../lib/src/message_image_paths.dart#L111) · _bareImagePathPattern |
| [行内代码中的图片路径](states.html?id=render-image-inline-path#render-image-inline-path) | 行内代码的值可以解析为媒体路径 | 打开缩略图预览 | — | — | [lib/src/message_image_paths.dart:97](../lib/src/message_image_paths.dart#L97) · _inlineCodePattern |
| [远程图片 URL](states.html?id=render-image-remote#render-image-remote) | 引用为 http / https 图片地址 | 打开媒体预览 | — | — | [lib/src/screens/session_detail_screen.dart:5895](../lib/src/screens/session_detail_screen.dart#L5895) · reference.isRemoteUrl |
| [Base64 内嵌图片](states.html?id=render-image-data#render-image-data) | data:image/*;base64, 后的内容可成功解码 | 打开媒体预览 | — | — | [lib/src/message_image_paths.dart:60](../lib/src/message_image_paths.dart#L60) · _tryParseDataUri |
| [SVG 与透明背景](states.html?id=render-image-svg#render-image-svg) | 媒体引用识别为 SVG | 打开预览、缩放、切换背景 | — | — | [lib/src/screens/session_detail_screen.dart:5928](../lib/src/screens/session_detail_screen.dart#L5928) · reference.isSvg |
| [GIF / WebP 动图](states.html?id=render-image-animated#render-image-animated) | GIF 或 WebP 引用进入预览 | 打开媒体预览 | — | — | [lib/src/message_image_paths.dart:44](../lib/src/message_image_paths.dart#L44) · isAnimatedImage |
| [重复路径只出现一次](states.html?id=render-image-deduplicate#render-image-deduplicate) | 同一路径被多种语法重复引用 | 打开唯一缩略图 | — | 重复媒体卡片 | [lib/src/message_image_paths.dart:86](../lib/src/message_image_paths.dart#L86) · matches.putIfAbsent |
| [图片与视频混排](states.html?id=render-media-mixed#render-media-mixed) | 同一消息提取到图片、MP4 与 SVG | 打开相应媒体、在预览中切换项目 | — | — | [lib/src/screens/session_detail_screen.dart:5536](../lib/src/screens/session_detail_screen.dart#L5536) · buildImageReferences() |
| [用户消息中的媒体](states.html?id=render-media-user#render-media-user) | 用户消息同时包含正文与图片 | 打开媒体预览 | — | — | [lib/src/screens/session_detail_screen.dart:4984](../lib/src/screens/session_detail_screen.dart#L4984) · imageWrapAlignment: WrapAlignment.end |
| [本地缩略图读取中](states.html?id=render-image-loading#render-image-loading) | Bridge 文件 Future 尚未完成 | — | — | — | [lib/src/screens/session_detail_screen.dart:11957](../lib/src/screens/session_detail_screen.dart#L11957) · widget.loadingBuilder() |
| [本地缩略图读取失败](states.html?id=render-image-hidden-error#render-image-hidden-error) | Bridge 读取失败或没有数据，缩略图分支返回 SizedBox.shrink | — | — | 失败的缩略图 | [lib/src/screens/session_detail_screen.dart:6224](../lib/src/screens/session_detail_screen.dart#L6224) · snapshot.hasError  /  /  !snapshot.hasData |
| [缩略图解码失败](states.html?id=render-image-decode-error#render-image-decode-error) | 图片字节不可解码，缩略图内容收起 | — | — | — | [lib/src/screens/session_detail_screen.dart:5937](../lib/src/screens/session_detail_screen.dart#L5937) · errorBuilder: (context, _, __) =&gt; const SizedBox.shrink() |
| [全屏媒体读取中](states.html?id=render-image-preview-loading#render-image-preview-loading) | 打开本地图片预览，文件 Future 尚未完成 | 关闭预览、切换背景 | — | — | [lib/src/screens/session_detail_screen.dart:6215](../lib/src/screens/session_detail_screen.dart#L6215) · snapshot.connectionState != ConnectionState.done |
| [全屏图片加载失败](states.html?id=render-image-preview-failed#render-image-preview-failed) | 全屏读取或图片解码失败 | 关闭预览、切换背景 | — | 虚构的重试按钮 | [lib/src/screens/session_detail_screen.dart:6135](../lib/src/screens/session_detail_screen.dart#L6135) · _buildImagePreviewError( |
| [画廊第一项](states.html?id=render-gallery-0#render-gallery-0) | 同一消息有 3 个媒体引用，当前索引为 0 | 关闭、切换背景、下一项 | 上一项 | — | [lib/src/screens/session_detail_screen.dart:6496](../lib/src/screens/session_detail_screen.dart#L6496) · image-preview-previous |
| [画廊中间项](states.html?id=render-gallery-1#render-gallery-1) | 同一消息有 3 个媒体引用，当前索引为 1 | 关闭、切换背景、上一项、下一项 | — | — | [lib/src/screens/session_detail_screen.dart:6496](../lib/src/screens/session_detail_screen.dart#L6496) · image-preview-previous |
| [画廊最后一项](states.html?id=render-gallery-2#render-gallery-2) | 同一消息有 3 个媒体引用，当前索引为 2 | 关闭、切换背景、上一项 | 下一项 | — | [lib/src/screens/session_detail_screen.dart:6496](../lib/src/screens/session_detail_screen.dart#L6496) · image-preview-previous |

## 视频播放

| 状态 | 触发条件 | 可用操作 | 禁用 | 隐藏 | 源码依据 |
| --- | --- | --- | --- | --- | --- |
| [MP4 缩略图回退](states.html?id=render-video-fallback#render-video-fallback) | 缩略图未初始化、初始化失败，或平台不支持内联视频帧 | 打开视频 | — | — | [lib/src/screens/session_detail_screen.dart:5982](../lib/src/screens/session_detail_screen.dart#L5982) · _buildVideoThumbnailFallback |
| [MP4 视频首帧](states.html?id=render-video-thumbnail#render-video-thumbnail) | 支持内联视频帧且缩略图已完成初始化 | 打开视频预览 | — | — | [lib/src/screens/session_detail_screen.dart:6052](../lib/src/screens/session_detail_screen.dart#L6052) · video-thumbnail-icon- |
| [视频播放器初始化](states.html?id=render-video-loading#render-video-loading) | 视频文件读取或播放器初始化尚未完成 | 关闭、切换背景 | 播放 / 暂停、静音切换、进度拖动 | — | [lib/src/screens/session_detail_screen.dart:13392](../lib/src/screens/session_detail_screen.dart#L13392) · initializeFuture == null  /  /  controller == null |
| [播放中 / 静音](states.html?id=render-video-playing-muted#render-video-playing-muted) | 播放器已初始化，isPlaying=true，muted=true | 播放 / 暂停、切换静音、拖动进度、关闭、切换背景 | — | — | [lib/src/screens/session_detail_screen.dart:13441](../lib/src/screens/session_detail_screen.dart#L13441) · video-preview-toggle-play |
| [播放中 / 有声](states.html?id=render-video-playing-sound#render-video-playing-sound) | 播放器已初始化，isPlaying=true，muted=false | 播放 / 暂停、切换静音、拖动进度、关闭、切换背景 | — | — | [lib/src/screens/session_detail_screen.dart:13441](../lib/src/screens/session_detail_screen.dart#L13441) · video-preview-toggle-play |
| [已暂停 / 静音](states.html?id=render-video-paused-muted#render-video-paused-muted) | 播放器已初始化，isPlaying=false，muted=true | 播放 / 暂停、切换静音、拖动进度、关闭、切换背景 | — | — | [lib/src/screens/session_detail_screen.dart:13441](../lib/src/screens/session_detail_screen.dart#L13441) · video-preview-toggle-play |
| [已暂停 / 有声](states.html?id=render-video-paused-sound#render-video-paused-sound) | 播放器已初始化，isPlaying=false，muted=false | 播放 / 暂停、切换静音、拖动进度、关闭、切换背景 | — | — | [lib/src/screens/session_detail_screen.dart:13441](../lib/src/screens/session_detail_screen.dart#L13441) · video-preview-toggle-play |
| [竖屏视频比例](states.html?id=render-video-portrait#render-video-portrait) | 视频已初始化，采用播放器返回的原始宽高比 | 播放 / 暂停、静音切换、拖动进度、缩放、关闭 | — | — | [lib/src/screens/session_detail_screen.dart:13420](../lib/src/screens/session_detail_screen.dart#L13420) · controller.value.aspectRatio |
| [视频播放失败](states.html?id=render-video-error#render-video-error) | 视频读取或初始化失败 | 关闭、切换背景 | — | 重试按钮、不可用播放控件 | [lib/src/screens/session_detail_screen.dart:13387](../lib/src/screens/session_detail_screen.dart#L13387) · _buildPreviewError(errorMessage) |
| [桌面端交给外部播放器](states.html?id=render-video-external#render-video-external) | Linux / Windows 点击视频引用，进入外部打开流程 | 通过系统播放器打开 | — | 应用内视频播放器 | [lib/src/screens/session_detail_screen.dart:6084](../lib/src/screens/session_detail_screen.dart#L6084) · _openVideoExternally( |

## Diff 与文件变更

| 状态 | 触发条件 | 可用操作 | 禁用 | 隐藏 | 源码依据 |
| --- | --- | --- | --- | --- | --- |
| [单文件变更摘要](states.html?id=render-diff-single#render-diff-single) | 当前轮次只有一个文件变更 | 打开全屏 Diff | — | 多文件展开开关 | [lib/src/screens/session_detail_screen.dart:5040](../lib/src/screens/session_detail_screen.dart#L5040) · diffs.length == 1 |
| [多文件变更 / 收起](states.html?id=render-diff-collapsed#render-diff-collapsed) | 当前轮次有多个变更，expanded=false | 打开首个 Diff、展开其他文件 | — | 其余文件摘要 | [lib/src/screens/session_detail_screen.dart:5043](../lib/src/screens/session_detail_screen.dart#L5043) · _expandedDiffTurnIds.contains(turn.id) |
| [多文件变更 / 展开](states.html?id=render-diff-expanded#render-diff-expanded) | 当前轮次有多个变更，expanded=true | 查看各文件 Diff、收起其他文件 | — | — | [lib/src/screens/session_detail_screen.dart:5082](../lib/src/screens/session_detail_screen.dart#L5082) · for (final diff in diffs.skip(1)) |
| [全屏 Diff / 原行与新行](states.html?id=render-diff-detail#render-diff-detail) | 点击文件变更摘要，打开全屏 Diff | 关闭、选择文本、横向与纵向滚动 | — | — | [lib/src/screens/session_detail_screen.dart:12597](../lib/src/screens/session_detail_screen.dart#L12597) · _buildLineSpan( |
| [Diff 无 patch / 使用 summary](states.html?id=render-diff-summary-only#render-diff-summary-only) | patch 为空，优先显示 summary，否则显示 No diff details | 关闭 | — | — | [lib/src/screens/session_detail_screen.dart:5189](../lib/src/screens/session_detail_screen.dart#L5189) · diff.summary ?? 'No diff details' |
| [超长 Diff / 虚拟列表](states.html?id=render-diff-long#render-diff-long) | 解析后行数大于 1000，使用固定行高的虚拟列表 | 关闭、横向与纵向滚动 | — | — | [lib/src/screens/session_detail_screen.dart:12557](../lib/src/screens/session_detail_screen.dart#L12557) · _virtualizedLineThreshold = 1000 |
| [消息内 fenced diff 文本](states.html?id=render-diff-fenced-text#render-diff-fenced-text) | 助手在普通 Markdown 回复中返回 diff 代码块 | 选择文本 | — | — | [lib/src/screens/session_detail_screen.dart:5560](../lib/src/screens/session_detail_screen.dart#L5560) · syntaxHighlighter: |

## 当前枚举与阶段覆盖

| 枚举 / 阶段表 | 数量 | 已对应独立画面 |
| --- | --- | --- |
| SessionStatus | 6 | session-idle、session-running、session-awaiting-approval、session-interrupted、session-waiting、session-failed |
| ExecutionPhase | 8 | execution-starting、execution-thinking、execution-runningCommand、execution-awaitingApproval、execution-retrying、execution-waitingForTool、execution-background、execution-unconfirmed |
| _LocalMessageState | 4 | message-queued、message-pending、message-submitted、message-failed |
| _VoiceHoldAction | 3 | composer-hold-send、composer-hold-insert、composer-hold-cancel |
| _CallModeSpeechHintState | 2 | call-detected、call-pause |
| _ImagePreviewBackdropMode | 3 | image-backdrop-dark、image-backdrop-light、image-backdrop-checker |
| _ComposerSettingsPanelSection | 3 | composer-select-provider、composer-select-reasoning、composer-select-model |
| AcceptancePhase | 11 | acceptance-phase-not_installed、acceptance-phase-checking、acceptance-phase-preparing、acceptance-phase-verifying、acceptance-phase-ready、acceptance-phase-starting、acceptance-phase-planning、acceptance-phase-running、acceptance-phase-stopping、acceptance-phase-completed、acceptance-phase-failed |
