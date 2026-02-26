import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/chat_screen.dart';
import 'services/chat_service.dart';
import 'services/theme_service.dart';
import 'services/vllm_service.dart';
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
        ChangeNotifierProvider(create: (_) => ChatService()),
        ChangeNotifierProvider(create: (_) => VllmService.instance),
        ChangeNotifierProvider(create: (_) => ModelCatalogService()),
      ],
      child: Consumer<ThemeService>(builder: (context, themeService, _) {
        return MaterialApp(
          title: 'LightChat',
          theme: ThemeData.light(useMaterial3: true).copyWith(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            platform: TargetPlatform.windows,
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
              },
            ),
          ),
          darkTheme: ThemeData.dark(useMaterial3: true),
          themeMode: themeService.mode,
          home: const ChatScreen(),
        );
      }),
    );
  }
}
