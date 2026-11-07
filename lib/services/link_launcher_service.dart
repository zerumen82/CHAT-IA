import 'dart:io';

import 'web_search_service.dart';

/// Apertura de los enlaces que aparecen en las respuestas.
///
/// Los enlaces normales se abren con el navegador del sistema. Los `.onion`
/// solo existen dentro de la red Tor, así que un navegador convencional no
/// puede abrirlos: se ofrecen para Tor Browser cuando está instalado y activo.
class LinkLauncherService {
  LinkLauncherService({
    Future<bool> Function(String)? opener,
    String? torBrowserPath,
  })  : _opener = opener,
        _torBrowserPath = torBrowserPath;

  static final LinkLauncherService instance = LinkLauncherService();

  final Future<bool> Function(String)? _opener;
  String? _torBrowserPath;

  /// Un enlace es de la deep web cuando su host termina en `.onion`.
  static bool isOnion(String url) {
    final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
    return host.endsWith('.onion');
  }

  /// Solo se abren enlaces http/https; el modelo no puede inyectar otros esquemas.
  static bool isWebUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri != null &&
        (uri.isScheme('http') || uri.isScheme('https')) &&
        uri.host.isNotEmpty;
  }

  static final _hostChars = RegExp(r'^[a-z0-9.-]+$', caseSensitive: false);

  /// Devuelve la URL lista para abrir. Acepta hosts sin esquema
  /// ("www.ejemplo.com"), que el modelo escribe a veces, y descarta esquemas
  /// desconocidos o texto con espacios.
  static String? normalizeUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) {
      return null;
    }
    if (trimmed.contains('://')) {
      return isWebUrl(trimmed) ? trimmed : null;
    }
    final parsed = Uri.tryParse('https://$trimmed');
    if (parsed == null ||
        parsed.host.isEmpty ||
        !parsed.host.contains('.') ||
        !_hostChars.hasMatch(parsed.host)) {
      return null;
    }
    final scheme =
        parsed.host.toLowerCase().endsWith('.onion') ? 'http' : 'https';
    return '$scheme://$trimmed';
  }

  /// Convierte en enlaces los dominios que el modelo escribe a secas
  /// («amazon.es/dp/x», «abc.onion»): Markdown solo autoenlaza `http(s)://` y
  /// `www.`, así que sin esto el texto se ve pero no se puede pulsar.
  /// Respeta bloques de código, código en línea y enlaces ya escritos.
  static String linkifyMarkdown(String text) {
    if (!text.contains('.')) return text;
    return text.replaceAllMapped(_linkTokens, (Match match) {
      final groups = match as RegExpMatch;
      final raw = groups.namedGroup('url') ?? groups.namedGroup('bare');
      if (raw == null) return match[0]!;
      var candidate = raw;
      var trailing = '';
      while (candidate.isNotEmpty &&
          '.,;:!?'.contains(candidate[candidate.length - 1])) {
        trailing = '${candidate[candidate.length - 1]}$trailing';
        candidate = candidate.substring(0, candidate.length - 1);
      }
      final href = normalizeUrl(candidate);
      if (href == null) return match[0]!;
      return '[$candidate]($href)$trailing';
    });
  }

  static final _linkTokens = RegExp(
    r'(?<fence>```[\s\S]*?(?:```|$))'
    r'|(?<code>`[^`\n]*`)'
    r'|(?<markdown>!?\[[^\]\n]*\]\([^)\s]*\))'
    r'|(?<url>(?:https?://|www\.)[^\s<>()\[\]]+)'
    r'|(?<bare>(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+'
    r'(?:onion|com|org|net|es|io|co|ai|dev|app|info|me|tv|cc|gov|edu|uk|de|'
    r'fr|it|nl|ru|mx|ar|cl|br|eu|se|no|fi|pl|in|jp|cn|ca|au|ch|at|be|pt|gr|'
    r'cz|xyz|online|site|shop|store|news|blog|link|live|wiki)'
    r'(?::\d+)?(?:/[^\s<>()\[\]]*)?)',
    caseSensitive: false,
  );

  /// Abre el enlace con el navegador predeterminado del sistema.
  Future<bool> openExternal(String url) async {
    final opener = _opener;
    if (opener != null) {
      return opener(url);
    }
    try {
      if (Platform.isWindows) {
        await Process.start(
          'rundll32',
          <String>['url.dll,FileProtocolHandler', url],
          mode: ProcessStartMode.detached,
        );
      } else if (Platform.isMacOS) {
        await Process.start('open', <String>[url],
            mode: ProcessStartMode.detached);
      } else {
        await Process.start('xdg-open', <String>[url],
            mode: ProcessStartMode.detached);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Ruta del ejecutable de Tor Browser si está instalado.
  Future<String?> torBrowserPath() async {
    if (_torBrowserPath != null) {
      return _torBrowserPath;
    }
    for (final candidate in _candidates()) {
      if (await File(candidate).exists()) {
        _torBrowserPath = candidate;
        return candidate;
      }
    }
    return null;
  }

  /// Abre el enlace dentro de Tor Browser (necesita Tor ya conectado).
  Future<bool> openInTorBrowser(String url) async {
    final path = await torBrowserPath();
    if (path == null) {
      return false;
    }
    try {
      await Process.start(path, <String>[url],
          mode: ProcessStartMode.detached);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Comprueba si hay un proxy SOCKS5 de Tor escuchando en local.
  Future<bool> torRunning() async {
    for (final port in WebSearchService.torPorts) {
      try {
        final socket = await Socket.connect(
          '127.0.0.1',
          port,
          timeout: const Duration(milliseconds: 400),
        );
        await socket.close();
        return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  List<String> _candidates() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    if (Platform.isWindows) {
      final local = Platform.environment['LOCALAPPDATA'] ?? '';
      final programFiles =
          Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
      final programFilesX86 =
          Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
      return <String>[
        if (local.isNotEmpty) ...<String>[
          '$local\\Programs\\Tor Browser\\Browser\\firefox.exe',
          '$local\\Tor Browser\\Browser\\firefox.exe',
        ],
        if (home.isNotEmpty) '$home\\Desktop\\Tor Browser\\Browser\\firefox.exe',
        '$programFiles\\Tor Browser\\Browser\\firefox.exe',
        '$programFilesX86\\Tor Browser\\Browser\\firefox.exe',
      ];
    }
    if (Platform.isMacOS) {
      return <String>[
        '/Applications/Tor Browser.app/Contents/MacOS/firefox',
        if (home.isNotEmpty)
          '$home/Applications/Tor Browser.app/Contents/MacOS/firefox',
      ];
    }
    return <String>[
      if (home.isNotEmpty) ...<String>[
        '$home/tor-browser/Browser/firefox',
        '$home/.local/share/tor-browser/Browser/firefox',
      ],
      '/opt/tor-browser/Browser/firefox',
    ];
  }
}
