import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:uuid/uuid.dart';
import '../storage/database.dart';

const apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://chat.nguyenphuquyet.online/api',
);
const realtimeUrl = String.fromEnvironment(
  'REALTIME_URL',
  defaultValue: 'https://chat.nguyenphuquyet.online',
);

class QChatClient {
  final dio = Dio(
    BaseOptions(
      baseUrl: apiUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );
  final storage = const FlutterSecureStorage();
  final changes = StreamController<void>.broadcast();
  final messageChanges = StreamController<void>.broadcast(sync: true);
  final Map<String, Map<String, dynamic>> outgoing = {};
  final Map<String, Map<String, dynamic>> confirmed = {};
  final Map<String, Map<String, int>> receipts = {};
  final Map<String, Future<List<Map<String, dynamic>>>> syncing = {};
  String? userId, token;
  io.Socket? socket;
  LocalDatabase? local;
  Future<void>? refreshing;
  bool flushing = false;
  bool stopping = false;
  final offline = ValueNotifier<bool>(false);
  final Map<String, Future<dynamic>> _requests = {};
  final Map<String, DateTime> _checked = {};
  Timer? _recovery;
  bool _reconnecting = false;

  static bool connectionFailure(Object error) =>
      error is DioException &&
      (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          (error.response?.statusCode ?? 0) >= 500);

  void _connectionLost() {
    offline.value = true;
    if (userId != null && !stopping) {
      _recovery ??= Timer.periodic(const Duration(seconds: 15), (_) {
        unawaited(reconnect());
      });
    }
  }

  Future<void> reconnect() async {
    if (_reconnecting || userId == null || stopping) return;
    _reconnecting = true;
    try {
      await refresh();
      offline.value = false;
      _recovery?.cancel();
      _recovery = null;
      _checked.clear();
      connect();
      changes.add(null);
    } catch (e) {
      if (connectionFailure(e)) _connectionLost();
    } finally {
      _reconnecting = false;
    }
  }

  QChatClient() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          if (token != null) o.headers['Authorization'] = 'Bearer $token';
          h.next(o);
        },
        onResponse: (r, h) {
          offline.value = false;
          if (r.requestOptions.method != 'GET') _checked.clear();
          h.next(r);
        },
        onError: (e, h) async {
          if (connectionFailure(e)) _connectionLost();
          if (e.response?.statusCode == 401 &&
              e.requestOptions.extra['retry'] != true &&
              !e.requestOptions.path.startsWith('/auth/')) {
            try {
              await refresh();
              e.requestOptions.extra['retry'] = true;
              e.requestOptions.headers['Authorization'] = 'Bearer $token';
              h.resolve(await dio.fetch(e.requestOptions));
              return;
            } catch (refreshError) {
              if (refreshError is DioException &&
                  connectionFailure(refreshError)) {
                _connectionLost();
                h.reject(refreshError);
                return;
              }
            }
          }
          h.next(e);
        },
      ),
    );
  }
  Future<bool> restore() async {
    userId = await storage.read(key: 'userId');
    if (userId == null) return false;
    local = LocalDatabase(userId!);
    // Open the saved account immediately; network recovery must not block UI.
    unawaited(reconnect());
    return true;
  }

  Future<void> login(Map<String, dynamic> data, {bool register = false}) async {
    final response = await dio.post(
      '/auth/${register ? 'register' : 'login'}',
      data: data,
    );
    await save(Map<String, dynamic>.from(response.data));
    local = LocalDatabase(userId!);
    connect();
  }

  Future<void> save(Map<String, dynamic> data) async {
    token = data['accessToken'];
    userId = data['userId'];
    await storage.write(key: 'refreshToken', value: data['refreshToken']);
    await storage.write(key: 'userId', value: userId);
  }

  Future<void> refresh() async {
    if (refreshing != null) return refreshing;
    refreshing = _refresh();
    try {
      await refreshing;
    } finally {
      refreshing = null;
    }
  }

  Future<void> _refresh() async {
    final refresh = await storage.read(key: 'refreshToken');
    if (refresh == null) throw StateError('Session expired');
    final r = await Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    ).post('$apiUrl/auth/refresh', data: {'refreshToken': refresh});
    await save(Map<String, dynamic>.from(r.data));
  }

  void connect() {
    stopping = true;
    socket?.dispose();
    stopping = false;
    socket = io.io(
      realtimeUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(30000)
          .build(),
    );
    socket!.onConnect((_) {
      offline.value = false;
      _checked.clear();
      flush();
      syncInbox();
      changes.add(null);
    });
    socket!.on('message:new', (event) async {
      try {
        _checked.clear();
        final message = Map<String, dynamic>.from(event);
        confirmed[message['clientId']] = message;
        messageChanges.add(null);
        await syncing[event['conversationId']];
        await messages(event['conversationId']);
        changes.add(null);
        messageChanges.add(null);
      } catch (_) {}
    });
    for (final name in ['message:delivered', 'message:read']) {
      socket!.on(name, (event) {
        final key = '${event['conversationId']}:${event['userId']}';
        final state = receipts.putIfAbsent(key, () => {});
        final field = name == 'message:read'
            ? 'readSequence'
            : 'deliveredSequence';
        final sequence = event['sequence'] as int;
        if (sequence > (state[field] ?? 0)) state[field] = sequence;
        messageChanges.add(null);
      });
    }
    socket!.on('message:recall', (event) async {
      _checked.clear();
      confirmed.removeWhere((_, m) => m['id'] == event['id']);
      final key = 'messages:${event['conversationId']}';
      final rows = await local?.read(key);
      if (rows is List) {
        for (final row in rows) {
          if (row['id'] == event['id']) {
            row['text'] = '';
            row['mediaId'] = null;
            row['recalledAt'] = DateTime.now().toIso8601String();
          }
        }
        await local?.cache(key, rows);
      }
      changes.add(null);
    });
    socket!.onDisconnect((_) async {
      if (stopping) return;
      _connectionLost();
      try {
        await refresh();
        socket!.auth = {'token': token};
        socket!.connect();
      } catch (_) {}
    });
    socket!.connect();
  }

  Future<dynamic> get(String path, {bool cached = true}) async {
    if (!cached) return (await dio.get(path)).data;
    final database = local;
    dynamic saved;
    try {
      saved = await database?.read(path);
    } catch (_) {
      // A storage failure must not prevent an online request.
    }
    if (saved != null) {
      final checked = _checked[path];
      if (checked == null ||
          DateTime.now().difference(checked) > const Duration(seconds: 10)) {
        unawaited(_fetchCached(path, database, saved).catchError((_) => null));
      }
      return saved;
    }
    return _fetchCached(path, database, null);
  }

  Future<dynamic> _fetchCached(
    String path,
    LocalDatabase? database,
    dynamic saved,
  ) async {
    if (_requests.containsKey(path)) return _requests[path];
    final request = _fetchAndStore(path, database, saved);
    _requests[path] = request;
    try {
      return await request;
    } finally {
      _requests.remove(path);
    }
  }

  Future<dynamic> _fetchAndStore(
    String path,
    LocalDatabase? database,
    dynamic saved,
  ) async {
    try {
      if (refreshing != null) await refreshing;
      final data = (await dio.get(path)).data;
      // Never write an old account's response into a newly logged-in account.
      if (database != local) return data;
      _checked[path] = DateTime.now();
      try {
        if (data != null) await database?.cache(path, data);
      } catch (_) {}
      if (saved != null && jsonEncode(saved) != jsonEncode(data)) {
        changes.add(null);
      }
      return data;
    } catch (e) {
      if (connectionFailure(e)) _connectionLost();
      if (database == local &&
          e is DioException &&
          [401, 403, 404].contains(e.response?.statusCode)) {
        await database?.removeCache(path);
        _checked.remove(path);
        if (saved != null) changes.add(null);
      }
      rethrow;
    }
  }

  Future<dynamic> post(String path, Object data) async =>
      (await dio.post(path, data: data)).data;
  Future<void> syncInbox() async {
    try {
      final conversations = await get('/conversations', cached: false);
      for (final c in conversations) {
        await messages(c['id']);
      }
      changes.add(null);
      messageChanges.add(null);
    } catch (_) {}
  }

  String messageStatus(Map<String, dynamic> message, List<dynamic> members) {
    if (message['failed'] == true) return 'sendFailed';
    if (message['pending'] == true) return 'sending';
    final sequence = message['sequence'] as int? ?? 0;
    final peers = members.where((m) => m['userId'] != userId).toList();
    bool reached(String field) =>
        peers.isNotEmpty &&
        peers.every((m) {
          final live =
              receipts['${message['conversationId']}:${m['userId']}']?[field] ??
              0;
          return (live > (m[field] ?? 0) ? live : (m[field] ?? 0)) >= sequence;
        });
    if (reached('readSequence')) return 'read';
    if (reached('deliveredSequence')) return 'delivered';
    return 'sent';
  }

  List<Map<String, dynamic>> visibleMessages(
    String id,
    List<Map<String, dynamic>> base,
  ) {
    final rows = <String, Map<String, dynamic>>{};
    for (final m in [...base, ...outgoing.values, ...confirmed.values]) {
      if (m['conversationId'] == id) rows[m['clientId'] ?? m['id']] = m;
    }
    final result = rows.values.toList();
    result.sort((a, b) {
      if (a['sequence'] != null && b['sequence'] != null) {
        return (a['sequence'] as int).compareTo(b['sequence']);
      }
      if (a['sequence'] != null) return -1;
      if (b['sequence'] != null) return 1;
      return (a['createdAt'] as String).compareTo(b['createdAt']);
    });
    return result;
  }

  Future<void> send(
    String conversation,
    String text, {
    String kind = 'TEXT',
    String? mediaId,
    String? replyToId,
  }) async {
    final payload = {
      'conversationId': conversation,
      'clientId': const Uuid().v4(),
      'kind': kind,
      'text': text,
      'mediaId': ?mediaId,
      'replyToId': ?replyToId,
    };
    final id = payload['clientId']!;
    outgoing[id] = {
      ...payload,
      'id': id,
      'senderId': userId,
      'pending': true,
      'createdAt': DateTime.now().toIso8601String(),
    };
    messageChanges.add(null);
    try {
      await local!.enqueue(payload);
      unawaited(flush());
    } catch (_) {
      outgoing[id]!['failed'] = true;
      messageChanges.add(null);
      rethrow;
    }
  }

  Future<void> flush() async {
    if (flushing || local == null) return;
    flushing = true;
    try {
      while (true) {
        final queue = await local!.pending();
        if (queue.isEmpty) break;
        final p = queue.first;
        try {
          await local!.markFailed(p['clientId'], false);
          outgoing[p['clientId']] = {
            ...p,
            'id': p['clientId'],
            'senderId': userId,
            'pending': true,
            'failed': false,
          };
          messageChanges.add(null);
          final result = Map<String, dynamic>.from(
            await post(
              '/conversations/${p['conversationId']}/messages',
              {...p}
                ..remove('conversationId')
                ..remove('createdAt')
                ..remove('failed'),
            ),
          );
          confirmed[p['clientId']] = result;
          await local!.mergeMessages(p['conversationId'], [result]);
          await local!.remove(p['clientId']);
          outgoing.remove(p['clientId']);
          messageChanges.add(null);
        } catch (_) {
          for (final waiting in await local!.pending()) {
            outgoing[waiting['clientId']]?['failed'] = true;
            await local!.markFailed(waiting['clientId'], true);
          }
          messageChanges.add(null);
          break;
        }
      }
    } finally {
      flushing = false;
      changes.add(null);
    }
  }

  Future<List<Map<String, dynamic>>> messages(String id) async {
    if (syncing.containsKey(id)) return syncing[id]!;
    final future = _messages(id);
    syncing[id] = future;
    try {
      return await future;
    } finally {
      syncing.remove(id);
    }
  }

  Future<List<Map<String, dynamic>>> _messages(String id) async {
    final key = 'messages:$id';
    final old = List<Map<String, dynamic>>.from(
      (await local!.read(key) ?? []).map((e) => Map<String, dynamic>.from(e)),
    );
    // A send acknowledgement can arrive ahead of missing incoming messages.
    // Only a completed history sync may advance this cursor.
    int cursor = await local!.read('cursor:$id') as int? ?? 0;
    try {
      while (true) {
        final batch = List<Map<String, dynamic>>.from(
          (await get(
            '/conversations/$id/messages?after=$cursor',
            cached: false,
          )).map((e) => Map<String, dynamic>.from(e)),
        );
        for (final m in batch) {
          if (outgoing.containsKey(m['clientId']) ||
              confirmed.containsKey(m['clientId'])) {
            confirmed[m['clientId']] = m;
          }
          old.removeWhere((x) => x['id'] == m['id']);
          old.add(m);
          cursor = m['sequence'];
        }
        if (batch.length < 50) break;
      }
      await local!.mergeMessages(id, old);
      await local!.cache('cursor:$id', cursor);
      for (final m in old) {
        if (outgoing.containsKey(m['clientId'])) {
          confirmed[m['clientId']] = m;
          await local!.remove(m['clientId']);
          outgoing.remove(m['clientId']);
        }
      }
      if (cursor > 0) {
        await post('/conversations/$id/delivered', {'sequence': cursor});
      }
    } catch (_) {
      // Keep the outbox visible even when the first network request fails.
    }
    final pending = (await local!.pending())
        .where((m) => m['conversationId'] == id)
        .map(
          (m) => {
            ...m,
            'id': m['clientId'],
            'senderId': userId,
            'pending': true,
          },
        );
    for (final m in pending) {
      outgoing.putIfAbsent(m['clientId'], () => m);
    }
    return visibleMessages(id, old);
  }

  Future<void> logout() async {
    await post('/auth/logout', {});
    await clearSession();
  }

  Future<void> clearSession() async {
    stopping = true;
    _recovery?.cancel();
    _recovery = null;
    _checked.clear();
    _requests.clear();
    offline.value = false;
    socket?.dispose();
    socket = null;
    await local?.clear();
    await local?.close();
    local = null;
    await storage.deleteAll();
    token = null;
    userId = null;
    outgoing.clear();
    confirmed.clear();
    receipts.clear();
  }

  void dispose() {
    stopping = true;
    _recovery?.cancel();
    socket?.dispose();
    dio.close(force: true);
  }
}
