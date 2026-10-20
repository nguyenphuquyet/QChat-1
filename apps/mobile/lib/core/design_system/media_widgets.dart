import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/network/client.dart';
import '../../core/storage/database.dart';
import 'components.dart';

class MediaCache {
  static final Map<String, Uint8List> _memory = {};
  static final Map<String, Future<Uint8List?>> _inFlight = {};
  static const int maxMemoryEntries = 250;

  static Uint8List? getFromMemory(String id) => _memory[id];

  static void put(String id, Uint8List bytes, {LocalDatabase? local}) {
    if (id.isEmpty || bytes.isEmpty) return;
    if (_memory.length >= maxMemoryEntries) {
      _memory.remove(_memory.keys.first);
    }
    _memory[id] = bytes;
    if (local != null) {
      unawaited(
        local
            .cache('media_bytes:$id', base64Encode(bytes))
            .catchError((_) {}),
      );
    }
  }

  static void evict(String id, {LocalDatabase? local}) {
    _memory.remove(id);
    if (local != null) {
      unawaited(
        local
            .removeCache('media_bytes:$id')
            .catchError((_) {}),
      );
    }
  }

  static void clear() {
    _memory.clear();
    _inFlight.clear();
  }

  static Future<Uint8List?> load(QChatClient client, String id) {
    if (id.isEmpty) return Future.value(null);
    final inMem = _memory[id];
    if (inMem != null) return Future.value(inMem);

    final existing = _inFlight[id];
    if (existing != null) return existing;

    final future = _loadFromDiskOrNetwork(client, id);
    _inFlight[id] = future;
    return future.whenComplete(() => _inFlight.remove(id));
  }

  static Future<Uint8List?> _loadFromDiskOrNetwork(
    QChatClient client,
    String id,
  ) async {
    // 1. Check local database cache
    try {
      final disk = await client.local?.read('media_bytes:$id');
      if (disk is String && disk.isNotEmpty) {
        final bytes = base64Decode(disk);
        if (_memory.length >= maxMemoryEntries) {
          _memory.remove(_memory.keys.first);
        }
        _memory[id] = bytes;
        return bytes;
      }
    } catch (_) {}

    // 2. Load access URL and bytes from server
    try {
      final access = await client.get('/media/$id/access', cached: true);
      if (access is Map && access['url'] != null) {
        final url = access['url'].toString();
        final response = await client.dio.get<List<int>>(
          url,
          options: Options(
            responseType: ResponseType.bytes,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 20),
          ),
        );
        final data = response.data;
        if (data != null && data.isNotEmpty) {
          final bytes = Uint8List.fromList(data);
          put(id, bytes, local: client.local);
          return bytes;
        }
      }
    } catch (_) {}
    return null;
  }
}

class MediaImage extends ConsumerStatefulWidget {
  const MediaImage({
    super.key,
    required this.id,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });
  final String id;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  ConsumerState<MediaImage> createState() => _MediaImageState();
}

class _MediaImageState extends ConsumerState<MediaImage> {
  Uint8List? _bytes;
  bool _error = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _load();
    }
  }

  void _load() {
    final mem = MediaCache.getFromMemory(widget.id);
    if (mem != null) {
      _bytes = mem;
      _error = false;
      return;
    }

    _bytes = null;
    _error = false;
    final currentRev = ++_revision;
    final client = ref.read(clientProvider);

    MediaCache.load(client, widget.id).then((bytes) {
      if (mounted && currentRev == _revision) {
        setState(() {
          _bytes = bytes;
          _error = bytes == null;
        });
      }
    }).catchError((_) {
      if (mounted && currentRev == _revision) {
        setState(() {
          _error = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext c) {
    if (_bytes != null) {
      return Image.memory(
        _bytes!,
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _buildError(),
      );
    }
    if (_error) {
      return _buildError();
    }
    return widget.placeholder ??
        const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
  }

  Widget _buildError() =>
      widget.errorWidget ??
      GestureDetector(
        onTap: () => setState(_load),
        child: const Center(
          child: TIcon(TIcons.refresh, size: 20, color: QChatColors.muted),
        ),
      );
}

class UserAvatar extends StatelessWidget {
  const UserAvatar(this.user, {super.key, this.size = 48});
  final Map user;
  final double size;
  @override
  Widget build(BuildContext c) {
    final avatarId = user['avatarId']?.toString();
    final nickname = user['nickname']?.toString() ?? '';
    final fallback = QChatAvatar(nickname, size: size);

    return Theme(
      data: Theme.of(c).copyWith(
        extensions: [
          ...Theme.of(c).extensions.values.where((e) => e is! TAvatarThemeData),
          TAvatarThemeData(dimension: size, squareBorderRadius: 5),
        ],
      ),
      child: TAvatar(
        shape: TAvatarShape.square,
        onTap: user['id'] == null ? null : () => c.push('/user/${user['id']}'),
        child: avatarId == null || avatarId.isEmpty
            ? fallback
            : SizedBox.square(
                dimension: size,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: MediaImage(
                    id: avatarId,
                    placeholder: fallback,
                    errorWidget: fallback,
                  ),
                ),
              ),
      ),
    );
  }
}
