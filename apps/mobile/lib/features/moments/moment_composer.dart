import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import '../../app/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/localization/strings.dart';
import '../../core/network/media_upload.dart';

class MomentComposer extends ConsumerStatefulWidget {
  const MomentComposer({super.key});
  @override
  ConsumerState<MomentComposer> createState() => _MomentComposerState();
}

class _MomentComposerState extends ConsumerState<MomentComposer> {
  final text = TextEditingController();
  final files = <PlatformFile>[];
  final fileSizes = <PlatformFile, int>{};
  final uploaded = <PlatformFile, String>{};
  bool busy = false, picking = false, private = false;
  String? error;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> pick(bool video) async {
    setState(() {
      picking = true;
      error = null;
    });
    try {
      final selected = await pickMediaWithSource(context, video: video);
      if (!mounted || selected.isEmpty) return;
      for (final file in selected) {
        final size = await file.length() ?? 0;
        if (size > maxMediaBytes) throw StateError('mediaTooLarge');
        fileSizes[file] = size;
      }
      if (!mounted) return;
      if (files.length + selected.length > 9) {
        throw StateError('maxAttachments');
      }
      setState(() => files.addAll(selected));
    } catch (e) {
      if (mounted) {
        setState(
          () => error = tr(
            context,
            e is StateError ? e.message.toString() : 'networkError',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> post() async {
    if (busy || (text.text.trim().isEmpty && files.isEmpty)) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final client = ref.read(clientProvider);
      for (final file in files) {
        uploaded[file] ??= await uploadMedia(client, file);
      }
      await client.post('/moments', {
        'text': text.text.trim(),
        'privacy': private ? 'PRIVATE' : 'FRIENDS',
        'mediaIds': files.map((f) => uploaded[f]!).toList(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = tr(
            context,
            e is StateError ? e.message.toString() : 'networkError',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Hiện action sheet chọn quyền riêng tư
  void _pickPrivacy() {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    const itemHeight = 52.0;
    final bottomPadding = bottomInset > 0 ? bottomInset : 10.0;
    final totalHeight = itemHeight * 2 + 1 + bottomPadding;

    TPopup.show(
      context,
      options: TPopupOptions.bottom(
        height: totalHeight,
        useSafeArea: false,
        radius: 12,
        backgroundColor: surface(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _privacyOption(
              height: itemHeight,
              label: tr(context, 'friends'),
              selected: !private,
              onTap: () {
                Navigator.pop(context);
                setState(() => private = false);
              },
            ),
            Divider(
              height: 1,
              thickness: 0.5,
              color: ink(context).withValues(alpha: 0.08),
            ),
            _privacyOption(
              height: itemHeight,
              label: tr(context, 'private'),
              selected: private,
              onTap: () {
                Navigator.pop(context);
                setState(() => private = true);
              },
            ),
            SizedBox(height: bottomPadding),
          ],
        ),
      ),
    );
  }

  Widget _privacyOption({
    required double height,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: height,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected ? QChatColors.green : ink(context),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext c) => PopScope(
    canPop: !busy,
    child: QChatPage(
      title: tr(c, 'post'),
      leading: QChatIconButton(
        'back',
        label: tr(c, 'back'),
        onTap: () {
          if (!busy) Navigator.pop(c);
        },
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TInput(
            controller: text,
            maxLength: 5000,
            maxLines: 8,
            minLines: 3,
            enabled: !busy,
            hintText: tr(c, 'writeMoment'),
            borderless: false,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              QChatButton(
                tr(c, 'image'),
                secondary: true,
                onTap: busy || picking ? null : () => pick(false),
              ),
              QChatButton(
                tr(c, 'video'),
                secondary: true,
                onTap: busy || picking ? null : () => pick(true),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            tr(c, 'mediaLimit'),
            style: const TextStyle(fontSize: 12, color: QChatColors.muted),
          ),
          for (final file in files)
            QChatListTile(
              title: file.name,
              subtitle:
                  '${((fileSizes[file] ?? 0) / 1024 / 1024).toStringAsFixed(1)} MB',
              trailing: QChatIconButton(
                'close',
                label: tr(c, 'delete'),
                onTap: () {
                  if (!busy) {
                    setState(() {
                      files.remove(file);
                      uploaded.remove(file);
                    });
                  }
                },
              ),
            ),
          const SizedBox(height: 4),
          // Chọn quyền riêng tư bằng action sheet
          GestureDetector(
            onTap: busy ? null : _pickPrivacy,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const QChatIcon('lock', size: 20, color: QChatColors.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr(c, private ? 'private' : 'friends'),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const QChatIcon(
                    'chevron',
                    size: 18,
                    color: Color(0xffb8b8b8),
                  ),
                ],
              ),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                error!,
                style: const TextStyle(color: QChatColors.danger),
              ),
            ),
          QChatButton(
            tr(c, busy ? 'loading' : 'post'),
            onTap: busy || picking ? null : post,
          ),
        ],
      ),
    ),
  );
}
