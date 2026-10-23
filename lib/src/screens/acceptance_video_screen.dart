import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../bridge_client.dart';
import '../l10n/app_locale.dart';

class AcceptanceVideoScreen extends StatefulWidget {
  const AcceptanceVideoScreen({
    super.key,
    required this.client,
    required this.runId,
    required this.name,
  });

  final BridgeClient client;
  final String runId, name;

  @override
  State<AcceptanceVideoScreen> createState() => _AcceptanceVideoScreenState();
}

class _AcceptanceVideoScreenState extends State<AcceptanceVideoScreen> {
  VideoPlayerController? controller;
  String? error;
  Directory? cacheDirectory;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final old = controller;
    final oldCache = cacheDirectory;
    setState(() {
      controller = null;
      error = null;
      cacheDirectory = null;
    });
    await old?.dispose();
    if (oldCache != null && await oldCache.exists()) {
      await oldCache.delete(recursive: true);
    }
    if (!mounted) return;
    Directory? cache;
    try {
      cache =
          await (await getTemporaryDirectory()).createTemp('acceptance-video-');
      cacheDirectory = cache;
      final file = File([cache.path, 'recording.mp4'].join('/'));
      final stream =
          await widget.client.acceptanceVideoStream(widget.runId, widget.name);
      await stream.pipe(file.openWrite());
      if (!mounted) {
        if (await cache.exists()) await cache.delete(recursive: true);
        return;
      }
      final player = VideoPlayerController.file(file);
      controller = player;
      await player.initialize();
      if (!mounted || controller != player) return;
      setState(() {});
      await player.play();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
      if (cache != null && await cache.exists()) {
        await cache.delete(recursive: true);
      }
    }
  }

  @override
  void dispose() {
    final player = controller;
    final cache = cacheDirectory;
    unawaited(() async {
      await player?.dispose();
      if (cache != null && await cache.exists()) {
        await cache.delete(recursive: true);
      }
    }());
    super.dispose();
  }

  String timestamp(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final player = controller;
    return Scaffold(
      appBar: AppBar(title: Text(l.acceptanceRecording)),
      body: SafeArea(
          child: error != null
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(l.acceptanceVideoError),
                        const SizedBox(height: 8),
                        Text(error!,
                            maxLines: 4, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: load, child: Text(l.retry)),
                      ])))
              : player == null || !player.value.isInitialized
                  ? const Center(child: CircularProgressIndicator())
                  : ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: player,
                      builder: (context, value, _) => Column(children: [
                        Expanded(
                            child: Center(
                                child: AspectRatio(
                                    aspectRatio: value.aspectRatio,
                                    child: VideoPlayer(player)))),
                        Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(children: [
                              VideoProgressIndicator(player,
                                  allowScrubbing: true,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12)),
                              Row(children: [
                                IconButton(
                                    tooltip: value.isPlaying
                                        ? l.acceptanceVideoPause
                                        : l.acceptanceVideoPlay,
                                    onPressed: () => value.isPlaying
                                        ? player.pause()
                                        : player.play(),
                                    icon: Icon(value.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded)),
                                const SizedBox(width: 8),
                                Text([
                                  timestamp(value.position),
                                  timestamp(value.duration)
                                ].join(' / ')),
                                const Spacer(),
                                IconButton(
                                    tooltip: l.acceptanceVideoReplay,
                                    onPressed: () async {
                                      await player.seekTo(Duration.zero);
                                      await player.play();
                                    },
                                    icon: const Icon(Icons.replay_rounded)),
                              ]),
                            ])),
                      ]),
                    )),
    );
  }
}
