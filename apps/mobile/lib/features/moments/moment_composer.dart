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
      final selected = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: video ? ['mp4', 'mov'] : imageExtensions,
      );
      if (!mounted) return;
      if (selected.any((f) => f.size > maxMediaBytes))
        throw StateError('mediaTooLarge');
      if (files.length + selected.length > 9)
        throw StateError('maxAttachments');
      setState(() => files.addAll(selected));
    } catch (e) {
      if (mounted)
        setState(
          () => error = tr(
            context,
            e is StateError ? e.message.toString() : 'networkError',
          ),
        );
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
      if (mounted)
        setState(
          () => error = tr(
            context,
            e is StateError ? e.message.toString() : 'networkError',
          ),
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

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
          TextField(
            controller: text,
            maxLength: 5000,
            maxLines: 5,
            enabled: !busy,
            decoration: InputDecoration(hintText: tr(c, 'writeMoment')),
          ),
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
          Text(tr(c, 'mediaLimit')),
          for (final file in files)
            QChatListTile(
              title: file.name,
              subtitle: '${(file.size / 1024 / 1024).toStringAsFixed(1)} MB',
              trailing: QChatIconButton(
                'close',
                label: tr(c, 'delete'),
                onTap: () {
                  if (!busy)
                    setState(() {
                      files.remove(file);
                      uploaded.remove(file);
                    });
                },
              ),
            ),
          SwitchListTile(
            title: Text(tr(c, 'private')),
            value: private,
            onChanged: busy ? null : (v) => setState(() => private = v),
          ),
          if (error != null)
            Text(error!, style: const TextStyle(color: QChatColors.danger)),
          QChatButton(
            tr(c, busy ? 'loading' : 'post'),
            onTap: busy || picking ? null : post,
          ),
        ],
      ),
    ),
  );
}
