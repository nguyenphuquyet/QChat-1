import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/localization/strings.dart';
import '../../core/design_system/media_widgets.dart';
import '../../core/design_system/dialogs.dart';
import 'moment_composer.dart';

class MomentsScreen extends ConsumerStatefulWidget {
  const MomentsScreen({super.key});
  @override
  ConsumerState<MomentsScreen> createState() => _MomentsScreenState();
}

class _MomentsScreenState extends ConsumerState<MomentsScreen> {
  late Future<dynamic> feed;
  StreamSubscription<void>? updates;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
    updates = ref.read(clientProvider).changes.stream.listen((_) {
      if (mounted) setState(load);
    });
  }

  void load() {
    feed = ref.read(clientProvider).get('/moments', cached: false);
  }

  @override
  void dispose() {
    updates?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => QChatPage(
    title: tr(c, 'moments'),
    leading: QChatIconButton(
      'back',
      label: tr(c, 'back'),
      onTap: () => context.pop(),
    ),
    trailing: QChatIconButton(
      'plus',
      label: tr(c, 'post'),
      onTap: () async {
        final posted = await Navigator.of(
          c,
        ).push<bool>(MaterialPageRoute(builder: (_) => const MomentComposer()));
        if (posted == true && mounted) setState(load);
      },
    ),
    child: Column(
      children: [
        if (error != null)
          Text(error!, style: const TextStyle(color: QChatColors.danger)),
        Expanded(
          child: FutureBuilder<dynamic>(
            future: feed,
            builder: (c, s) {
              if (s.hasError && !ref.read(clientProvider).offline.value) {
                return QChatError(error: s.error!, retry: () => setState(load));
              }
              final posts = s.data as List? ?? [];
              if (!s.hasData && !s.hasError) return const QChatLoading();
              return ListView(
                children: [
                  Container(
                    height: 190,
                    color: const Color(0xff2f5345),
                    padding: const EdgeInsets.all(24),
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      tr(c, 'moments'),
                      style: const TextStyle(
                        fontSize: 30,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (posts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: QChatEmptyState(tr(c, 'emptyMoments')),
                    ),
                  for (final p in posts)
                    _MomentCard(
                      post: p,
                      myId: ref.read(clientProvider).userId,
                      onReload: () => setState(load),
                      onError: (msg) => setState(() => error = msg),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

// ─── Card từng bài viết ──────────────────────────────────────────────────────

class _MomentCard extends ConsumerStatefulWidget {
  const _MomentCard({
    required this.post,
    required this.myId,
    required this.onReload,
    required this.onError,
  });
  final Map post;
  final String? myId;
  final VoidCallback onReload;
  final void Function(String) onError;

  @override
  ConsumerState<_MomentCard> createState() => _MomentCardState();
}

class _MomentCardState extends ConsumerState<_MomentCard> {
  /// null = ẩn input; non-null = đang mở input cho bài post này
  bool _showInput = false;
  final _commentCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(clientProvider).post(
        '/moments/${widget.post['id']}/comments',
        {'text': text},
      );
      _commentCtrl.clear();
      setState(() {
        _showInput = false;
        _sending = false;
      });
      widget.onReload();
    } catch (_) {
      if (mounted) {
        setState(() => _sending = false);
        widget.onError(tr(context, 'networkError'));
      }
    }
  }

  Future<void> _toggleLike() async {
    final liked = (widget.post['likes'] as List).any(
      (l) => l['userId'] == widget.myId,
    );
    try {
      if (liked) {
        await ref
            .read(clientProvider)
            .dio
            .delete('/moments/${widget.post['id']}/likes');
      } else {
        await ref
            .read(clientProvider)
            .post('/moments/${widget.post['id']}/likes', {});
      }
      widget.onReload();
    } catch (_) {
      if (mounted) widget.onError(tr(context, 'networkError'));
    }
  }

  Future<void> _delete() async {
    if (!await confirmAction(
          context,
          tr(context, 'delete'),
          tr(context, 'deleteMoment'),
        ) ||
        !mounted) {
      return;
    }
    try {
      await ref
          .read(clientProvider)
          .dio
          .delete('/moments/${widget.post['id']}');
      widget.onReload();
    } catch (_) {
      if (mounted) widget.onError(tr(context, 'networkError'));
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = widget.post;
    final liked = (p['likes'] as List).any((l) => l['userId'] == widget.myId);
    return Container(
      color: surface(c),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(p['author'], size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tên tác giả
                Text(
                  p['author']['nickname'],
                  style: const TextStyle(
                    color: Color(0xff546d91),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                // Nội dung
                Text(p['text']),
                const SizedBox(height: 10),
                // Media
                if ((p['media'] as List).isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final media in p['media'])
                        GestureDetector(
                          onTap: () =>
                              context.push('/media/${media['mediaId']}'),
                          child: SizedBox(
                            width: 120,
                            height: 120,
                            child: (media['media']?['mime'] as String? ?? '')
                                    .startsWith('video/')
                                ? ColoredBox(
                                    color: const Color(0xff252525),
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const QChatIcon(
                                            'videoCall',
                                            color: Colors.white,
                                            size: 36,
                                          ),
                                          Text(
                                            tr(c, 'play'),
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : MediaImage(id: media['mediaId']),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 10),
                // Hàng ngày + thao tác
                Row(
                  children: [
                    Text(
                      p['createdAt'].toString().substring(0, 10),
                      style: const TextStyle(
                        fontSize: 11,
                        color: QChatColors.muted,
                      ),
                    ),
                    const Spacer(),
                    // Nút like
                    GestureDetector(
                      onTap: _toggleLike,
                      child: Row(
                        children: [
                          QChatIcon(
                            'heart',
                            size: 18,
                            filled: liked,
                            color: liked
                                ? QChatColors.danger
                                : QChatColors.muted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${(p['likes'] as List).length}',
                            style: TextStyle(
                              fontSize: 13,
                              color: liked
                                  ? QChatColors.danger
                                  : QChatColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Nút bình luận inline
                    GestureDetector(
                      onTap: () => setState(() => _showInput = !_showInput),
                      child: QChatIcon(
                        'chats',
                        size: 18,
                        color: _showInput
                            ? QChatColors.green
                            : QChatColors.muted,
                      ),
                    ),
                    // Nút xóa (chỉ chủ bài)
                    if (p['authorId'] == widget.myId) ...[
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: _delete,
                        child: const QChatIcon(
                          'close',
                          size: 18,
                          color: QChatColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),

                // Danh sách bình luận
                if ((p['comments'] as List).isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: ink(c).withValues(alpha: .05),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final comment in p['comments'])
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  fontSize: 13,
                                  color: ink(c),
                                ),
                                children: [
                                  if ((comment['author']?['nickname'] ?? '')
                                      .toString()
                                      .isNotEmpty)
                                    TextSpan(
                                      text:
                                          '${comment['author']['nickname']}: ',
                                      style: const TextStyle(
                                        color: Color(0xff546d91),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  TextSpan(text: comment['text']),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                // Input bình luận inline
                if (_showInput)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TInput(
                            controller: _commentCtrl,
                            hintText: tr(c, 'comment'),
                            maxLines: 3,
                            minLines: 1,
                            maxLength: 1000,
                            enabled: !_sending,
                            autofocus: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _sending ? null : _sendComment,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: QChatColors.green,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              tr(c, 'send'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
