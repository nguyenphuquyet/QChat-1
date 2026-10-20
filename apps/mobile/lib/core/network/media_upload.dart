import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'client.dart';

const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
const momentExtensions = [...imageExtensions, 'mp4', 'mov'];
const maxMediaBytes = 25 * 1024 * 1024;

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
  if (file.size > maxMediaBytes) throw StateError('mediaTooLarge');
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
    return intent['id'] as String;
  } finally {
    uploader.close();
  }
}
