import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import '../design_system/components.dart';
import '../design_system/media_widgets.dart';
import '../localization/strings.dart';
import 'client.dart';

const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
const momentExtensions = [...imageExtensions, 'mp4', 'mov'];
const maxMediaBytes = 25 * 1024 * 1024;

base class XFilePlatformFile extends PlatformFile {
  XFilePlatformFile(this._xFile, [this._bytes, this._length]);
  final XFile _xFile;
  final Uint8List? _bytes;
  final int? _length;

  @override
  String get name => _xFile.name;

  @override
  Uri get uri => Uri.parse(
    _xFile.path.startsWith('http') ||
            _xFile.path.startsWith('content:') ||
            _xFile.path.startsWith('file:')
        ? _xFile.path
        : 'file://${_xFile.path}',
  );

  @override
  String? get path => _xFile.path;

  @override
  XFile get xFile => _xFile;

  @override
  int? lengthSync() => _length ?? _bytes?.length;

  @override
  Future<int?> length() async =>
      _length ?? _bytes?.length ?? await _xFile.length();

  @override
  Future<Uint8List> readAsBytes() async =>
      _bytes ?? await _xFile.readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() => _xFile.openRead();
}

Future<PlatformFile?> pickImageWithSource(
  BuildContext context, {
  List<String>? allowedExtensions,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            leading: const TIcon(TIcons.image, size: 24, color: QChatColors.primary),
            title: Text(tr(c, 'photoLibrary')),
            onTap: () => Navigator.pop(c, 'gallery'),
          ),
          ListTile(
            leading: const TIcon(TIcons.folder, size: 24, color: QChatColors.primary),
            title: Text(tr(c, 'fromFiles')),
            onTap: () => Navigator.pop(c, 'file'),
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
  );
  if (choice == null) return null;
  if (choice == 'gallery') {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery);
    if (x == null) return null;
    return XFilePlatformFile(x);
  } else {
    return await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: allowedExtensions ?? imageExtensions,
    );
  }
}

Future<List<PlatformFile>> pickMediaWithSource(
  BuildContext context, {
  bool video = false,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            leading: const TIcon(TIcons.image, size: 24, color: QChatColors.primary),
            title: Text(tr(c, 'photoLibrary')),
            onTap: () => Navigator.pop(c, 'gallery'),
          ),
          ListTile(
            leading: const TIcon(TIcons.folder, size: 24, color: QChatColors.primary),
            title: Text(tr(c, 'fromFiles')),
            onTap: () => Navigator.pop(c, 'file'),
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
  );
  if (choice == null) return [];
  if (choice == 'gallery') {
    final picker = ImagePicker();
    if (video) {
      final x = await picker.pickVideo(source: ImageSource.gallery);
      if (x == null) return [];
      return [XFilePlatformFile(x)];
    } else {
      final list = await picker.pickMultiImage();
      return list.map((x) => XFilePlatformFile(x)).toList();
    }
  } else {
    return await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: video ? ['mp4', 'mov'] : imageExtensions,
    );
  }
}

String? mediaMime(String? extension) => const {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
}[extension?.toLowerCase()];

Future<String> uploadMedia(QChatClient client, PlatformFile file) async {
  final mime = mediaMime(file.extension);
  if (mime == null) throw StateError('unsupportedMedia');
  if ((await file.length() ?? 0) > maxMediaBytes) {
    throw StateError('mediaTooLarge');
  }
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty || bytes.length > maxMediaBytes) {
    throw StateError('mediaTooLarge');
  }
  final intent = await client.post('/media/upload-intent', {
    'name': file.name,
    'size': bytes.length,
    'mime': mime,
  });
  final uploader = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(minutes: 3),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  try {
    await uploader.put(
      intent['url'],
      data: bytes,
      options: Options(headers: {'Content-Type': mime}),
    );
    await client.post('/media/complete', {'mediaId': intent['id']});
    final mediaId = intent['id'] as String;
    MediaCache.put(mediaId, bytes, local: client.local);
    return mediaId;
  } finally {
    uploader.close();
  }
}
