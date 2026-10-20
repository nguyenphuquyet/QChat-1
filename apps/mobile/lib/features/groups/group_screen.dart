import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/design_system/media_widgets.dart';
import '../../core/localization/strings.dart';

class GroupScreen extends ConsumerStatefulWidget {
  const GroupScreen({super.key});
  @override
  ConsumerState<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends ConsumerState<GroupScreen> {
  final name = TextEditingController();
  final selected = <String>{};
  late Future<dynamic> friends;
  String? error;
  @override
  void initState() {
    super.initState();
    friends = ref.read(clientProvider).get('/friends');
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> create() async {
    try {
      final c = await ref.read(clientProvider).post('/conversations', {
        'kind': 'GROUP',
        'title': name.text.trim(),
        'memberIds': selected.toList(),
      });
      if (mounted) context.go('/chat/${c['id']}');
    } catch (e) {
      if (mounted) setState(() => error = tr(context, 'networkError'));
    }
  }

  @override
  Widget build(BuildContext c) => QChatPage(
    title: tr(c, 'newGroup'),
    leading: QChatIconButton(
      'back',
      label: tr(c, 'back'),
      onTap: () => context.pop(),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: QChatTextInput(controller: name, hint: tr(c, 'groupName')),
        ),
        if (error != null) Text(error!),
        Expanded(
          child: FutureBuilder<dynamic>(
            future: friends,
            builder: (c, s) => s.hasError
                ? QChatError(
                    error: s.error!,
                    retry: () => setState(
                      () => friends = ref.read(clientProvider).get('/friends'),
                    ),
                  )
                : !s.hasData
                ? const QChatLoading()
                : ListView(
                    children: [
                      for (final f in s.data)
                        QChatListTile(
                          title: f['friend']['nickname'],
                          leading: UserAvatar(f['friend']),
                          trailing: Text(
                            selected.contains(f['friendId']) ? '✓' : '○',
                            style: const TextStyle(
                              color: QChatColors.green,
                              fontSize: 24,
                            ),
                          ),
                          onTap: () => setState(
                            () => selected.contains(f['friendId'])
                                ? selected.remove(f['friendId'])
                                : selected.add(f['friendId']),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: QChatButton(
            tr(c, 'newGroup'),
            onTap: selected.isEmpty ? null : create,
          ),
        ),
      ],
    ),
  );
}
