import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/design_system/detail_page.dart';
import '../../core/design_system/media_widgets.dart';
import '../../core/localization/strings.dart';

class UserProfileScreen extends ConsumerStatefulWidget {
  const UserProfileScreen({super.key, this.id, this.qchatId});
  final String? id, qchatId;
  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  Map? user;
  bool friend = false, sent = false, busy = false, loading = true;
  String? error;
  StreamSubscription<void>? updates;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    load();
    updates = ref.read(clientProvider).changes.stream.listen((_) => load());
  }

  @override
  void dispose() {
    updates?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    final current = ++revision;
    try {
      final client = ref.read(clientProvider);
      Map? found;
      if (widget.id != null) {
        found = await client.get('/users/${widget.id}', cached: false);
      } else {
        final matches =
            await client.get(
                  '/users/search?q=${Uri.encodeQueryComponent(widget.qchatId ?? '')}',
                  cached: false,
                )
                as List;
        found = matches.isEmpty ? null : matches.first as Map;
      }
      final friends = await client.get('/friends', cached: false) as List;
      if (mounted && current == revision) {
        setState(() {
          user = found;
          friend =
              found != null &&
              friends.any((f) => f['friendId'] == found!['id']);
          error = found == null ? tr(context, 'userNotFound') : null;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted && current == revision) {
        setState(() {
          error = tr(context, 'networkError');
          loading = false;
        });
      }
    }
  }

  Future<void> act(String action) async {
    if (busy || user == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final client = ref.read(clientProvider);
      if (action == 'add' || action == 'addFriend') {
        await client.post('/friends/requests', {'recipientId': user!['id']});
        if (mounted) setState(() => sent = true);
      } else {
        final conversation = await client.post('/conversations', {
          'memberIds': [user!['id']],
        });
        if (!mounted) return;
        await context.push(
          action == 'messageUser'
              ? '/chat/${conversation['id']}'
              : '/call/${conversation['id']}?video=${action == 'videoCall'}',
        );
        if (mounted) await load();
      }
    } catch (_) {
      if (mounted) setState(() => error = tr(context, 'networkError'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget action(String label, String icon, {bool disabled = false}) =>
      Container(
        color: surface(context),
        width: double.infinity,
        child: TButton(
          variant: TButtonVariant.text,
          onPressed: busy || disabled ? null : () => act(label),
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(double.infinity, 56)),
            foregroundColor: WidgetStatePropertyAll(Color(0xff576b95)),
            textStyle: WidgetStatePropertyAll(
              TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          icon: QChatIcon(icon, size: 22, color: const Color(0xff576b95)),
          child: Text(tr(context, label)),
        ),
      );

  @override
  Widget build(BuildContext c) => DetailPage(
    whiteHeader: true,
    child: ListView(
      children: [
        if (loading) const Center(child: TLoading()),
        if (user != null) ...[
          Container(
            color: surface(c),
            padding: const EdgeInsets.fromLTRB(16, 26, 16, 32),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserAvatar(user!, size: 64),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user!['nickname'] ?? '',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'QChat ID: ${user!['qchatId'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 15,
                          color: QChatColors.muted,
                        ),
                      ),
                      if ((user!['bio'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          user!['bio'],
                          style: const TextStyle(color: QChatColors.muted),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          if (user!['id'] != ref.read(clientProvider).userId)
            if (friend) ...[
              action('messageUser', 'chats'),
              const SizedBox(height: 1),
              action('voiceCall', 'call'),
              const SizedBox(height: 1),
              action('videoCall', 'videoCall'),
            ] else
              action(
                sent ? 'friendRequestSent' : 'add',
                'contacts',
                disabled: sent,
              ),
        ],
        if (busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: TLoading()),
          ),
        if (error != null) TCell(title: Text(error!), arrow: true, onTap: load),
      ],
    ),
  );
}
