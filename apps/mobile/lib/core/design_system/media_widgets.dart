import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import '../../app/providers.dart';
import 'components.dart';

class MediaImage extends ConsumerStatefulWidget {
  const MediaImage({super.key, required this.id, this.fit = BoxFit.cover});
  final String id;
  final BoxFit fit;
  @override
  ConsumerState<MediaImage> createState() => _MediaImageState();
}

class _MediaImageState extends ConsumerState<MediaImage> {
  late Future<dynamic> access;
  void load() {
    access = ref
        .read(clientProvider)
        .get('/media/${widget.id}/access', cached: false);
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant MediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) load();
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<dynamic>(
    future: access,
    builder: (c, s) => s.hasData
        ? Image.network(
            s.data['url'],
            fit: widget.fit,
            errorBuilder: (_, e, st) => GestureDetector(
              onTap: () => setState(load),
              child: const Center(child: Icon(Icons.refresh)),
            ),
          )
        : s.hasError
        ? GestureDetector(
            onTap: () => setState(load),
            child: const Center(child: Icon(Icons.refresh)),
          )
        : const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
  );
}

class UserAvatar extends StatelessWidget {
  const UserAvatar(this.user, {super.key, this.size = 48});
  final Map user;
  final double size;
  @override
  Widget build(BuildContext c) => user['avatarId'] == null
      ? QChatAvatar(user['nickname']?.toString() ?? '', size: size)
      : ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            width: size,
            height: size,
            child: MediaImage(id: user['avatarId']),
          ),
        );
}
