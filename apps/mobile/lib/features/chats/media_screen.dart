import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../app/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/localization/strings.dart';

class MediaScreen extends ConsumerStatefulWidget {
  const MediaScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends ConsumerState<MediaScreen> {
  late Future<dynamic> data;
  @override
  void initState() {
    super.initState();
    data = ref
        .read(clientProvider)
        .get('/media/${widget.id}/access', cached: false);
  }

  @override
  Widget build(BuildContext c) => QChatPage(
    title: tr(c, 'image'),
    leading: QChatIconButton(
      'back',
      label: tr(c, 'back'),
      onTap: () => context.pop(),
    ),
    child: FutureBuilder<dynamic>(
      future: data,
      builder: (c, s) => s.hasError
          ? QChatError(
              error: s.error!,
              retry: () => setState(
                () => data = ref
                    .read(clientProvider)
                    .get('/media/${widget.id}/access', cached: false),
              ),
            )
          : !s.hasData
          ? const QChatLoading()
          : (s.data['mime'] as String? ?? '').startsWith('video/')
          ? VideoMedia(url: s.data['url'])
          : InteractiveViewer(
              minScale: .5,
              maxScale: 5,
              child: Center(
                child: Image.network(
                  s.data['url'],
                  errorBuilder: (_, e, st) => QChatEmptyState(tr(c, 'file')),
                ),
              ),
            ),
    ),
  );
}

class VideoMedia extends StatefulWidget {
  const VideoMedia({super.key, required this.url});
  final String url;
  @override
  State<VideoMedia> createState() => _VideoMediaState();
}

class _VideoMediaState extends State<VideoMedia> {
  late final VideoPlayerController controller;
  String? error;
  @override
  void initState() {
    super.initState();
    controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    controller
        .initialize()
        .then((_) {
          if (mounted) setState(() {});
        })
        .catchError((Object e) {
          if (mounted) setState(() => error = e.toString());
        });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    if (error != null) return QChatEmptyState(tr(c, 'videoPlaybackError'));
    if (!controller.value.isInitialized) return const QChatLoading();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
        VideoProgressIndicator(controller, allowScrubbing: true),
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: controller,
          builder: (c, value, _) => QChatButton(
            tr(c, value.isPlaying ? 'pause' : 'play'),
            onTap: () =>
                value.isPlaying ? controller.pause() : controller.play(),
          ),
        ),
      ],
    );
  }
}
