import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/design_system/media_widgets.dart';
import '../../core/localization/strings.dart';
import '../../core/design_system/reference_widgets.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key, this.query});
  final String? query;
  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final search = TextEditingController();
  List<dynamic> users = [], requests = [];
  String? error;
  bool busy = false;
  Timer? debounce;
  late final Future<dynamic> me = ref.read(clientProvider).get('/users/me');
  @override
  void initState() {
    super.initState();
    search.text = widget.query ?? '';
    load();
    if (search.text.length >= 4) find();
  }

  @override
  void dispose() {
    search.dispose();
    debounce?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await ref.read(clientProvider).get('/friends/requests');
      if (mounted) setState(() => requests = r);
    } catch (e) {
      if (mounted) setState(() => error = tr(context, 'networkError'));
    }
  }

  Future<void> find() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await ref
          .read(clientProvider)
          .get('/users/search?q=${Uri.encodeComponent(search.text.trim())}');
      if (mounted) setState(() => users = r);
    } catch (e) {
      if (mounted) setState(() => error = tr(context, 'networkError'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> action(Future<dynamic> Function() work) async {
    try {
      await work();
      await load();
    } catch (e) {
      if (mounted) setState(() => error = tr(context, 'networkError'));
    }
  }

  @override
  Widget build(BuildContext c) => QChatPage(
    title: tr(c, 'addFriend'),
    background: surface(c),
    trailing: QChatIconButton(
      'more',
      label: tr(c, 'more'),
      onTap: () => c.push('/qr'),
    ),
    leading: QChatIconButton(
      'back',
      label: tr(c, 'back'),
      onTap: () => context.pop(),
    ),
    child: ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Theme(
            data: Theme.of(c).copyWith(
              extensions: [
                ...Theme.of(
                  c,
                ).extensions.values.where((e) => e is! TInputThemeData),
                TInputThemeData(
                  backgroundColor: Theme.of(c).brightness == Brightness.dark
                      ? surface(c)
                      : const Color(0xfff2f2f2),
                  borderRadius: 6,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  hintStyle: const TextStyle(
                    fontSize: 16,
                    color: Color(0xffb2b2b2),
                  ),
                ),
              ],
            ),
            child: TInput(
              controller: search,
              hintText: 'QChat ID',
              prefix: const QChatIcon(
                'search',
                color: QChatColors.muted,
                size: 20,
              ),
              borderless: true,
              onChanged: (value) {
                debounce?.cancel();
                if (value.trim().length >= 4) {
                  debounce = Timer(const Duration(milliseconds: 400), find);
                } else {
                  setState(() => users = []);
                }
              },
            ),
          ),
        ),
        if (busy) const QChatLoading(),
        if (users.isEmpty && search.text.isEmpty) ...[
          MenuRow(
            'scanFriend',
            icon: 'scan',
            subtitle: 'scanFriendNote',
            onTap: () => c.push('/scan'),
          ),
          const MenuRow(
            'mobileContacts',
            icon: 'mobile',
            color: QChatColors.green,
            subtitle: 'mobileContactsNote',
          ),
          const MenuRow(
            'radar',
            icon: 'radar',
            color: Color(0xff7c70ec),
            subtitle: 'radarNote',
          ),
          MenuRow(
            'invite',
            icon: 'mail',
            subtitle: 'inviteNote',
            onTap: () async {
              final u = await me;
              await Clipboard.setData(
                ClipboardData(text: 'QChat ID: ${u['qchatId']}'),
              );
              if (c.mounted) qchatSheet(c, [(tr(c, 'copied'), () {})]);
            },
          ),
          const MenuRow(
            'workContacts',
            icon: 'contacts',
            subtitle: 'workContactsNote',
          ),
          MenuRow(
            'privateGroup',
            icon: 'groups',
            color: QChatColors.green,
            subtitle: 'privateGroupNote',
            onTap: () => c.push('/groups/new'),
          ),
          const MenuRow('official', icon: 'official', subtitle: 'learnMore'),
          const MenuRow(
            'service',
            icon: 'service',
            color: Color(0xffed7361),
            subtitle: 'learnMore',
          ),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              error!,
              style: const TextStyle(color: QChatColors.danger),
            ),
          ),
        for (final u in users)
          QChatListTile(
            title: u['nickname'],
            subtitle: u['qchatId'],
            leading: UserAvatar(u),
            onTap: () => c.push('/user/${u['id']}'),
          ),
        const SizedBox(height: 24),
        for (final r in requests)
          QChatListTile(
            title: r['sender']['nickname'],
            subtitle: r['sender']['qchatId'],
            leading: UserAvatar(r['sender']),
            onTap: () => qchatSheet(c, [
              (
                tr(c, 'accept'),
                () => action(
                  () => ref
                      .read(clientProvider)
                      .dio
                      .patch(
                        '/friends/requests/${r['id']}',
                        data: {'accept': true},
                      ),
                ),
              ),
              (
                tr(c, 'reject'),
                () => action(
                  () => ref
                      .read(clientProvider)
                      .dio
                      .patch(
                        '/friends/requests/${r['id']}',
                        data: {'accept': false},
                      ),
                ),
              ),
            ]),
          ),
        if (search.text.isEmpty)
          FutureBuilder<dynamic>(
            future: me,
            builder: (c, s) => s.hasData
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Column(
                      children: [
                        QrImageView(
                          data: 'qchat://user/${s.data['qchatId']}',
                          size: 175,
                          backgroundColor: Colors.white,
                        ),
                        Text(
                          'QChat ID: ${s.data['qchatId']}',
                          style: const TextStyle(color: QChatColors.muted),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
      ],
    ),
  );
}
