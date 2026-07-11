import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/kb_provider.dart';
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
  runApp(const NexusAiApp());
}

/// Forui dark theme, tinted to the app's brand teal so Forui widgets match the
/// existing Material-styled areas (built once, from zinc-dark's neutral palette).
final _foruiDarkTheme = FThemeData(
  touch: false,
  colors: FColors.zincDark.copyWith(
    primary: const Color(0xFF10A37F),
    primaryForeground: Colors.white,
  ),
);

class NexusAiApp extends StatelessWidget {
  const NexusAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..tryAutoLogin()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => KbProvider()),
      ],
      child: MaterialApp(
        title: 'Nexus AI',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        // Forui: provide its theme + localizations app-wide so Forui widgets
        // (FButton, FCard, FTextField, FScaffold, …) render correctly on every
        // route. Dark, neutral "zinc" scheme to match the app's dark UI.
        localizationsDelegates: FLocalizations.localizationsDelegates,
        supportedLocales: FLocalizations.supportedLocales,
        builder: (context, child) => FTheme(
          data: _foruiDarkTheme,
          child: child!,
        ),
        home: const _AuthGate(),
      ),
    );
  }
}

/// Routes to the auth screen or the chat app based on authentication state.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    switch (auth.status) {
      case AuthStatus.unknown:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AuthStatus.unauthenticated:
        return const AuthScreen();
      case AuthStatus.authenticated:
        // Key by account id so logging in as a different user rebuilds the
        // chat screen and reloads that account's conversations.
        return ChatScreen(key: ValueKey(auth.account?.id));
    }
  }
}
