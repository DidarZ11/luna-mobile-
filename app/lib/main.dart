import 'package:flutter/material.dart';

import 'api.dart';
import 'chat_screen.dart';
import 'chat_store.dart';
import 'settings.dart';
import 'voice.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  final store = await ChatStore.load();
  final api = LunaApi(settings);
  final voice = DeviceVoice(
    fetchVoice: api.tts,
    useServerVoice: () => settings.serverVoice,
  );
  runApp(LunaApp(settings: settings, store: store, api: api, voice: voice));
}

class LunaApp extends StatelessWidget {
  const LunaApp({
    super.key,
    required this.settings,
    required this.store,
    required this.api,
    required this.voice,
  });

  final AppSettings settings;
  final ChatStore store;
  final LunaApi api;
  final VoiceIO voice;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF8E9BC7),
      brightness: Brightness.dark,
      surface: const Color(0xFF10121C),
    );
    return MaterialApp(
      title: 'Луна',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      home: ChatScreen(
        settings: settings,
        store: store,
        api: api,
        voice: voice,
      ),
    );
  }
}
