import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/chat_screen.dart';
import 'services/chat_service_ollama.dart';
import 'services/theme_service.dart';
import 'services/ollama_service.dart';
import 'services/model_catalog_service.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar y configurar pantalla completa en Windows
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      center: true,
      skipTaskbar: false,
      title: 'LightChat',
      fullScreen: false,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      // Maximizar la ventana en lugar de usar fullScreen para preservar los controles
      await windowManager.show();
      await windowManager.maximize();
      await windowManager.focus();
    });
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeService()),
        ChangeNotifierProvider(create: (_) => ChatServiceOllama()),
        ChangeNotifierProvider(create: (_) => OllamaService.instance),
        ChangeNotifierProvider(create: (_) => ModelCatalogService()),
      ],
      child: Consumer<ThemeService>(builder: (context, themeService, _) {
        final lightTheme = ThemeData.light(useMaterial3: true).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          textTheme: const TextTheme(
            displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            headlineLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            titleSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            bodyLarge: TextStyle(fontSize: 16),
            bodyMedium: TextStyle(fontSize: 14),
            bodySmall: TextStyle(fontSize: 12),
            labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide.none,
            ),
          ),
          dialogTheme: DialogThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          platform: TargetPlatform.windows,
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
            },
          ),
        );

        final darkTheme = ThemeData.dark(useMaterial3: true).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          textTheme: const TextTheme(
            displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            headlineLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            titleSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            bodyLarge: TextStyle(fontSize: 16),
            bodyMedium: TextStyle(fontSize: 14),
            bodySmall: TextStyle(fontSize: 12),
            labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide.none,
            ),
          ),
          dialogTheme: DialogThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          platform: TargetPlatform.windows,
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
            },
          ),
        );

        return MaterialApp(
          title: 'LightChat',
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeService.mode,
          home: const ChatScreen(),
        );
      }),
    );
  }
}
