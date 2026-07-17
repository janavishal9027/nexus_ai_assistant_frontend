import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/kb_provider.dart';
import 'providers/backend_status_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/auth_screen.dart';
import 'screens/chat_screen.dart';
import 'services/api_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restore a saved backend URL before anything makes a request. On Android the
  // default `localhost` won't reach your PC — set it on the login screen to
  // `http://10.0.2.2:8080` (emulator) or your PC's LAN IP (physical device).
  await ApiService.loadBaseUrlFromPrefs();
  // Load appearance BEFORE the first frame, or the app paints its default dark
  // theme and then snaps to the user's — a visible flash on every launch.
  final settings = SettingsProvider();
  await settings.load();
  runApp(NexusAiApp(settings: settings));
}

/// Forui's theme, matched to the current brightness and accent so Forui widgets
/// (FButton, FCard, FTextField, …) track the user's Personalization choices.
/// Built per-change rather than once: it used to be a top-level `final` that was
/// always dark, which would have left the settings rail dark in light mode.
FThemeData _foruiTheme(Brightness brightness, Color accent) => FThemeData(
      touch: false,
      colors: (brightness == Brightness.dark ? FColors.zincDark : FColors.zincLight)
          .copyWith(primary: accent, primaryForeground: Colors.white),
    );

class NexusAiApp extends StatelessWidget {
  const NexusAiApp({super.key, required this.settings});

  final SettingsProvider settings;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..tryAutoLogin()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => KbProvider()),
        ChangeNotifierProvider(
            create: (_) => BackendStatusProvider()..start(), lazy: false),
        // Already loaded above, so the first frame is the user's theme.
        ChangeNotifierProvider.value(value: settings),
      ],
      // Consumer, not context.watch: this build context sits ABOVE the provider.
      child: Consumer<SettingsProvider>(
        builder: (context, s, _) => MaterialApp(
          title: 'Nexus AI',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(accent: s.accent),
          darkTheme: AppTheme.dark(accent: s.accent),
          themeMode: s.themeMode,
          // Forui: provide its theme + localizations app-wide so Forui widgets
          // render correctly on every route.
          localizationsDelegates: FLocalizations.localizationsDelegates,
          supportedLocales: FLocalizations.supportedLocales,
          builder: (context, child) => FTheme(
            // Theme.of() here resolves themeMode against the platform, so
            // "System" gives Forui the right brightness too.
            data: _foruiTheme(Theme.of(context).brightness, s.accent),
            child: child!,
          ),
          home: const _AuthGate(),
        ),
      ),
    );
  }
}

/// Routes to the auth screen or the chat app based on authentication state.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  int? _syncedFor;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    switch (auth.status) {
      case AuthStatus.unknown:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AuthStatus.unauthenticated:
        _syncedFor = null;
        return const AuthScreen();
      case AuthStatus.authenticated:
        // Adopt this account's appearance once per sign-in, so a second device
        // matches. Local settings already rendered; this only refines them.
        final id = auth.account?.id;
        if (id != null && _syncedFor != id) {
          _syncedFor = id;
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => context.read<SettingsProvider>().syncFromServer());
        }
        // Key by account id so logging in as a different user rebuilds the
        // chat screen and reloads that account's conversations.
        return ChatScreen(key: ValueKey(id));
    }
  }
}
