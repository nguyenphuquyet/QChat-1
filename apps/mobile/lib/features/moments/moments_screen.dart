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
                    Container(
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
                                Text(
                                  p['author']['nickname'],
                                  style: const TextStyle(
                                    color: Color(0xff546d91),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(p['text']),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final media in p['media'])
                                      GestureDetector(
                                        onTap: () => context.push(
                                          '/media/${media['mediaId']}',
                                        ),
                                        child: SizedBox(
                                          width: 120,
                                          height: 120,
                                          child:
                                              (media['media']?['mime']
                                                          as String? ??
                                                      '')
                                                  .startsWith('video/')
                                              ? ColoredBox(
                                                  color: const Color(
                                                    0xff252525,
                                                  ),
                                                  child: Center(
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        const QChatIcon(
                                                          'videoCall',
                                                          color: Colors.white,
                                                          size: 36,
                                                        ),
                                                        Text(
                                                          tr(c, 'play'),
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                )
                                              : MediaImage(
                                                  id: media['mediaId'],
                                                ),
                                        ),
                                      ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Text(
                                      p['createdAt'].toString().substring(
                                        0,
                                        10,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: QChatColors.muted,
                                      ),
                                    ),
                                    const Spacer(),
                                    QChatButton(
                                      '♡ ${(p['likes'] as List).length}',
                                      secondary: true,
                                      onTap: () async {
                                        try {
                                          final liked = (p['likes'] as List)
                                              .any(
                                                (l) =>
                                                    l['userId'] ==
                                                    ref
                                                        .read(clientProvider)
                                                        .userId,
                                              );
                                          if (liked) {
                                            await ref
                                                .read(clientProvider)
                                                .dio
                                                .delete(
                                                  '/moments/${p['id']}/likes',
                                                );
                                          } else {
                                            await ref
                                                .read(clientProvider)
                                                .post(
                                                  '/moments/${p['id']}/likes',
                                                  {},
                                                );
                                          }
                                          if (mounted) setState(load);
                                        } catch (e) {
                                          if (mounted) {
                                            setState(
                                              () =>
                                                  error = tr(c, 'networkError'),
                                            );
                                          }
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    QChatButton(
                                      tr(c, 'comment'),
                                      secondary: true,
                                      onTap: () async {
                                        final value = await editText(
                                          c,
                                          tr(c, 'comment'),
                                          maxLength: 1000,
                                          lines: 3,
                                        );
                                        if (value == null ||
                                            value.isEmpty ||
                                            !mounted)
                                          return;
                                        try {
                                          await ref.read(clientProvider).post(
                                            '/moments/${p['id']}/comments',
                                            {'text': value},
                                          );
                                          if (mounted) setState(load);
                                        } catch (_) {
                                          if (mounted)
                                            setState(
                                              () => error = tr(
                                                context,
                                                'networkError',
                                              ),
                                            );
                                        }
                                      },
                                    ),
                                    if (p['authorId'] ==
                                        ref.read(clientProvider).userId)
                                      QChatButton(
                                        tr(c, 'delete'),
                                        secondary: true,
                                        onTap: () async {
                                          if (!await confirmAction(
                                                c,
                                                tr(c, 'delete'),
                                                tr(c, 'deleteMoment'),
                                              ) ||
                                              !mounted)
                                            return;
                                          try {
                                            await ref
                                                .read(clientProvider)
                                                .dio
                                                .delete('/moments/${p['id']}');
                                            if (mounted) setState(load);
                                          } catch (_) {
                                            if (mounted)
                                              setState(
                                                () => error = tr(
                                                  context,
                                                  'networkError',
                                                ),
                                              );
                                          }
                                        },
                                      ),
                                  ],
                                ),
                                for (final comment in p['comments'])
                                  Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Text(
                                      comment['text'],
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
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
