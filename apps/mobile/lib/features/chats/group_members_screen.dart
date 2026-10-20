import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import '../../app/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/design_system/detail_page.dart';
import '../../core/design_system/dialogs.dart';
import '../../core/design_system/media_widgets.dart';
import '../../core/localization/strings.dart';

class GroupMembersScreen extends ConsumerStatefulWidget {
  const GroupMembersScreen({
    super.key,
    required this.conversationId,
    this.initialConversation,
    this.onUpdated,
  });

  final String conversationId;
  final Map<String, dynamic>? initialConversation;
  final VoidCallback? onUpdated;

  @override
  ConsumerState<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends ConsumerState<GroupMembersScreen> {
  Map<String, dynamic>? conversation;
  bool loading = true;
  String? error;
  final searchController = TextEditingController();
  String query = '';
  StreamSubscription<void>? updates;

  @override
  void initState() {
    super.initState();
    conversation = widget.initialConversation;
    load();
    updates = ref.read(clientProvider).changes.stream.listen((_) {
      if (mounted) load();
    });
  }

  @override
  void dispose() {
    updates?.cancel();
    searchController.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final client = ref.read(clientProvider);
      final data = await client.get('/conversations/${widget.conversationId}', cached: false);
      if (mounted) {
        setState(() {
          conversation = Map<String, dynamic>.from(data);
          loading = false;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          if (conversation == null) {
            error = tr(context, 'networkError');
          }
        });
      }
    }
  }

  Future<void> addMember() async {
    final client = ref.read(clientProvider);
    try {
      final friends = await client.get('/friends', cached: false) as List;
      final members = (conversation?['members'] as List? ?? []);
      final ids = members.map((m) => m['userId']).toSet();
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
      await client.post('/conversations/${widget.conversationId}/members', {
        'userId': chosen,
      });
      await load();
      widget.onUpdated?.call();
    } catch (_) {
      if (mounted) {
        setState(() => error = tr(context, 'networkError'));
      }
    }
  }

  Future<void> removeMember(Map<String, dynamic> member) async {
    final nickname = member['user']?['nickname'] ?? '';
    final confirmed = await confirmAction(
      context,
      tr(context, 'removeMember'),
      '${tr(context, 'removeMemberNote')} ($nickname)',
    );
    if (!confirmed) return;
    try {
      final client = ref.read(clientProvider);
      await client.dio.delete(
        '/conversations/${widget.conversationId}/members/${member['userId']}',
      );
      await load();
      widget.onUpdated?.call();
    } catch (_) {
      if (mounted) setState(() => error = tr(context, 'networkError'));
    }
  }

  @override
  Widget build(BuildContext c) {
    final client = ref.read(clientProvider);
    final members = (conversation?['members'] as List? ?? [])
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final own = members.where((m) => m['userId'] == client.userId).firstOrNull;
    final canManage = ['OWNER', 'ADMIN'].contains(own?['role']);

    final filtered = members.where((m) {
      if (query.trim().isEmpty) return true;
      final nick = (m['user']?['nickname'] ?? '').toString().toLowerCase();
      return nick.contains(query.trim().toLowerCase());
    }).toList();

    final admins = filtered
        .where((m) => ['OWNER', 'ADMIN'].contains(m['role']))
        .toList();

    return DefaultTabController(
      length: 2,
      child: DetailPage(
        title: tr(c, 'groupMembers'),
        child: Column(
          children: [
            Container(
              color: surface(c),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: Theme.of(c).brightness == Brightness.dark
                      ? const Color(0xff2c2c2c)
                      : const Color(0xfff0f0f0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  controller: searchController,
                  onChanged: (v) => setState(() => query = v),
                  decoration: InputDecoration(
                    hintText: tr(c, 'searchMembers'),
                    hintStyle: const TextStyle(fontSize: 14, color: QChatColors.muted),
                    prefixIcon: const Icon(Icons.search, size: 20, color: QChatColors.muted),
                    suffixIcon: query.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              searchController.clear();
                              setState(() => query = '');
                            },
                            child: const Icon(Icons.close, size: 18, color: QChatColors.muted),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ),
            Container(
              color: surface(c),
              child: TabBar(
                labelColor: QChatColors.primary,
                unselectedLabelColor: QChatColors.muted,
                indicatorColor: QChatColors.primary,
                indicatorWeight: 2.5,
                tabs: [
                  Tab(text: '${tr(c, 'allMembers')} (${members.length})'),
                  Tab(text: '${tr(c, 'admins')} (${members.where((m) => ['OWNER', 'ADMIN'].contains(m['role'])).length})'),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 0.5),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  error!,
                  style: const TextStyle(color: QChatColors.danger, fontSize: 13),
                ),
              ),
            Expanded(
              child: loading && conversation == null
                  ? const Center(child: TLoading())
                  : TabBarView(
                      children: [
                        _buildMemberList(
                          c,
                          filtered,
                          canManage: canManage,
                          currentUserId: client.userId,
                          showAddButton: canManage && query.isEmpty,
                        ),
                        _buildMemberList(
                          c,
                          admins,
                          canManage: canManage,
                          currentUserId: client.userId,
                          showAddButton: false,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberList(
    BuildContext c,
    List<Map<String, dynamic>> list, {
    required bool canManage,
    required String? currentUserId,
    required bool showAddButton,
  }) {
    if (list.isEmpty && !showAddButton) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            tr(c, 'emptyContacts'),
            style: const TextStyle(color: QChatColors.muted),
          ),
        ),
      );
    }

    return ListView(
      children: [
        if (showAddButton)
          Container(
            color: surface(c),
            child: TCell(
              image: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: QChatColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: TIcon(TIcons.add, color: QChatColors.primary, size: 22),
                ),
              ),
              title: Text(
                tr(c, 'add'),
                style: const TextStyle(
                  color: QChatColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: addMember,
            ),
          ),
        for (final m in list)
          Container(
            color: surface(c),
            child: TCell(
              image: UserAvatar(m['user'], size: 42),
              title: Text(
                m['user']?['nickname'] ?? '',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              note: _buildRoleBadge(c, m['role']),
              trailing: canManage &&
                      m['role'] != 'OWNER' &&
                      m['userId'] != currentUserId
                  ? IconButton(
                      icon: const Icon(Icons.remove_circle_outline,
                          color: QChatColors.danger, size: 20),
                      onPressed: () => removeMember(m),
                    )
                  : null,
              onTap: () => c.push('/user/${m['userId']}'),
            ),
          ),
      ],
    );
  }

  Widget? _buildRoleBadge(BuildContext c, String? role) {
    if (role == 'OWNER') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xfffff7e6),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xffffd591), width: 0.8),
        ),
        child: Text(
          tr(c, 'groupOwner'),
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xffd46b08),
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    if (role == 'ADMIN') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xffe6f7ff),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xff91d5ff), width: 0.8),
        ),
        child: Text(
          tr(c, 'groupAdmin'),
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xff096dd9),
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    return null;
  }
}
