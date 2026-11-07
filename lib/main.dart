import 'package:flutter/material.dart';

import 'screens/chat_screen.dart';
import 'services/settings_store.dart';

void main() => runApp(const KeyChatApp());

class KeyChatApp extends StatefulWidget {
  const KeyChatApp({super.key});

  @override
  State<KeyChatApp> createState() => _KeyChatAppState();
}

class _KeyChatAppState extends State<KeyChatApp> {
  final SettingsStore _store = SettingsStore();
  late final Future<AppSettings> _initial = _store.load();

  // Your color palette
  static const Color softPink = Color(0xFFFFF5F4);
  static const Color chartreuse = Color(0xFFB1D430);
  static const Color tealCyan = Color(0xFF1A8B9D);
  static const Color deepBlack = Color(0xFF000000);

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme = isDark
        ? ColorScheme.dark(
            primary: chartreuse,
            onPrimary: deepBlack,
            secondary: tealCyan,
            onSecondary: Colors.white,
            surface: const Color(0xFF121212),
            onSurface: softPink,
            primaryContainer: const Color(0xFF2A3410),
            onPrimaryContainer: chartreuse,
            secondaryContainer: const Color(0xFF0D3D45),
            onSecondaryContainer: softPink,
            outlineVariant: Colors.white24,
          )
        : ColorScheme.light(
            primary: tealCyan,
            onPrimary: Colors.white,
            secondary: chartreuse,
            onSecondary: deepBlack,
            surface: softPink,
            onSurface: deepBlack,
            primaryContainer: const Color(0xFFD4EEF2),
            onPrimaryContainer: const Color(0xFF0A3B43),
            secondaryContainer: const Color(0xFFEAF5B8),
            onSecondaryContainer: const Color(0xFF2E3800),
            outlineVariant: const Color(0xFFD8CFCF),
          );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.72),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: scheme.onSurface),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KeyChat',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: FutureBuilder<AppSettings>(
        future: _initial,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return ChatScreen(store: _store, initialSettings: snapshot.data!);
        },
      ),
    );
  }
}
