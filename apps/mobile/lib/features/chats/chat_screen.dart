import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../core/design_system/dialogs.dart';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../../app/providers.dart';
import '../../core/design_system/components.dart';
import '../../core/localization/strings.dart';
import 'message_status.dart';
import 'chat_composer.dart';
import 'chat_details_screen.dart';
import '../../core/design_system/media_widgets.dart';
import '../../core/design_system/qchat_animations.dart';
import '../../core/design_system/reference_widgets.dart';
import '../../core/network/media_upload.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final input = TextEditingController(), scroll = ScrollController();
  List<Map<String, dynamic>> messages = [];
  final selected = <String>{};
  bool selecting = false;
  StreamSubscription<void>? updates;
  StreamSubscription<void>? messageUpdates;
  List<dynamic> members = [];
  int readSequence = 0;
  String title = 'QChat';
  String? error, reply;
  bool loading = true, emoji = false, uploading = false;
  bool attachments = false, voice = false;
  String myName = 'Q';
  Color? chatBackground;
  ImageProvider? chatBackgroundImage;
  final inputFocus = FocusNode();
  double keyboardHeight = 0;
  Timer? panelTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    inputFocus.addListener(() {
      if (mounted) setState(() {});
      settlePanels();
    });
    scroll.addListener(() {
      if (scroll.hasClients &&
          scroll.position.pixels < 20 &&
          messages.any((m) => (m['sequence'] as int? ?? 0) > readSequence)) {
        load();
      }
    });
    load();
    updates = ref.read(clientProvider).changes.stream.listen((_) {
      if (mounted) load();
    });
    messageUpdates = ref.read(clientProvider).messageChanges.stream.listen((_) {
      if (!mounted) return;
      final nearEnd = !scroll.hasClients || scroll.position.pixels < 100;
      final previousCount = messages.length;
      setState(() {
        messages = ref
            .read(clientProvider)
            .visibleMessages(widget.id, messages);
        loading = false;
      });
      if (nearEnd ||
          (messages.length > previousCount &&
              messages.last['pending'] == true)) {
        scrollToEnd();
      }
    });
  }

  @override
  void dispose() {
    updates?.cancel();
    messageUpdates?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    panelTimer?.cancel();
    inputFocus.dispose();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  bool fetching = false;
  bool reload = false;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load();
  }

  /// Chạy mỗi khung hình khi bàn phím trượt: giữ danh sách bám đáy để không bị
  /// lò xo (bouncing) của iOS kéo nẩy lại khi viewport đổi kích thước.
  @override
  void didChangeMetrics() {
    if (!mounted) return;
    if (scroll.hasClients && scroll.position.pixels < 100) scrollToEnd();
    settlePanels();
  }

  /// Khi người dùng bấm lại vào ô nhập lúc panel đang mở, đợi bàn phím lên hẳn
  /// rồi mới đóng panel -> chiều cao vùng đáy luôn liên tục, không nhảy.
  void settlePanels() {
    panelTimer?.cancel();
    if (!(emoji || attachments) || !inputFocus.hasFocus) return;
    panelTimer = Timer(const Duration(milliseconds: 280), () {
      if (!mounted || !inputFocus.hasFocus) return;
      setState(() {
        emoji = false;
        attachments = false;
      });
    });
  }

  void stickyState(VoidCallback change) {
    final stick = !scroll.hasClients || scroll.position.pixels < 100;
    setState(change);
    if (stick) scrollToEnd();
  }

  void toggleVoice() {
    stickyState(() {
      voice = !voice;
      emoji = false;
      attachments = false;
    });
    voice ? inputFocus.unfocus() : inputFocus.requestFocus();
  }

  void toggleEmoji() {
    if (emoji) {
      inputFocus.requestFocus();
      return;
    }
    stickyState(() {
      emoji = true;
      attachments = false;
      voice = false;
    });
    inputFocus.unfocus();
  }

  void togglePlus() {
    if (attachments) {
      inputFocus.requestFocus();
      return;
    }
    stickyState(() {
      attachments = true;
      emoji = false;
      voice = false;
    });
    inputFocus.unfocus();
  }

  void dismissInput() {
    inputFocus.unfocus();
    if (emoji || attachments) {
      stickyState(() {
        emoji = false;
        attachments = false;
      });
    }
  }

  void insertEmoji(String e) {
    final text = input.text;
    final sel = input.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    input.value = TextEditingValue(
      text: text.replaceRange(start, end, e),
      selection: TextSelection.collapsed(offset: start + e.length),
    );
    setState(() {});
  }

  static const emojis = [
    '😀',
    '😊',
    '😂',
    '🥰',
    '😍',
    '🤔',
    '😢',
    '😎',
    '👍',
    '👏',
    '🙏',
    '💚',
    '❤️',
    '🎉',
    '🌻',
    '☕',
  ];

  void scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) scroll.jumpTo(0);
    });
  }

  Future<void> load() async {
    if (fetching) {
      reload = true;
      return;
    }
    fetching = true;
    final nearEnd = !scroll.hasClients || scroll.offset < 100;
    try {
      final client = ref.read(clientProvider);
      final color = await client.local?.read('chatBackground:${widget.id}');
      final bgImg = await client.local?.read('chatBackgroundImage:${widget.id}');
      if (mounted) {
        setState(() {
          chatBackground = color is int ? Color(color) : null;
          if (bgImg is String && bgImg.isNotEmpty) {
            try {
              chatBackgroundImage = MemoryImage(base64Decode(bgImg));
            } catch (_) {
              chatBackgroundImage = null;
            }
          } else {
            chatBackgroundImage = null;
          }
        });
      }
      final cached = await client.local?.read('messages:${widget.id}');
      client.clearedSequences[widget.id] =
          await client.local?.read('clearedSequence:${widget.id}') as int? ?? 0;
      if (cached is List && mounted) {
        setState(() {
          messages = client.visibleMessages(
            widget.id,
            cached.map((m) => Map<String, dynamic>.from(m)).toList(),
          );
          loading = false;
        });
      }
      final c = await client.get('/conversations/${widget.id}', cached: false);
      final ownMember = (c['members'] as List).firstWhere(
        (m) => m['userId'] == client.userId,
      );
      await client.applyClearedSequence(
        widget.id,
        ownMember['clearedSequence'] as int? ?? 0,
      );
      if (ownMember['markedUnread'] == true) {
        await client.dio.patch(
          '/conversations/${widget.id}/state',
          data: {'markedUnread': false},
        );
        await client.local?.removeCache('/conversations');
      }
      final rows = await client.messages(widget.id);
      final others = (c['members'] as List).where(
        (m) => m['userId'] != client.userId,
      );
      if (mounted) {
        setState(() {
          messages = client.visibleMessages(widget.id, rows);
          members = c['members'];
          final own = members.where((m) => m['userId'] == client.userId);
          if (own.isNotEmpty) myName = own.first['user']['nickname'];
          title = c['kind'] == 'GROUP'
              ? c['title']
              : others.isEmpty
              ? 'QChat'
              : others.first['user']['nickname'];
          error = null;
        });
      }
      final sent = rows.where((m) => m['pending'] != true);
      if (sent.isNotEmpty &&
          nearEnd &&
          mounted &&
          (WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) &&
          (ModalRoute.of(context)?.isCurrent ?? false) &&
          (sent.last['sequence'] as int) > readSequence) {
        unawaited(
          client
              .post('/conversations/${widget.id}/read', {
                'sequence': sent.last['sequence'],
              })
              .then((_) {
                readSequence = sent.last['sequence'];
              })
              .catchError((_) {}),
        );
      }
      if (nearEnd) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scroll.hasClients) scroll.jumpTo(0);
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = tr(context, 'networkError'));
    } finally {
      fetching = false;
      if (mounted) setState(() => loading = false);
      if (reload && mounted) {
        reload = false;
        unawaited(load());
      }
    }
  }

  Future<void> send() async {
    if (input.text.trim().isEmpty) return;
    final text = input.text;
    input.clear();
    try {
      await ref.read(clientProvider).send(widget.id, text, replyToId: reply);
      if (mounted) setState(() => reply = null);
    } catch (e) {
      if (mounted) setState(() => error = tr(context, 'networkError'));
    }
  }

  Future<void> attachFile(PlatformFile file) async {
    final bytes = await file.readAsBytes();
    const mime = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'mp4': 'video/mp4',
      'mp3': 'audio/mpeg',
      'pdf': 'application/pdf',
    };
    final ext = file.extension?.toLowerCase();
    final type = mime[ext];
    if (type == null) return;
    setState(() => uploading = true);
    try {
      final client = ref.read(clientProvider);
      final intent = await client.post('/media/upload-intent', {
        'name': file.name,
        'size': bytes.length,
        'mime': type,
      });
      await Dio().put(
        intent['url'],
        data: bytes,
        options: Options(headers: {'Content-Type': type}),
      );
      await client.post('/media/complete', {'mediaId': intent['id']});
      await client.send(
        widget.id,
        file.name,
        kind: type.startsWith('image')
            ? 'IMAGE'
            : type.startsWith('video')
            ? 'VIDEO'
            : type.startsWith('audio')
            ? 'AUDIO'
            : 'FILE',
        mediaId: intent['id'],
      );
    } catch (e) {
      if (mounted) setState(() => error = tr(context, 'networkError'));
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> attach({List<String>? extensions}) async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions:
          extensions ??
          ['jpg', 'jpeg', 'png', 'gif', 'webp', 'mp4', 'mp3', 'pdf'],
    );
    if (result != null) await attachFile(result);
  }

  Future<void> attachImage() async {
    final file = await pickImageWithSource(context);
    if (file != null) await attachFile(file);
  }

  Future<void> takePhoto() async {
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        await attachFile(XFilePlatformFile(photo));
      }
    } catch (_) {
      if (mounted) setState(() => error = tr(context, 'networkError'));
    }
  }

  String messageTime(dynamic raw) {
    final d = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (d == null) return '';
    final now = DateTime.now();
    final time =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return d.year == now.year && d.month == now.month && d.day == now.day
        ? time
        : '${d.day}/${d.month} $time';
  }

  bool showTime(int i) {
    if (i == 0) return true;
    final a = DateTime.tryParse(messages[i]['createdAt']?.toString() ?? '');
    final b = DateTime.tryParse(messages[i - 1]['createdAt']?.toString() ?? '');
    return a != null && b != null && a.difference(b).inMinutes.abs() >= 5;
  }

  Widget attachmentPanel(BuildContext c, double safeBottom) {
    final actions = <(String, String, VoidCallback)>[
      (
        'image',
        'image',
        attachImage,
      ),
      ('camera', 'camera', takePhoto),
      ('location', 'location', () => openFeature(c, 'location')),
      ('favorites', 'favorites', () => c.push('/favorites')),
      ('me', 'contactCard', () => openFeature(c, 'contactCard')),
      ('file', 'file', () => attach()),
      ('music', 'music', () => attach(extensions: ['mp3'])),
    ];
    return GridView.count(
      padding: EdgeInsets.fromLTRB(12, 16, 12, 8 + safeBottom),
      crossAxisCount: 4,
      childAspectRatio: .88,
      children: [
        for (final a in actions)
          GestureDetector(
            onTap: uploading ? null : a.$3,
            child: Column(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: surface(c),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Center(
                    child: QChatIcon(
                      a.$1,
                      size: 29,
                      color: const Color(0xff505050),
                      filled: true,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(c, a.$2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xff888888),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget emojiPanel(BuildContext c, double safeBottom) => GridView.count(
    padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + safeBottom),
    crossAxisCount: 8,
    children: [
      for (final e in emojis)
        GestureDetector(
          onTap: () => insertEmoji(e),
          child: Center(child: Text(e, style: const TextStyle(fontSize: 26))),
        ),
    ],
  );

  Future<void> forward(List<Map<String, dynamic>> rows) async {
    try {
      final client = ref.read(clientProvider);
      final chats = await client.get('/conversations', cached: false) as List;
      if (!mounted) return;
      final target = await TDialog.show<String>(
        context,
        dialog: Builder(
          builder: (c) => TDialog(
            title: Text(tr(c, 'forward')),
            content: SizedBox(
              width: double.maxFinite,
              height: 320,
              child: ListView(
                children: [
                  for (final chat in chats)
                    TCell(
                      title: Text(
                        chat['kind'] == 'GROUP'
                            ? chat['title']
                            : (chat['members'] as List)
                                  .where((m) => m['userId'] != client.userId)
                                  .map((m) => m['user']['nickname'])
                                  .join(', '),
                      ),
                      onTap: () => Navigator.pop(c, chat['id'] as String),
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
      if (target == null) return;
      for (final row in rows) {
        await client.post('/messages/${row['id']}/forward', {
          'conversationId': target,
          'clientId': const Uuid().v4(),
        });
      }
      if (mounted) {
        setState(() {
          selecting = false;
          selected.clear();
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = tr(context, 'networkError'));
    }
  }

  Future<void> deleteMessages(List<Map<String, dynamic>> rows) async {
    if (!await confirmAction(
      context,
      tr(context, 'delete'),
      tr(context, 'deleteMessagesNote'),
    )) {
      return;
    }
    await operation(() async {
      for (final row in rows) {
        await ref.read(clientProvider).dio.delete('/messages/${row['id']}');
      }
    });
    if (mounted) {
      setState(() {
        selecting = false;
        selected.clear();
      });
    }
  }

  Widget menu(Map<String, dynamic> m) {
    final sent = m['pending'] != true && m['recalledAt'] == null;
    final created = DateTime.tryParse(m['createdAt']?.toString() ?? '');
    final actions = <(String, IconData, VoidCallback)>[
      (
        'copy',
        TIcons.copy,
        () => Clipboard.setData(ClipboardData(text: m['text'] ?? '')),
      ),
      if (sent) ...[
        ('forward', TIcons.share, () => forward([m])),
        (
          'favorites',
          TIcons.star,
          () => operation(
            () => ref
                .read(clientProvider)
                .dio
                .patch(
                  '/messages/${m['id']}/favorite',
                  data: {'favorite': true},
                ),
          ),
        ),
        ('delete', TIcons.delete, () => deleteMessages([m])),
        (
          'selectMessages',
          TIcons.check_rectangle,
          () => setState(() {
            selecting = true;
            selected.add(m['id']);
          }),
        ),
        (
          'quoteMessage',
          TIcons.quote,
          () {
            setState(() => reply = m['id']);
            inputFocus.requestFocus();
          },
        ),
        (
          'search',
          TIcons.search,
          () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ChatHistoryScreen(id: widget.id, query: m['text'] ?? ''),
            ),
          ),
        ),
        if (m['senderId'] == ref.read(clientProvider).userId &&
            created != null &&
            DateTime.now().difference(created).inSeconds < 120)
          (
            'recall',
            TIcons.rollback,
            () => operation(
              () => ref
                  .read(clientProvider)
                  .post('/messages/${m['id']}/recall', {}),
            ),
          ),
      ],
    ];
    return Builder(
      builder: (c) => Wrap(
        children: [
          for (final a in actions)
            SizedBox(
              width: (MediaQuery.sizeOf(c).width.clamp(0, 430) - 48) / 4,
              height: 78,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  TPopoverController.maybeOf(c)?.close();
                  a.$3();
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TIcon(a.$2, size: 22, color: Colors.white),
                    const SizedBox(height: 4),
                    Text(
                      tr(c, a.$1),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> operation(Future<dynamic> Function() fn) async {
    try {
      await fn();
      await ref.read(clientProvider).local!.cache('messages:${widget.id}', []);
      await ref.read(clientProvider).local!.cache('cursor:${widget.id}', 0);
      ref
          .read(clientProvider)
          .confirmed
          .removeWhere((_, m) => m['conversationId'] == widget.id);
      await load();
    } catch (e) {
      if (mounted) setState(() => error = tr(context, 'networkError'));
    }
  }

  @override
  Widget build(BuildContext c) {
    final lastOutgoing = messages.lastIndexWhere(
      (message) =>
          message['senderId'] == ref.read(clientProvider).userId &&
          message['recalledAt'] == null,
    );
    final keyboard = MediaQuery.viewInsetsOf(c).bottom;
    final safeBottom = MediaQuery.viewPaddingOf(c).bottom;
    if (keyboard > keyboardHeight) keyboardHeight = keyboard;
    final panelOpen = emoji || attachments;
    final panelHeight = math.max(keyboardHeight, 250 + safeBottom);
    // Hàm liên tục theo bàn phím: không còn bước nhảy từ viewInsets -> safe area.
    final reserved = math.max(keyboard, panelOpen ? panelHeight : safeBottom);
    return QChatPage(
      title: title,
      background: chatBackground,
      backgroundImage: chatBackgroundImage,
      leading: QChatIconButton(
        'back',
        label: tr(c, 'back'),
        onTap: () => context.canPop() ? context.pop() : context.go('/home'),
      ),
      trailing: QChatIconButton(
        'more',
        label: tr(c, 'settings'),
        onTap: () async {
          dismissInput();
          await Navigator.of(c).push(
            MaterialPageRoute<void>(
              builder: (_) => ChatDetailsScreen(id: widget.id),
            ),
          );
          if (mounted) load();
        },
      ),
      child: Column(
        children: [
          if (error != null)
            GestureDetector(
              onTap: load,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  error!,
                  style: const TextStyle(
                    color: QChatColors.danger,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          Expanded(
            child: loading
                ? const QChatLoading()
                : messages.isEmpty
                ? QChatEmptyState(tr(c, 'emptyChats'))
                : GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: dismissInput,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ListView.builder(
                        controller: scroll,
                        // reverse: điểm bắt đầu là tin mới nhất -> mở chat không phải
                        // cuộn từ trên xuống. Ít tin thì shrinkWrap + Align để vẫn
                        // nằm sát phía trên như cũ.
                        reverse: true,
                        shrinkWrap: messages.length < 12,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: messages.length,
                        itemBuilder: (c, index) {
                          final i = messages.length - 1 - index;
                          final m = messages[i],
                              mine =
                                  m['senderId'] ==
                                  ref.read(clientProvider).userId;
                          return Column(
                            children: [
                              if (showTime(i))
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  child: Text(
                                    messageTime(m['createdAt']),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: QChatColors.muted,
                                    ),
                                  ),
                                ),
                              if (selecting && m['pending'] != true)
                                TButton(
                                  variant: TButtonVariant.text,
                                  onPressed: () => setState(
                                    () => selected.contains(m['id'])
                                        ? selected.remove(m['id'])
                                        : selected.add(m['id']),
                                  ),
                                  child: TIcon(
                                    selected.contains(m['id'])
                                        ? TIcons.check_circle_filled
                                        : TIcons.circle,
                                    color: QChatColors.green,
                                  ),
                                ),
                              TPopoverAnchor(
                                content: menu(m),
                                placement: TPopoverPlacement.bottom,
                                width:
                                    MediaQuery.sizeOf(c).width.clamp(0, 430) -
                                    24,
                                showArrow: true,
                                builder: (anchor, controller, _) =>
                                    QChatChatBubble(
                                      mine: mine,
                                      avatar: UserAvatar(
                                        members.cast<Map>().firstWhere(
                                          (member) =>
                                              member['userId'] == m['senderId'],
                                          orElse: () => {
                                            'user':
                                                m['sender'] ??
                                                {
                                                  'nickname': mine
                                                      ? myName
                                                      : title,
                                                },
                                          },
                                        )['user'],
                                        size: 42,
                                      ),
                                      name: mine ? myName : title,
                                      onLongPress: controller.open,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (m['replyToId'] != null)
                                            Text(
                                              '↳ ${tr(c, 'reply')}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: QChatColors.muted,
                                              ),
                                            ),
                                          if (m['mediaId'] != null)
                                            GestureDetector(
                                              onTap: () => context.push(
                                                '/media/${m['mediaId']}',
                                              ),
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 8,
                                                ),
                                                child: QChatIcon(
                                                  m['kind'] == 'IMAGE'
                                                      ? 'image'
                                                      : 'file',
                                                  size: 40,
                                                ),
                                              ),
                                            ),
                                          Text(
                                            m['recalledAt'] != null
                                                ? tr(c, 'recalled')
                                                : m['text'] ?? '',
                                          ),
                                        ],
                                      ),
                                    ),
                              ),
                              if (i == lastOutgoing)
                                MessageStatus(
                                  status: ref
                                      .read(clientProvider)
                                      .messageStatus(m, members),
                                  onRetry: () =>
                                      ref.read(clientProvider).flush(),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
          ),
          if (selecting)
            Row(
              children: [
                Expanded(
                  child: TButton(
                    variant: TButtonVariant.text,
                    onPressed: selected.isEmpty
                        ? null
                        : () => forward(
                            messages
                                .where((m) => selected.contains(m['id']))
                                .toList(),
                          ),
                    child: Text(tr(c, 'forward')),
                  ),
                ),
                Expanded(
                  child: TButton(
                    variant: TButtonVariant.text,
                    onPressed: selected.isEmpty
                        ? null
                        : () => deleteMessages(
                            messages
                                .where((m) => selected.contains(m['id']))
                                .toList(),
                          ),
                    child: Text(tr(c, 'delete')),
                  ),
                ),
                Expanded(
                  child: TButton(
                    variant: TButtonVariant.text,
                    onPressed: () => setState(() {
                      selecting = false;
                      selected.clear();
                    }),
                    child: Text(tr(c, 'cancel')),
                  ),
                ),
              ],
            ),
          if (reply != null)
            QChatListTile(
              title: tr(c, 'reply'),
              trailing: QChatButton(
                tr(c, 'cancel'),
                onTap: () => setState(() => reply = null),
              ),
            ),
          if (uploading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                tr(c, 'loading'),
                style: const TextStyle(fontSize: 12, color: QChatColors.muted),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: navigationSurface(c),
              border: Border(
                top: BorderSide(
                  color: ink(c).withValues(alpha: .08),
                  width: .5,
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ChatInputBar(
                  controller: input,
                  focusNode: inputFocus,
                  voice: voice,
                  hasText: input.text.trim().isNotEmpty,
                  voiceLabel: tr(c, 'voice'),
                  emojiLabel: 'Emoji',
                  plusLabel: tr(c, 'file'),
                  sendLabel: tr(c, 'send'),
                  holdLabel: tr(c, 'holdToTalk'),
                  onVoice: toggleVoice,
                  onEmoji: toggleEmoji,
                  onPlus: togglePlus,
                  onSend: send,
                  onHold: () => openFeature(c, 'voice'),
                  onChanged: (_) => setState(() {}),
                ),
                // Vùng đáy: = bàn phím | panel emoji/đính kèm | safe area.
                // Khi bàn phím đang chuyển động thì không animate thêm để khỏi trễ.
                AnimatedContainer(
                  duration: keyboard > 0 || inputFocus.hasFocus
                      ? Duration.zero
                      : qchatDuration(c),
                  curve: Curves.easeOut,
                  height: reserved,
                  child: panelOpen
                      ? ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.topCenter,
                            minHeight: 0,
                            maxHeight: panelHeight,
                            child: SizedBox(
                              height: panelHeight,
                              child: emoji
                                  ? emojiPanel(c, safeBottom)
                                  : attachmentPanel(c, safeBottom),
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
