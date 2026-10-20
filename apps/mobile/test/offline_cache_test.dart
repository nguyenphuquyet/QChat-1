import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qchat/app/providers.dart';
import 'package:qchat/core/design_system/components.dart';
import 'package:qchat/core/network/client.dart';
import 'package:qchat/core/network/connection_banner.dart';
import 'package:qchat/core/storage/database.dart';
import 'package:qchat/features/chats/home_screen.dart';

class DelayedTransport implements HttpClientAdapter {
  final started = Completer<RequestOptions>();
  final response = Completer<ResponseBody>();
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) {
    if (!started.isCompleted) started.complete(options);
    return response.future;
  }

  @override
  void close({bool force = false}) {}
}

class OfflineClient extends QChatClient {
  @override
  Future<dynamic> get(String path, {bool cached = true}) async {
    throw DioException(
      requestOptions: RequestOptions(path: path),
      type: DioExceptionType.connectionError,
    );
  }
}

void main() {
  test(
    'cached data renders before HTTP finishes and fresh data is persisted',
    () async {
      final client = QChatClient()
        ..local = LocalDatabase.testing(NativeDatabase.memory());
      final transport = DelayedTransport();
      client.dio.httpClientAdapter = transport;
      addTearDown(() async {
        client.dispose();
        await client.local!.close();
      });
      await client.local!.cache('/friends', [
        {'id': 'old'},
      ]);
      final result = await client
          .get('/friends')
          .timeout(const Duration(seconds: 1));
      expect(result.single['id'], 'old');
      expect(transport.response.isCompleted, false);
      await transport.started.future;
      final changed = client.changes.stream.first;
      transport.response.complete(
        ResponseBody.fromString(
          jsonEncode([
            {'id': 'new'},
          ]),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        ),
      );
      await changed.timeout(const Duration(seconds: 2));
      expect((await client.get('/friends')).single['id'], 'new');
      expect((await client.local!.read('/friends')).single['id'], 'new');
    },
  );

  test(
    'connection failure keeps persistent cache and exposes offline state',
    () async {
      final client = QChatClient()
        ..local = LocalDatabase.testing(NativeDatabase.memory());
      final transport = DelayedTransport();
      client.dio.httpClientAdapter = transport;
      addTearDown(() async {
        client.dispose();
        await client.local!.close();
      });
      await client.local!.cache('/conversations', [
        {'id': 'saved-chat'},
      ]);
      expect((await client.get('/conversations')).single['id'], 'saved-chat');
      final request = await transport.started.future;
      final offline = Completer<void>();
      client.offline.addListener(() {
        if (client.offline.value && !offline.isCompleted) offline.complete();
      });
      transport.response.completeError(
        DioException(
          requestOptions: request,
          type: DioExceptionType.connectionError,
        ),
      );
      await offline.future.timeout(const Duration(seconds: 2));
      expect(
        (await client.local!.read('/conversations')).single['id'],
        'saved-chat',
      );
    },
  );

  test('server denial invalidates cached private data', () async {
    final client = QChatClient()
      ..local = LocalDatabase.testing(NativeDatabase.memory());
    final transport = DelayedTransport();
    client.dio.httpClientAdapter = transport;
    addTearDown(() async {
      client.dispose();
      await client.local!.close();
    });
    await client.local!.cache('/friends', [
      {'id': 'old'},
    ]);
    await client.get('/friends');
    await transport.started.future;
    final changed = client.changes.stream.first;
    transport.response.complete(
      ResponseBody.fromString(
        '{}',
        403,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      ),
    );
    await changed.timeout(const Duration(seconds: 2));
    expect(await client.local!.read('/friends'), isNull);
    expect(client.offline.value, false);
  });

  testWidgets('offline without cache retains home navigation and search', (
    tester,
  ) async {
    final client = OfflineClient()..offline.value = true;
    addTearDown(client.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [clientProvider.overrideWithValue(client)],
        child: MaterialApp(
          home: Material(
            child: ConnectionBanner(client: client, child: const HomeScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(QChatBottomNavigation), findsOneWidget);
    expect(find.byType(QChatSearchBar), findsOneWidget);
    expect(find.byType(QChatError), findsNothing);
    // Banner retry button removed – offline state is now shown silently via
    // the header title change ("Đã ngắt kết nối") instead of a Material banner.
    expect(find.byType(TextButton), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
