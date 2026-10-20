import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/network/client.dart';

final clientProvider = Provider<QChatClient>((ref) {
  final client = QChatClient();
  ref.onDispose(client.dispose);
  return client;
});

typedef AppPreferences = ({String locale, bool dark, bool startMuted});

class Preferences extends Notifier<AppPreferences> {
  late Future<void> ready;
  int revision = 0;
  Future<void> writes = Future.value();
  @override
  AppPreferences build() {
    ready = restore();
    return (locale: 'vi', dark: false, startMuted: false);
  }

  Future<void> restore() async {
    final version = revision;
    try {
      final saved = await SharedPreferences.getInstance();
      if (!ref.mounted || revision != version) return;
      final locale = saved.getString('qchat.locale') ?? 'vi';
      state = (
        locale: ['vi', 'en', 'zh'].contains(locale) ? locale : 'vi',
        dark: saved.getBool('qchat.dark') ?? false,
        startMuted: saved.getBool('qchat.startMuted') ?? false,
      );
    } catch (_) {
      // Defaults remain usable when device storage is unavailable.
    }
  }

  Future<void> save(AppPreferences next) {
    revision++;
    state = next;
    writes = writes.catchError((_) {}).then((_) async {
      final saved = await SharedPreferences.getInstance();
      await saved.setString('qchat.locale', next.locale);
      await saved.setBool('qchat.dark', next.dark);
      await saved.setBool('qchat.startMuted', next.startMuted);
    });
    return writes;
  }

  Future<void> language(String value) =>
      save((locale: value, dark: state.dark, startMuted: state.startMuted));
  Future<void> appearance(bool value) =>
      save((locale: state.locale, dark: value, startMuted: state.startMuted));
  Future<void> muteOnJoin(bool value) =>
      save((locale: state.locale, dark: state.dark, startMuted: value));
}

final preferencesProvider = NotifierProvider<Preferences, AppPreferences>(
  Preferences.new,
);
