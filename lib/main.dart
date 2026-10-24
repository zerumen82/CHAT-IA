import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/chat_screen.dart';
import 'services/chat_service_ollama.dart';
import 'services/theme_service.dart';
import 'services/ollama_service.dart';
import 'services/model_catalog_service.dart';
import 'package:window_manager/window_manager.dart';

const _primarySeed = Color(0xFF5967D8);
const _secondarySeed = Color(0xFF15A6A0);

ThemeData _buildAppTheme(Brightness brightness) {
  final baseScheme = ColorScheme.fromSeed(
    seedColor: _primarySeed,
    brightness: brightness,
    contrastLevel: 0.15,
  );
  final accentScheme = ColorScheme.fromSeed(
    seedColor: _secondarySeed,
    brightness: brightness,
    contrastLevel: 0.15,
  );
  final colorScheme = baseScheme.copyWith(
    secondary: accentScheme.primary,
    onSecondary: accentScheme.onPrimary,
    secondaryContainer: accentScheme.primaryContainer,
    onSecondaryContainer: accentScheme.onPrimaryContainer,
  );
  final textTheme = const TextTheme(
    displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
    displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
    displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
    headlineLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
    headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
    headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
    titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    bodyLarge: TextStyle(fontSize: 16),
    bodyMedium: TextStyle(fontSize: 14),
    bodySmall: TextStyle(fontSize: 13),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    labelMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
  ).apply(
    bodyColor: colorScheme.onSurface,
    displayColor: colorScheme.onSurface,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      margin: const EdgeInsets.all(8),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    ),
    platform: TargetPlatform.windows,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
      },
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar y configurar pantalla completa en Windows
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();

    // Antes de cerrar, liberar la VRAM de los modelos cargados sin tocar el
    // servidor Ollama del usuario.
    try {
      await windowManager.setPreventClose(true);
      windowManager.addListener(_WindowCloseObserver());
    } catch (e) {
      // Si el sistema no permite interceptar el cierre, la app debe arrancar.
      debugPrint('No se pudo interceptar el cierre de la ventana: $e');
    }

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

  // Observer para liberar GPU al cerrar la app
  WidgetsBinding.instance.addObserver(_AppLifecycleObserver());

  runApp(const MyApp());
}

/// Libera la VRAM de Ollama antes de cerrar la ventana.
///
/// `setPreventClose` evita que el proceso muera antes de terminar la petición
/// de descarga del modelo, que es rápida y nunca bloquea el cierre más de 2 s.
class _WindowCloseObserver with WindowListener {
  bool _closing = false;

  @override
  void onWindowClose() async {
    if (_closing) return;
    _closing = true;

    try {
      await OllamaService.instance
          .unloadLoadedModels()
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // Cerrar siempre, aunque Ollama no responda.
    }

    try {
      await windowManager.destroy();
    } catch (e) {
      debugPrint('No se pudo cerrar la ventana: $e');
    }
  }
}

class _AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // Solo se detiene el Ollama que haya iniciado LightChat. Si lo inició el
      // usuario (lo normal), se deja en marcha: Ollama libera el modelo según
      // su propio `keep_alive`.
      OllamaService.instance.stopServer();
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeService()),
        ChangeNotifierProvider(create: (_) => ChatServiceOllama()),
        // `.value` evita que el provider destruya el singleton al desmontarse
        // el árbol (p. ej. en pruebas o al recrear la app).
        ChangeNotifierProvider.value(value: OllamaService.instance),
        ChangeNotifierProvider(create: (_) => ModelCatalogService()),
      ],
      child: Consumer<ThemeService>(builder: (context, themeService, _) {
        return MaterialApp(
          title: 'LightChat',
          theme: _buildAppTheme(Brightness.light),
          darkTheme: _buildAppTheme(Brightness.dark),
          themeMode: themeService.mode,
          home: const ChatScreen(),
        );
      }),
    );
  }
}
