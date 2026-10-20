import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/design_system/media_widgets.dart';
import '../../core/design_system/reference_widgets.dart';
import '../../core/localization/strings.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final query = TextEditingController();
  Timer? debounce;
  int generation = 0;
  bool busy = false;
  Object? error;
  Map data = {};

  void changed(String value) {
    debounce?.cancel();
    final version = ++generation;
    setState(() {
      data = {};
      error = null;
      busy = value.trim().isNotEmpty;
    });
    if (value.trim().isEmpty) return;
    debounce = Timer(const Duration(milliseconds: 350), () => search(version));
  }

  Future<void> search(int version) async {
    try {
      final result = await ref
          .read(clientProvider)
          .get(
            '/search?q=${Uri.encodeComponent(query.text.trim())}',
            cached: false,
          );
      if (mounted && version == generation) {
        setState(() => data = result as Map);
      }
    } catch (e) {
      if (mounted && version == generation) setState(() => error = e);
    } finally {
      if (mounted && version == generation) setState(() => busy = false);
    }
  }

  Future<void> chat(String friendId) async {
    try {
      final result = await ref.read(clientProvider).post('/conversations', {
        'memberIds': [friendId],
      });
      if (mounted) context.push('/chat/${result['id']}');
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final friends = data['friends'] as List? ?? [];
    final conversations = data['conversations'] as List? ?? [];
    final messages = data['messages'] as List? ?? [];
    return QChatPage(
      title: tr(c, 'search'),
      leading: QChatIconButton(
        'back',
        label: tr(c, 'back'),
        onTap: () => c.pop(),
      ),
      child: Column(
        children: [
          QChatSearchBar(controller: query, onChanged: changed),
          Expanded(
            child: busy
                ? const QChatLoading()
                : error != null
                ? QChatError(error: error!, retry: () => changed(query.text))
                : ListView(
                    children: [
                      if (query.text.trim().isEmpty)
                        QChatEmptyState(tr(c, 'searchHint')),
                      if (query.text.trim().isNotEmpty &&
                          friends.isEmpty &&
                          conversations.isEmpty &&
                          messages.isEmpty)
                        QChatEmptyState(tr(c, 'noItems')),
                      if (friends.isNotEmpty) const SectionLabel('contacts'),
                      for (final item in friends)
                        QChatListTile(
                          title: item['friend']['nickname'],
                          subtitle: item['friend']['qchatId'],
                          leading: UserAvatar(item['friend'], size: 42),
                          onTap: () => c.push('/user/${item['friend']['id']}'),
                        ),
                      if (conversations.isNotEmpty)
                        const SectionLabel('conversations'),
                      for (final item in conversations)
                        QChatListTile(
                          title: item['kind'] == 'GROUP'
                              ? item['title']
                              : (item['members'] as List)
                                    .where(
                                      (m) =>
                                          m['userId'] !=
                                          ref.read(clientProvider).userId,
                                    )
                                    .map((m) => m['user']['nickname'])
                                    .join(', '),
                          onTap: () => c.push('/chat/${item['id']}'),
                        ),
                      if (messages.isNotEmpty) const SectionLabel('messages'),
                      for (final item in messages)
                        QChatListTile(
                          title: item['text'],
                          subtitle: item['sender']['nickname'],
                          onTap: () =>
                              c.push('/chat/${item['conversationId']}'),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
