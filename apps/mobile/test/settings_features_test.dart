import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/native.dart';
import 'package:qchat/app/providers.dart';
import 'package:qchat/core/storage/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'language, appearance and microphone preference survive restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = ProviderContainer();
      await first.read(preferencesProvider.notifier).ready;
      await first.read(preferencesProvider.notifier).language('en');
      await first.read(preferencesProvider.notifier).appearance(true);
      await first.read(preferencesProvider.notifier).muteOnJoin(true);
      first.dispose();
      final second = ProviderContainer();
      addTearDown(second.dispose);
      await second.read(preferencesProvider.notifier).ready;
      expect(second.read(preferencesProvider), (
        locale: 'en',
        dark: true,
        startMuted: true,
      ));
    },
  );
  test(
    'clear cache preserves queued messages and reports actual cache bytes',
    () async {
      final db = LocalDatabase.testing(NativeDatabase.memory());
      addTearDown(db.close);
      await db.cache('/users/me', {'nickname': 'Quyết'});
      await db.enqueue({
        'clientId': 'pending-1',
        'conversationId': 'chat',
        'text': 'Keep me',
      });
      final before = await db.cacheStats();
      expect(before.entries, 1);
      expect(before.bytes, greaterThan(0));
      expect(before.pending, 1);
      await db.clearReadCache();
      expect(await db.read('/users/me'), isNull);
      expect((await db.pending()).single['text'], 'Keep me');
      expect(await db.cacheStats(), (bytes: 0, entries: 0, pending: 1));
    },
  );
}
