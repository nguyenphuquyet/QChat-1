import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/design_system/reference_widgets.dart';
import '../../core/design_system/media_widgets.dart';
import '../../core/design_system/dialogs.dart';
import '../../core/localization/strings.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int index = 0;
  final search = TextEditingController();
  late Future<dynamic> data;
  StreamSubscription<void>? updates;
  final sectionKeys = <String, GlobalKey>{};
  @override
  void initState() {
    super.initState();
    load();
    updates = ref.read(clientProvider).changes.stream.listen((_) {
      if (mounted) setState(load);
    });
  }

  void load() {
    data = ref
        .read(clientProvider)
        .get(
          index == 0
              ? '/conversations'
              : index == 1
              ? '/friends'
              : '/users/me',
        );
  }

  @override
  void dispose() {
    updates?.cancel();
    search.dispose();
    super.dispose();
  }

  String conversationName(Map c) {
    if (c['kind'] == 'GROUP') return c['title'] ?? 'QChat';
    final others = (c['members'] as List).where(
      (m) => m['userId'] != ref.read(clientProvider).userId,
    );
    return others.isEmpty ? 'QChat' : others.first['user']['nickname'];
  }

  void switchTab(int value) => setState(() {
    index = value;
    search.clear();
    load();
  });
  Future<void> invite() async {
    final u = await ref.read(clientProvider).get('/users/me');
    await Clipboard.setData(ClipboardData(text: 'QChat ID: ${u['qchatId']}'));
    if (mounted) qchatSheet(context, [(tr(context, 'copied'), () {})]);
  }

  void menu(BuildContext c) => qchatTopMenu(c, [
    ('chats', 'newChat', () => c.push('/groups/new')),
    ('addFriend', 'addFriend', () => c.push('/friends')),
    ('scan', 'scan', () => c.push('/scan')),
    ('payments', 'payments', () => openFeature(c, 'payments')),
  ]);
  @override
  Widget build(BuildContext c) {
    final offline = ref.read(clientProvider).offline;
    return ValueListenableBuilder<bool>(
      valueListenable: offline,
      builder: (c, isOffline, _) => QChatPage(
        statusBackground: index == 3 ? surface(c) : null,
        navigationBackground: navigationSurface(c),
        edgeToEdge: true,
        title: index == 3
            ? null
            : index == 0
            ? (isOffline ? tr(c, 'disconnected') : 'QChat')
            : tr(c, index == 1 ? 'contacts' : 'discover'),
        trailing: index < 2
            ? QChatIconButton(
                index == 0 ? 'plus' : 'addFriend',
                label: tr(c, 'addFriend'),
                onTap: () => index == 0 ? menu(c) : c.push('/friends'),
              )
            : null,
        bottom: QChatBottomNavigation(index: index, onChanged: switchTab),
        child: index == 2
            ? discover(c)
            : FutureBuilder<dynamic>(
                key: ValueKey(index),
                future: data,
                builder: (c, s) {
                  if (s.hasError && !ref.read(clientProvider).offline.value) {
                    return QChatError(
                      error: s.error!,
                      retry: () => setState(load),
                    );
                  }
                  if (index == 3) {
                    return me(
                      c,
                      s.data as Map? ?? {'nickname': '', 'qchatId': ''},
                    );
                  }
                  var items = (s.data as List? ?? [])
                      .where(
                        (item) =>
                            (index == 0
                                    ? conversationName(item)
                                    : item['friend']['nickname'])
                                .toString()
                                .toLowerCase()
                                .contains(search.text.toLowerCase()),
                      )
                      .toList();
                  if (index == 0) {
                    bool pinned(dynamic chat) => (chat['members'] as List).any(
                      (m) =>
                          m['userId'] == ref.read(clientProvider).userId &&
                          m['pinned'] == true,
                    );
                    final ordered = [
                      ...items.where(pinned),
                      ...items.where((item) => !pinned(item)),
                    ];
                    items = ordered;
                  }
                  return Column(
                    children: [
                      QChatSearchBar(
                        controller: search,
                        onChanged: (_) => setState(() {}),
                      ),
                      Expanded(
                        child: ColoredBox(
                          color: surface(c),
                          child: index == 0
                              ? chats(c, items)
                              : contacts(c, items),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget chats(BuildContext c, List items) => ListView(
    children: [
      for (final item in items) conversation(c, item),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 26),
        child: GestureDetector(
          onTap: invite,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                tr(c, 'invite'),
                style: const TextStyle(fontSize: 17, color: QChatColors.green),
              ),
              const SizedBox(width: 12),
              const QChatIcon('chevron', color: QChatColors.green, size: 20),
            ],
          ),
        ),
      ),
    ],
  );
  Widget conversation(BuildContext c, Map item) {
    final rows = item['messages'] as List;
    final members = (item['members'] as List).cast<dynamic>();
    final member = members.firstWhere(
      (m) => m['userId'] == ref.read(clientProvider).userId,
      orElse: () => null,
    );
    final last = rows.isEmpty ? null : rows.first;
    final date = DateTime.tryParse(last?['createdAt'] ?? '')?.toLocal();
    final now = DateTime.now();
    final time = date == null
        ? ''
        : date.year == now.year &&
              date.month == now.month &&
              date.day == now.day
        ? '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
        : '${date.day}/${date.month}';
    return TSwipeCell(
      key: ValueKey(item['id']),
      end: TSwipeCellPanel(
        children: [
          TSwipeCellAction(
            backgroundColor: const Color(0xff168fe5),
            label: tr(
              c,
              member?['markedUnread'] == true ? 'markRead' : 'markUnread',
            ),
            onPressed: (_) => conversationAction(
              item,
              member?['markedUnread'] == true ? 'read' : 'unread',
            ),
          ),
          TSwipeCellAction(
            backgroundColor: const Color(0xffff9c38),
            label: tr(c, 'hideChat'),
            onPressed: (_) => conversationAction(item, 'hide'),
          ),
          TSwipeCellAction(
            backgroundColor: const Color(0xfffa5151),
            label: tr(c, 'delete'),
            onPressed: (_) => conversationAction(item, 'delete'),
          ),
        ],
      ),
      child: QChatConversationTile(
        name: conversationName(item),
        avatar: item['kind'] == 'DIRECT'
            ? UserAvatar(
                members.firstWhere(
                  (m) => m['userId'] != ref.read(clientProvider).userId,
                  orElse: () => member,
                )?['user'],
              )
            : GroupAvatar(item, size: 48),
        preview: last == null
            ? ''
            : last['recalledAt'] != null
            ? tr(c, 'recalled')
            : last['text']?.toString().isNotEmpty == true
            ? last['text']
            : '[${last['kind']}]',
        time: time,
        unread: member?['markedUnread'] == true
            ? 1
            : ((item['sequence'] as int) -
                    ((member?['readSequence'] as int?) ?? 0))
                  .clamp(0, 999),
        onTap: () => c.push('/chat/${item['id']}'),
      ),
    );
  }

  Future<void> conversationAction(Map item, String action) async {
    if (action == 'delete' &&
        !await confirmAction(
          context,
          tr(context, 'delete'),
          tr(context, 'deleteChatNote'),
        )) {
      return;
    }
    try {
      final client = ref.read(clientProvider);
      final id = item['id'];
      if (action == 'delete') {
        await client.clearHistory(id, hide: true);
      } else if (action == 'read') {
        await client.post('/conversations/$id/read', {
          'sequence': item['sequence'],
        });
      } else {
        await client.dio.patch(
          '/conversations/$id/state',
          data: action == 'hide' ? {'hidden': true} : {'markedUnread': true},
        );
      }
      await client.local?.removeCache('/conversations');
      if (mounted) {
        setState(() => data = client.get('/conversations', cached: false));
      }
    } catch (_) {
      if (mounted) {
        await TDialog.show<void>(
          context,
          barrierDismissible: true,
          dialog: Builder(
            builder: (c) => TDialog(
              content: Text(tr(c, 'networkError')),
              actions: [
                TDialogAction(
                  child: Text(tr(c, 'confirm')),
                  onPressed: () => Navigator.pop(c),
                  role: TDialogActionRole.primary,
                  variant: TButtonVariant.text,
                ),
              ],
            ),
          ),
        );
      }
    }
  }

  Widget contacts(BuildContext c, List items) {
    items.sort(
      (a, b) => a['friend']['nickname'].toString().compareTo(
        b['friend']['nickname'].toString(),
      ),
    );
    final letters = items
        .map(
          (e) =>
              e['friend']['nickname'].toString().characters.first.toUpperCase(),
        )
        .toSet()
        .toList();
    return Stack(
      children: [
        ListView(
          children: [
            MenuRow(
              'newFriends',
              icon: 'addFriend',
              boxed: true,
              color: const Color(0xfffa9d3b),
              onTap: () => c.push('/friends'),
            ),
            MenuRow(
              'groups',
              icon: 'groups',
              boxed: true,
              color: QChatColors.green,
              onTap: () => c.push('/groups/new'),
            ),
            const MenuRow('tags', icon: 'tag', boxed: true),
            const MenuRow(
              'service',
              icon: 'service',
              boxed: true,
              color: Color(0xff0aaeea),
            ),
            for (final letter in letters) ...[
              Container(
                key: sectionKeys.putIfAbsent(letter, () => GlobalKey()),
                padding: const EdgeInsets.fromLTRB(16, 23, 16, 8),
                child: Text(
                  letter,
                  style: const TextStyle(
                    fontSize: 14,
                    color: QChatColors.muted,
                  ),
                ),
              ),
              for (final item in items.where(
                (e) => e['friend']['nickname']
                    .toString()
                    .toUpperCase()
                    .startsWith(letter),
              ))
                QChatListTile(
                  title: (item['remark'] ?? '').toString().isEmpty
                      ? item['friend']['nickname']
                      : item['remark'],
                  leading: UserAvatar(item['friend'], size: 42),
                  trailing: const SizedBox.shrink(),
                  onTap: () => c.push('/user/${item['friend']['id']}'),
                ),
            ],
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '${items.length} ${tr(c, 'friendsCount')}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: QChatColors.muted, fontSize: 17),
              ),
            ),
          ],
        ),
        if (letters.isNotEmpty)
          Positioned(
            right: 4,
            top: 255,
            child: Column(
              children: [
                for (final letter in letters)
                  GestureDetector(
                    onTap: () {
                      final target = sectionKeys[letter]?.currentContext;
                      if (target != null) {
                        Scrollable.ensureVisible(
                          target,
                          duration: const Duration(milliseconds: 200),
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(letter, style: const TextStyle(fontSize: 11)),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget discover(BuildContext c) => ListView(
    children: [
      MenuRow('moments', icon: 'moments', onTap: () => c.push('/moments')),
      sectionGap,
      const MenuRow('channels', icon: 'channels', color: Color(0xfff5a33a)),
      sectionGap,
      MenuRow('scan', icon: 'scan', onTap: () => c.push('/scan')),
      sectionGap,
      const MenuRow('stories', icon: 'stories', color: Color(0xffeeb714)),
      MenuRow(
        'search',
        icon: 'searchStar',
        color: const Color(0xffef6269),
        onTap: () => c.push('/search'),
      ),
      sectionGap,
      const MenuRow('nearby', icon: 'nearby'),
      sectionGap,
      const MenuRow('miniApps', icon: 'miniApps', color: Color(0xff7c70ec)),
      sectionGap,
      const MenuRow('out', icon: 'call', color: QChatColors.green),
    ],
  );
  Widget me(BuildContext c, Map u) => ListView(
    padding: EdgeInsets.zero,
    children: [
      Container(
        color: surface(c),
        padding: EdgeInsets.fromLTRB(
          28,
          60 + MediaQuery.paddingOf(c).top,
          20,
          32,
        ),
        child: GestureDetector(
          onTap: () async {
            await c.push('/profile');
            if (mounted) setState(load);
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(u, size: 64),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u['nickname'],
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      'QChat ID: ${u['qchatId']}',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xff888888),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => c.push('/profile'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: QChatColors.line),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '+ ${tr(c, 'status')}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: QChatColors.muted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  QChatIconButton(
                    'qr',
                    label: tr(c, 'qr'),
                    onTap: () => c.push('/qr'),
                    color: const Color(0xff65718e),
                  ),
                  const QChatIcon(
                    'chevron',
                    color: QChatColors.muted,
                    size: 18,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      sectionGap,
      const MenuRow('payments', icon: 'payments', color: QChatColors.green),
      sectionGap,
      MenuRow(
        'favorites',
        icon: 'favorites',
        color: const Color(0xffe8b933),
        onTap: () => c.push('/favorites'),
      ),
      MenuRow('moments', icon: 'image', onTap: () => c.push('/moments')),
      const MenuRow('stickers', icon: 'emoji', color: Color(0xffeeb714)),
      sectionGap,
      MenuRow('settings', icon: 'settings', onTap: () => c.push('/settings')),
    ],
  );
}
