import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/design_system/dialogs.dart';
import '../../core/design_system/detail_page.dart';
import '../../core/design_system/media_widgets.dart';
import '../../core/localization/strings.dart';
import '../../core/network/media_upload.dart';
import 'group_members_screen.dart';

class ChatDetailsScreen extends ConsumerStatefulWidget {
  const ChatDetailsScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<ChatDetailsScreen> createState() => _ChatDetailsScreenState();
}

class _ChatDetailsScreenState extends ConsumerState<ChatDetailsScreen> {
  Map? conversation;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await ref
          .read(clientProvider)
          .get('/conversations/${widget.id}', cached: false);
      if (mounted) {
        setState(() {
          conversation = data;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = tr(context, 'networkError'));
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => error = tr(context, 'networkError'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> background() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const TIcon(TIcons.image, size: 24, color: QChatColors.primary),
                title: Text(tr(c, 'selectWallpaper')),
                onTap: () async {
                  Navigator.pop(c);
                  final file = await pickImageWithSource(context);
                  if (file == null) return;
                  final bytes = await file.readAsBytes();
                  if (bytes.isNotEmpty) {
                    final base64Str = base64Encode(bytes);
                    final client = ref.read(clientProvider);
                    await client.local?.removeCache('chatBackground:${widget.id}');
                    await client.local?.cache('chatBackgroundImage:${widget.id}', base64Str);
                    client.changes.add(null);
                    if (mounted) setState(() {});
                  }
                },
              ),
              ListTile(
                leading: const TIcon(TIcons.close, size: 24, color: QChatColors.danger),
                title: Text(tr(c, 'clearWallpaper')),
                onTap: () async {
                  Navigator.pop(c);
                  final client = ref.read(clientProvider);
                  await client.local?.removeCache('chatBackgroundImage:${widget.id}');
                  await client.local?.removeCache('chatBackground:${widget.id}');
                  client.changes.add(null);
                  if (mounted) setState(() {});
                },
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final value in [
                      0xffededed,
                      0xffe4eee5,
                      0xffe5edf5,
                      0xfff5e8e1,
                    ])
                      GestureDetector(
                        onTap: () async {
                          Navigator.pop(c);
                          final client = ref.read(clientProvider);
                          await client.local?.removeCache('chatBackgroundImage:${widget.id}');
                          await client.local?.cache('chatBackground:${widget.id}', value);
                          client.changes.add(null);
                          if (mounted) setState(() {});
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Color(value),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.black12,
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: Center(
                  child: Text(
                    tr(c, 'cancel'),
                    style: const TextStyle(color: QChatColors.muted),
                  ),
                ),
                onTap: () => Navigator.pop(c),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> clearHistory() async {
    if (!await confirmAction(
      context,
      tr(context, 'clearHistory'),
      tr(context, 'clearHistoryNote'),
    )) {
      return;
    }
    await run(() async {
      final client = ref.read(clientProvider);
      await client.clearHistory(widget.id);
      client.changes.add(null);
    });
  }

  Future<void> report() async {
    final reason = await editText(
      context,
      tr(context, 'report'),
      maxLength: 2000,
      lines: 4,
    );
    if (reason == null || reason.trim().isEmpty) return;
    await run(() async {
      await ref.read(clientProvider).post('/reports', {
        'targetId': widget.id,
        'reason': reason,
      });
      if (mounted) {
        await TDialog.show<void>(
          context,
          barrierDismissible: true,
          dialog: Builder(
            builder: (c) => TDialog(
              content: Text(tr(c, 'reportSent')),
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
    });
  }

  Future<void> addMember() async {
    await run(() async {
      final client = ref.read(clientProvider);
      final friends = await client.get('/friends', cached: false) as List;
      final ids = (conversation!['members'] as List)
          .map((m) => m['userId'])
          .toSet();
      final available = friends
          .where((f) => !ids.contains(f['friendId']))
          .toList();
      if (!mounted) return;
      final chosen = await TDialog.show<String>(
        context,
        barrierDismissible: true,
        dialog: Builder(
          builder: (c) => TDialog(
            title: Text(tr(c, 'add')),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: available.isEmpty
                  ? Center(child: Text(tr(c, 'emptyContacts')))
                  : ListView(
                      children: [
                        for (final f in available)
                          TCell(
                            title: Text(f['friend']['nickname']),
                            image: UserAvatar(f['friend'], size: 42),
                            onTap: () =>
                                Navigator.pop(c, f['friendId'] as String),
                          ),
                      ],
                    ),
            ),
            actions: [
              TDialogAction(
                child: Text(tr(c, 'cancel')),
                onPressed: () => Navigator.pop(c),
                variant: TButtonVariant.text,
              ),
            ],
          ),
        ),
      );
      if (chosen == null) return;
      if (conversation!['kind'] == 'GROUP') {
        await client.post('/conversations/${widget.id}/members', {
          'userId': chosen,
        });
        await load();
      } else {
        final created = await client.post('/conversations', {
          'kind': 'GROUP',
          'title': conversation!['members']
              .map((m) => m['user']['nickname'])
              .join(', '),
          'memberIds': [...ids.where((id) => id != client.userId), chosen],
        });
        if (mounted) context.go('/chat/${created['id']}');
      }
    });
  }

  Future<void> dissolve() async {
    if (!await confirmAction(
      context,
      tr(context, 'dissolveGroup'),
      tr(context, 'dissolveGroupNote'),
    )) {
      return;
    }
    await run(() async {
      final client = ref.read(clientProvider);
      await client.dio.delete('/conversations/${widget.id}');
      await client.local?.removeCache('/conversations');
      await client.local?.removeCache('/conversations/${widget.id}');
      await client.local?.removeCache('messages:${widget.id}');
      client.confirmed.removeWhere((_, m) => m['conversationId'] == widget.id);
      client.changes.add(null);
      if (mounted) context.go('/home');
    });
  }

  Future<void> changeGroupName() async {
    final current = conversation?['title']?.toString() ?? '';
    final name = await editText(
      context,
      tr(context, 'changeGroupName'),
      initial: current,
      maxLength: 100,
    );
    if (name == null || name.trim().isEmpty || name.trim() == current) return;
    await run(() async {
      final client = ref.read(clientProvider);
      await client.dio.patch(
        '/conversations/${widget.id}',
        data: {'title': name.trim()},
      );
      await load();
      client.changes.add(null);
    });
  }

  Future<void> changeGroupAvatar() async {
    final file = await pickImageWithSource(context);
    if (file == null) return;
    await run(() async {
      final client = ref.read(clientProvider);
      final id = await uploadMedia(client, file);
      final currentAnn = conversation?['announcement']?.toString() ?? '';
      Map<String, dynamic> annMap = {};
      if (currentAnn.startsWith('{')) {
        try {
          annMap = Map<String, dynamic>.from(jsonDecode(currentAnn));
        } catch (_) {}
      }
      annMap['avatarId'] = id;
      await client.dio.patch(
        '/conversations/${widget.id}',
        data: {'announcement': jsonEncode(annMap)},
      );
      await load();
      client.changes.add(null);
    });
  }

  Future<void> showMembers() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => GroupMembersScreen(
        conversationId: widget.id,
        initialConversation: conversation != null
            ? Map<String, dynamic>.from(conversation!)
            : null,
        onUpdated: load,
      ),
    ),
  );
  @override
  Widget build(BuildContext c) {
    final client = ref.read(clientProvider);
    final members = conversation?['members'] as List? ?? [];
    final own = members.where((m) => m['userId'] == client.userId).firstOrNull;
    final shown = conversation?['kind'] == 'DIRECT'
        ? members.where((m) => m['userId'] != client.userId)
        : members;
    return DetailPage(
      title: tr(c, 'chatDetails'),
      child: ListView(
        children: [
          if (error != null) TCell(title: Text(error!), onTap: load),
          if (conversation == null && error == null)
            const Center(child: TLoading()),
          if (conversation != null) ...[
            if (conversation!['kind'] == 'GROUP') ...[
              Container(
                color: surface(c),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        GroupAvatar(conversation!, size: 58),
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: GestureDetector(
                            onTap: busy ? null : changeGroupAvatar,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: QChatColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(color: surface(c), width: 1.5),
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: GestureDetector(
                        onTap: busy ? null : changeGroupName,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              conversation?['title'] ?? tr(c, 'group'),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${members.length} ${tr(c, 'groupMembers').toLowerCase()}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: QChatColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20, color: QChatColors.muted),
                      onPressed: busy ? null : changeGroupName,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 9),
            ],
            Container(
              color: surface(c),
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final member in shown)
                    SizedBox(
                      width: 52,
                      child: Column(
                        children: [
                          UserAvatar(member['user'], size: 50),
                          const SizedBox(height: 6),
                          Text(
                            member['user']['nickname'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: QChatColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (conversation!['kind'] == 'DIRECT' ||
                      ['OWNER', 'ADMIN'].contains(own?['role']))
                    SizedBox(
                      width: 52,
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: busy ? null : addMember,
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Theme.of(c).brightness == Brightness.dark
                                      ? const Color(0xff444444)
                                      : const Color(0xffdcdcdc),
                                  width: 1.2,
                                ),
                              ),
                              child: const Center(
                                child: TIcon(
                                  TIcons.add,
                                  color: QChatColors.muted,
                                  size: 26,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 9),
            if (conversation!['kind'] == 'GROUP') ...[
              TCell(
                title: Text(tr(c, 'groupMembers')),
                note: Text('${members.length}'),
                arrow: true,
                onTap: showMembers,
              ),
              const SizedBox(height: 9),
              TCell(
                title: Text(tr(c, 'groupName')),
                note: Text(conversation?['title'] ?? ''),
                arrow: true,
                onTap: busy ? null : changeGroupName,
              ),
              const SizedBox(height: 9),
              TCell(
                title: Text(tr(c, 'groupAvatar')),
                arrow: true,
                onTap: busy ? null : changeGroupAvatar,
              ),
              const SizedBox(height: 9),
            ],
            TCell(
              title: Text(tr(c, 'searchHistory')),
              arrow: true,
              onTap: () => Navigator.of(c).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChatHistoryScreen(id: widget.id),
                ),
              ),
            ),
            const SizedBox(height: 9),
            TCell(
              title: Text(tr(c, 'pinChat')),
              trailing: TSwitch(
                value: own?['pinned'] == true,
                loading: busy,
                onChanged: (value) => run(() async {
                  await client.dio.patch(
                    '/conversations/${widget.id}/state',
                    data: {'pinned': value},
                  );
                  await load();
                  await client.local?.removeCache('/conversations');
                  client.changes.add(null);
                }),
              ),
            ),
            const SizedBox(height: 9),
            TCell(
              title: Text(tr(c, 'chatBackground')),
              arrow: true,
              onTap: busy ? null : () => run(background),
            ),
            const SizedBox(height: 9),
            TCell(
              title: Text(tr(c, 'clearHistory')),
              onTap: busy ? null : clearHistory,
            ),
            const SizedBox(height: 9),
            TCell(
              title: Text(tr(c, 'report')),
              arrow: true,
              onTap: busy ? null : report,
            ),
            if (conversation!['kind'] == 'GROUP' &&
                own?['role'] == 'OWNER') ...[
              const SizedBox(height: 9),
              TCell(
                title: Text(
                  tr(c, 'dissolveGroup'),
                  style: const TextStyle(color: QChatColors.danger),
                ),
                onTap: busy ? null : dissolve,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class ChatHistoryScreen extends ConsumerStatefulWidget {
  const ChatHistoryScreen({super.key, required this.id, this.query = ''});
  final String id;
  final String query;
  @override
  ConsumerState<ChatHistoryScreen> createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends ConsumerState<ChatHistoryScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.query.isNotEmpty) search(widget.query);
  }

  List rows = [];
  String? error;
  bool loading = false;
  int request = 0;
  Future<void> search(String query) async {
    final current = ++request;
    if (query.trim().isEmpty) {
      setState(() {
        rows = [];
        loading = false;
        error = null;
      });
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final found = await ref
          .read(clientProvider)
          .get(
            '/conversations/${widget.id}/messages?q=${Uri.encodeQueryComponent(query.trim())}',
            cached: false,
          );
      if (mounted && current == request) setState(() => rows = found);
    } catch (_) {
      if (mounted && current == request) {
        setState(() => error = tr(context, 'networkError'));
      }
    } finally {
      if (mounted && current == request) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext c) => DetailPage(
    title: tr(c, 'searchHistory'),
    child: Column(
      children: [
        TSearchBar(
          initialValue: widget.query,
          hintText: tr(c, 'searchHistory'),
          autofocus: true,
          onChanged: search,
          onSubmitted: search,
        ),
        if (loading) const Center(child: TLoading()),
        if (error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
        Expanded(
          child: ListView(
            children: [
              for (final row in rows)
                TCell(
                  image: UserAvatar(row['sender'] ?? {}, size: 42),
                  title: Text(row['text'] ?? ''),
                  subtitle: Text(row['sender']?['nickname'] ?? ''),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
