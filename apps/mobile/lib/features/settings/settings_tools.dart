import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/design_system/media_widgets.dart';
import '../../core/design_system/reference_widgets.dart';
import '../../core/design_system/dialogs.dart';
import '../../core/localization/strings.dart';

class SettingsTools extends ConsumerStatefulWidget {
  const SettingsTools({super.key, required this.kind});
  final String kind;
  @override
  ConsumerState<SettingsTools> createState() => _SettingsToolsState();
}

class _SettingsToolsState extends ConsumerState<SettingsTools> {
  late Future<dynamic> data;
  bool busy = false;
  String? feedback;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    final client = ref.read(clientProvider);
    data = switch (widget.kind) {
      'storage' =>
        client.local?.cacheStats() ??
            Future.value((bytes: 0, entries: 0, pending: 0)),
      'conversations' => client.get('/conversations', cached: false),
      'calls' => client.get('/calls', cached: false),
      'blocks' => client.get('/blocks', cached: false),
      _ => client.get('/users/me', cached: false),
    };
  }

  Future<void> action(Future<void> Function() work) async {
    if (busy) return;
    setState(() {
      busy = true;
      feedback = null;
    });
    try {
      await work();
      if (mounted) {
        setState(() {
          feedback = tr(context, 'saved');
          load();
        });
      }
    } catch (_) {
      if (mounted) setState(() => feedback = tr(context, 'operationFailed'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> changePassword() async {
    final current = await editText(
      context,
      tr(context, 'currentPassword'),
      secret: true,
      maxLength: 128,
    );
    if (current == null || current.isEmpty || !mounted) return;
    final next = await editText(
      context,
      tr(context, 'newPassword'),
      secret: true,
      maxLength: 128,
    );
    if (next == null || !mounted) return;
    if (next.length < 12) {
      setState(() => feedback = tr(context, 'passwordMinimum'));
      return;
    }
    final repeated = await editText(
      context,
      tr(context, 'repeatPassword'),
      secret: true,
      maxLength: 128,
    );
    if (repeated == null || !mounted) return;
    if (repeated != next) {
      setState(() => feedback = tr(context, 'passwordMismatch'));
      return;
    }
    await action(() async {
      final client = ref.read(clientProvider);
      await client.post('/users/me/password', {
        'currentPassword': current,
        'password': next,
      });
      await client.clearSession();
      if (mounted) context.go('/login');
    });
  }

  Future<void> exportData() => action(() async {
    final result = await ref
        .read(clientProvider)
        .get('/users/me/export', cached: false);
    await FilePicker.saveFile(
      fileName: 'qchat-export.json',
      mimeType: 'application/json',
      bytes: Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(result)),
      ),
    );
  });
  Widget row(String label, VoidCallback tap, {String? value}) => MenuRow(
    label,
    value: value,
    onTap: () {
      if (!busy) tap();
    },
  );
  Widget note(String key) =>
      Padding(padding: const EdgeInsets.all(16), child: Text(tr(context, key)));
  @override
  Widget build(BuildContext c) {
    final prefs = ref.watch(preferencesProvider);
    return QChatPage(
      title: tr(c, widget.kind),
      leading: QChatIconButton(
        'back',
        label: tr(c, 'back'),
        onTap: () => c.pop(),
      ),
      child: FutureBuilder<dynamic>(
        future: data,
        builder: (c, s) {
          if (s.hasError) {
            return QChatError(error: s.error!, retry: () => setState(load));
          }
          if (!s.hasData) return const QChatLoading();
          final client = ref.read(clientProvider);
          final widgets = <Widget>[];
          switch (widget.kind) {
            case 'security':
              widgets.addAll([
                QChatListTile(title: 'QChat ID', subtitle: s.data['qchatId']),
                QChatListTile(title: 'Email', subtitle: s.data['email']),
                row('changePassword', changePassword),
                note('passwordLogoutNote'),
                row('sessions', () => c.push('/sessions')),
              ]);
            case 'permissions':
              widgets.addAll([
                row('profile', () => c.push('/profile')),
                row('exportData', exportData),
                note('exportDataNote'),
                note('devicePermissionsNote'),
                row('scan', () => c.push('/scan')),
                row(
                  'friendPermissions',
                  () => c.push('/settings/friendPermissions'),
                ),
              ]);
            case 'storage':
              final stats = s.data as ({int bytes, int entries, int pending});
              widgets.addAll([
                QChatListTile(
                  title: tr(c, 'cachedContent'),
                  subtitle:
                      '${(stats.bytes / 1024 / 1024).toStringAsFixed(2)} MB · ${stats.entries}',
                ),
                QChatListTile(
                  title: tr(c, 'pendingMessages'),
                  subtitle: '${stats.pending}',
                ),
                note('clearCacheNote'),
                row('clearCache', () async {
                  if (await confirmAction(
                        c,
                        tr(c, 'clearCache'),
                        tr(c, 'clearCacheNote'),
                      ) &&
                      mounted) {
                    await action(() async {
                      await client.local?.clearReadCache();
                      PaintingBinding.instance.imageCache.clear();
                      MediaCache.clear();
                    });
                  }
                }),
              ]);
            case 'calls':
              widgets.addAll([
                row(
                  'muteOnJoin',
                  () => action(
                    () => ref
                        .read(preferencesProvider.notifier)
                        .muteOnJoin(!prefs.startMuted),
                  ),
                  value: prefs.startMuted
                      ? tr(c, 'enabled')
                      : tr(c, 'disabled'),
                ),
                note('callPermissionNote'),
                const SectionLabel('callHistory'),
                if ((s.data as List).isEmpty) QChatEmptyState(tr(c, 'noItems')),
                for (final call in s.data as List)
                  QChatListTile(
                    title: tr(
                      c,
                      call['kind'] == 'VIDEO' ? 'videoCall' : 'call',
                    ),
                    subtitle: '${call['createdAt']} · ${call['status']}',
                    onTap: () => c.push(
                      '/call/${call['conversationId']}?video=${call['kind'] == 'VIDEO'}',
                    ),
                  ),
              ]);
            case 'conversations':
              widgets.addAll([
                if ((s.data as List).isEmpty) QChatEmptyState(tr(c, 'noItems')),
                for (final chat in s.data as List) conversation(c, chat),
              ]);
            case 'blocks':
              widgets.addAll([
                if ((s.data as List).isEmpty) QChatEmptyState(tr(c, 'noItems')),
                for (final block in s.data as List)
                  QChatListTile(
                    title: block['target']?['nickname'] ?? block['targetId'],
                    subtitle: tr(c, 'unblock'),
                    onTap: () async {
                      if (await confirmAction(
                            c,
                            tr(c, 'unblock'),
                            tr(c, 'unblockNote'),
                          ) &&
                          mounted) {
                        await action(() async {
                          await client.dio.delete(
                            '/blocks/${block['targetId']}',
                          );
                        });
                      }
                    },
                  ),
              ]);
          }
          return ListView(
            children: [
              if (busy) const QChatLoading(),
              if (feedback != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(feedback!),
                ),
              ...widgets,
            ],
          );
        },
      ),
    );
  }

  Widget conversation(BuildContext c, Map chat) {
    final client = ref.read(clientProvider);
    final members = chat['members'] as List;
    final state = members.firstWhere((m) => m['userId'] == client.userId);
    final title = chat['kind'] == 'GROUP'
        ? chat['title'] as String
        : members
              .where((m) => m['userId'] != client.userId)
              .map((m) => m['user']['nickname'])
              .join(', ');
    Future<void> toggle(String field) => action(() async {
      await client.dio.patch(
        '/conversations/${chat['id']}/state',
        data: {field: state[field] != true},
      );
      client.changes.add(null);
    });
    return QChatListTile(
      title: title,
      subtitle:
          '${tr(c, 'pin')}: ${state['pinned'] == true ? '✓' : '—'} · ${tr(c, 'mute')}: ${state['muted'] == true ? '✓' : '—'}',
      onTap: () => qchatSheet(c, [
        (tr(c, 'openChat'), () => c.push('/chat/${chat['id']}')),
        (tr(c, 'pin'), () => toggle('pinned')),
        (tr(c, 'mute'), () => toggle('muted')),
      ]),
    );
  }
}
