import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:qchat/app/providers.dart';
import 'package:qchat/core/design_system/components.dart';
import 'package:qchat/core/design_system/media_widgets.dart';
import 'package:qchat/core/design_system/qchat_theme.dart';
import 'package:qchat/core/network/client.dart';
import 'package:qchat/features/chats/chat_screen.dart';
import 'package:qchat/features/chats/chat_details_screen.dart';
import 'package:qchat/features/chats/home_screen.dart';
import 'package:qchat/features/profile/user_profile_screen.dart';

class FakeClient extends QChatClient {
  FakeClient({this.isFriend = false, this.group = false, this.owner = false}) {
    userId = 'self';
  }
  final bool isFriend, group, owner;
  final calls = <String>[];
  final peer = {
    'id': 'peer',
    'nickname': 'Quyết',
    'qchatId': 'quyetguic',
    'avatarId': 'photo',
  };
  Map<String, dynamic> get conversation => {
    'id': 'chat',
    'kind': group ? 'GROUP' : 'DIRECT',
    'title': 'Nhóm thử',
    'sequence': 1,
    'members': [
      {
        'userId': 'self',
        'role': owner ? 'OWNER' : 'MEMBER',
        'readSequence': 1,
        'user': {'id': 'self', 'nickname': 'Tôi', 'avatarId': 'my-photo'},
      },
      {'userId': 'peer', 'role': 'MEMBER', 'readSequence': 0, 'user': peer},
    ],
    'messages': rows,
  };
  List<Map<String, dynamic>> get rows => [
    {
      'id': 'message',
      'clientId': 'client',
      'conversationId': 'chat',
      'senderId': 'self',
      'text': 'Xin chào',
      'sequence': 1,
      'createdAt': DateTime.now().toIso8601String(),
    },
  ];
  @override
  Future<dynamic> get(String path, {bool cached = true}) async {
    calls.add(path);
    if (path == '/users/peer') return peer;
    if (path.startsWith('/users/search')) return [peer];
    if (path == '/friends') {
      return isFriend
          ? [
              {'friendId': 'peer', 'friend': peer},
            ]
          : [];
    }
    if (path == '/conversations') return [conversation];
    if (path == '/conversations/chat') return conversation;
    if (path.contains('/messages?')) return rows;
    if (path.contains('/media/')) throw Exception('offline photo');
    return [];
  }

  @override
  Future<List<Map<String, dynamic>>> messages(String id) async => rows;
  @override
  Future<dynamic> post(String path, Object data) async {
    calls.add(path);
    return {'id': 'chat'};
  }
}

Future<void> mount(
  WidgetTester tester,
  FakeClient client,
  Widget screen,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [clientProvider.overrideWithValue(client)],
      child: MaterialApp(
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: qchatTheme(false),
        home: Material(child: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'three dots opens TDesign details and message avatars use media IDs',
    (tester) async {
      final client = FakeClient();
      await mount(tester, client, const ChatScreen(id: 'chat'));
      expect(find.byType(UserAvatar), findsOneWidget);
      expect(tester.widget<MediaImage>(find.byType(MediaImage)).id, 'my-photo');
      await tester.tap(
        find.byWidgetPredicate((w) => w is QChatIconButton && w.icon == 'more'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chi tiết'), findsOneWidget);
      expect(find.byType(TSwitch), findsOneWidget);
      expect(find.text('Xóa lịch sử trò chuyện'), findsOneWidget);
      expect(find.text('Giải tán nhóm'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('QR lookup shows Add friend and sends request only when tapped', (
    tester,
  ) async {
    final client = FakeClient();
    await mount(tester, client, const UserProfileScreen(qchatId: 'quyetguic'));
    expect(client.calls, contains('/users/search?q=quyetguic'));
    expect(find.text('Thêm bạn'), findsOneWidget);
    expect(client.calls, isNot(contains('/friends/requests')));
    await tester.tap(find.text('Thêm bạn'));
    await tester.pumpAndSettle();
    expect(client.calls, contains('/friends/requests'));
    expect(find.text('Đã gửi lời mời'), findsOneWidget);
  });
  testWidgets('friend profile shows message and both call actions', (
    tester,
  ) async {
    await mount(
      tester,
      FakeClient(isFriend: true),
      const UserProfileScreen(id: 'peer'),
    );
    expect(find.text('Nhắn tin'), findsOneWidget);
    expect(find.text('Gọi thoại'), findsOneWidget);
    expect(find.text('Gọi video'), findsOneWidget);
    expect(find.text('Thêm bạn'), findsNothing);
  });
  testWidgets('only group owner sees dissolve action', (tester) async {
    await mount(
      tester,
      FakeClient(group: true, owner: true),
      const ChatDetailsScreen(id: 'chat'),
    );
    expect(find.text('Thành viên'), findsOneWidget);
    expect(find.text('Giải tán nhóm'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await mount(
      tester,
      FakeClient(group: true),
      const ChatDetailsScreen(id: 'chat'),
    );
    expect(find.text('Thành viên'), findsOneWidget);
    expect(find.text('Giải tán nhóm'), findsNothing);
  });
  testWidgets('long press opens anchored actions and selection', (
    tester,
  ) async {
    await mount(tester, FakeClient(), const ChatScreen(id: 'chat'));
    await tester.longPress(find.text('Xin chào'));
    await tester.pumpAndSettle();
    expect(find.byType(TPopoverAnchor), findsOneWidget);
    expect(find.text('Chuyển tiếp'), findsOneWidget);
    expect(find.text('Trích dẫn'), findsOneWidget);
    await tester.tap(find.text('Chọn'));
    await tester.pumpAndSettle();
    expect(find.byType(TPopoverAnchor), findsNothing);
    expect(find.text('Hủy'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('conversation swipe exposes unread hide and delete', (
    tester,
  ) async {
    await mount(tester, FakeClient(), const HomeScreen());
    await tester.drag(
      find.byType(QChatConversationTile),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TSwipeCellAction), findsNWidgets(3));
    expect(find.text('Đánh dấu chưa đọc'), findsOneWidget);
    expect(find.text('Ẩn'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
    'cleared messages cannot return from confirmed cache and newer messages survive',
    () async {
      final client = FakeClient();
      client.confirmed['old'] = {
        'id': 'old',
        'clientId': 'old',
        'conversationId': 'chat',
        'sequence': 1,
      };
      client.confirmed['new'] = {
        'id': 'new',
        'clientId': 'new',
        'conversationId': 'chat',
        'sequence': 3,
      };
      await client.applyClearedSequence('chat', 2);
      await client.applyClearedSequence('chat', 0);
      expect(client.visibleMessages('chat', client.rows).map((m) => m['id']), [
        'new',
      ]);
    },
  );
}
