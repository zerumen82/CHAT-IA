import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/message.dart';

/// Servicio para gestión de contexto conversacional
/// Simplificado para chat general (sin programación)
class ContextService {
  static const String _messagesKey = 'chat_messages';
  static const String _userLanguageKey = 'user_language';
  static const String _preferredModelKey = 'preferred_model';
  static const String _ollamaServerKey = 'ollama_server_url';
  static const int _maxHistoryMessages = 100;

  /// Timer para debounce de guardado de mensajes (evita escrituras frecuentes en disco)
  static Timer? _saveMessagesDebounceTimer;

  /// Palabras completas y frecuentes de cada idioma.
  ///
  /// Se comparan como palabras enteras (nunca como subcadenas) para no
  /// confundir, por ejemplo, "mission" con el español "mi" o "difference"
  /// con el francés "ce". El orden importa: en caso de empate gana el primero,
  /// y el español es el idioma por defecto del producto.
  static final Map<String, Set<String>> _languageWords = {
    'español': {
      'el',
      'la',
      'los',
      'las',
      'un',
      'una',
      'unos',
      'unas',
      'de',
      'del',
      'al',
      'que',
      'qué',
      'y',
      'o',
      'en',
      'es',
      'son',
      'está',
      'están',
      'estoy',
      'estás',
      'era',
      'fue',
      'por',
      'para',
      'con',
      'sin',
      'sobre',
      'entre',
      'desde',
      'hasta',
      'se',
      'le',
      'les',
      'lo',
      'su',
      'sus',
      'mi',
      'mis',
      'tu',
      'tus',
      'no',
      'sí',
      'si',
      'como',
      'más',
      'pero',
      'porque',
      'cuando',
      'dónde',
      'donde',
      'muy',
      'este',
      'esta',
      'esto',
      'estos',
      'estas',
      'ese',
      'esa',
      'eso',
      'yo',
      'tú',
      'él',
      'ella',
      'nosotros',
      'usted',
      'ellos',
      'ellas',
      'hay',
      'he',
      'has',
      'ha',
      'han',
      'puedo',
      'puedes',
      'puede',
      'quiero',
      'quieres',
      'dime',
      'dame',
      'cuánto',
      'cuántos',
      'cuál',
      'cómo',
      'quién',
      'necesito',
      'gracias',
      'hola',
      'buenos',
      'días',
      'tardes',
      'noches',
      'resumen',
      'analiza',
      'analizar',
      'documento',
      'documentos',
      'hoja',
      'datos',
      'archivo',
      'tabla',
      'ventas',
      'total',
      'suma',
      'compara',
      'explica',
      'responde',
      'según',
      'hace',
      'hacer',
      'tengo',
      'tiene',
      'bastante',
      'también',
      'solo',
    },
    'english': {
      'the',
      'of',
      'and',
      'is',
      'are',
      'was',
      'were',
      'to',
      'in',
      'on',
      'at',
      'for',
      'with',
      'without',
      'about',
      'between',
      'from',
      'this',
      'that',
      'these',
      'those',
      'it',
      'its',
      'you',
      'we',
      'they',
      'he',
      'she',
      'my',
      'your',
      'our',
      'their',
      'not',
      'no',
      'yes',
      'but',
      'very',
      'more',
      'can',
      'could',
      'would',
      'should',
      'do',
      'does',
      'did',
      'have',
      'has',
      'had',
      'what',
      'how',
      'when',
      'where',
      'why',
      'which',
      'who',
      'me',
      'please',
      'thanks',
      'thank',
      'help',
      'need',
      'want',
      'give',
      'show',
      'summarize',
      'summarise',
      'analyze',
      'analyse',
      'document',
      'file',
      'sheet',
      'data',
      'table',
      'total',
      'compare',
      'explain',
      'according',
      'tell',
      'read',
      'extract',
      'row',
      'rows',
      'column',
      'value',
      'values',
    },
    'português': {
      'o',
      'os',
      'as',
      'um',
      'uma',
      'uns',
      'umas',
      'do',
      'da',
      'dos',
      'das',
      'ao',
      'no',
      'na',
      'nos',
      'nas',
      'que',
      'e',
      'é',
      'em',
      'para',
      'por',
      'com',
      'sem',
      'sobre',
      'entre',
      'não',
      'sim',
      'mais',
      'mas',
      'muito',
      'este',
      'esta',
      'isto',
      'esse',
      'essa',
      'isso',
      'eu',
      'você',
      'vocês',
      'ele',
      'ela',
      'nós',
      'eles',
      'elas',
      'sou',
      'são',
      'está',
      'estão',
      'tenho',
      'tem',
      'pode',
      'posso',
      'quero',
      'preciso',
      'obrigado',
      'obrigada',
      'olá',
      'bom',
      'boa',
      'dia',
      'tarde',
      'noite',
      'como',
      'onde',
      'quando',
      'qual',
      'quanto',
      'resumo',
      'planilha',
      'dados',
      'arquivo',
      'tabela',
      'vendas',
      'total',
      'soma',
      'compara',
      'explique',
      'segundo',
    },
    'français': {
      'le',
      'les',
      'des',
      'du',
      'au',
      'aux',
      'qui',
      'et',
      'est',
      'sont',
      'pour',
      'par',
      'avec',
      'sans',
      'sur',
      'entre',
      'ne',
      'pas',
      'plus',
      'mais',
      'très',
      'ce',
      'cette',
      'ces',
      'je',
      'tu',
      'vous',
      'nous',
      'ils',
      'elles',
      'mon',
      'ton',
      'son',
      'notre',
      'votre',
      'leur',
      'ai',
      'as',
      'avons',
      'avez',
      'ont',
      'suis',
      'sommes',
      'êtes',
      'besoin',
      'merci',
      'bonjour',
      'bonsoir',
      'comment',
      'où',
      'quand',
      'quel',
      'quelle',
      'combien',
      'résumé',
      'document',
      'feuille',
      'données',
      'fichier',
      'tableau',
      'ventes',
      'total',
      'somme',
      'compare',
      'explique',
      'selon',
      'fichiers',
      'ligne',
      'lignes',
    },
    'italiano': {
      'il',
      'lo',
      'gli',
      'di',
      'del',
      'della',
      'dei',
      'degli',
      'delle',
      'alla',
      'che',
      'e',
      'è',
      'per',
      'con',
      'senza',
      'su',
      'tra',
      'non',
      'sì',
      'più',
      'ma',
      'molto',
      'questo',
      'questa',
      'questi',
      'queste',
      'io',
      'noi',
      'voi',
      'loro',
      'sono',
      'sei',
      'siamo',
      'siete',
      'ho',
      'hai',
      'ha',
      'abbiamo',
      'avete',
      'hanno',
      'posso',
      'vuoi',
      'voglio',
      'bisogno',
      'grazie',
      'ciao',
      'buongiorno',
      'come',
      'dove',
      'quando',
      'quale',
      'quanto',
      'riassunto',
      'documento',
      'foglio',
      'dati',
      'file',
      'tabella',
      'vendite',
      'totale',
      'somma',
      'confronta',
      'spiega',
      'secondo',
    },
    'deutsch': {
      'der',
      'die',
      'das',
      'den',
      'dem',
      'des',
      'ein',
      'eine',
      'einen',
      'einem',
      'einer',
      'und',
      'ist',
      'sind',
      'war',
      'waren',
      'zu',
      'mit',
      'für',
      'von',
      'auf',
      'aus',
      'bei',
      'nicht',
      'nein',
      'ja',
      'aber',
      'sehr',
      'mehr',
      'ich',
      'du',
      'sie',
      'wir',
      'ihr',
      'mein',
      'dein',
      'unser',
      'brauche',
      'bitte',
      'danke',
      'hallo',
      'wie',
      'was',
      'wann',
      'wo',
      'warum',
      'welche',
      'welcher',
      'hilf',
      'hilfe',
      'zusammenfassen',
      'dokument',
      'tabelle',
      'datei',
      'daten',
      'blatt',
      'verkäufe',
      'summe',
      'vergleiche',
      'erkläre',
      'zeile',
      'zeilen',
    },
    'català': {
      'els',
      'les',
      'uns',
      'unes',
      'dels',
      'als',
      'i',
      'és',
      'en',
      'amb',
      'sense',
      'sobre',
      'entre',
      'no',
      'sí',
      'més',
      'però',
      'molt',
      'aquest',
      'aquesta',
      'aquests',
      'jo',
      'vostè',
      'nosaltres',
      'ells',
      'elles',
      'sóc',
      'són',
      'està',
      'estan',
      'tinc',
      'té',
      'puc',
      'vull',
      'necessito',
      'gràcies',
      'hola',
      'bon',
      'bona',
      'dia',
      'tarda',
      'nit',
      'com',
      'on',
      'quan',
      'quin',
      'quant',
      'resum',
      'full',
      'dades',
      'fitxer',
      'taula',
      'vendes',
      'total',
      'suma',
      'compara',
      'explica',
      'segons',
    },
    'galego': {
      'unha',
      'do',
      'da',
      'dos',
      'das',
      'ao',
      'no',
      'na',
      'nos',
      'nas',
      'que',
      'e',
      'é',
      'en',
      'para',
      'por',
      'con',
      'sen',
      'sobre',
      'entre',
      'non',
      'si',
      'máis',
      'pero',
      'moi',
      'este',
      'esta',
      'iso',
      'eu',
      'ti',
      'vostede',
      'somos',
      'está',
      'están',
      'teño',
      'ten',
      'podo',
      'preciso',
      'facer',
      'grazas',
      'ola',
      'onde',
      'cando',
      'cal',
      'canto',
      'resumo',
      'folla',
      'datos',
      'ficheiro',
      'táboa',
      'vendas',
      'total',
      'suma',
      'explica',
      'segundo',
    },
  };

  /// Palabras de 1–3 letras que aparecen en varios idiomas y solo añaden ruido.
  static const Set<String> _ambiguousShortWords = {'a', 'e', 'o', 'i', 'y'};

  static final RegExp _wordPattern = RegExp(r"[\p{L}\p{M}]+", unicode: true);

  /// Detectar idioma comparando palabras completas.
  static String detectLanguage(String text) {
    if (text.trim().isEmpty) return 'español';

    final tokens = _wordPattern
        .allMatches(text.toLowerCase())
        .map((match) => match.group(0)!)
        .where((token) => !_ambiguousShortWords.contains(token))
        .toList();
    if (tokens.isEmpty) return 'español';

    var detectedLanguage = 'español';
    var bestScore = 0;

    for (final entry in _languageWords.entries) {
      var score = 0;
      for (final token in tokens) {
        if (!entry.value.contains(token)) continue;
        score += 1;
        // Las palabras largas son más específicas del idioma.
        if (token.length > 4) score += 1;
        if (token.length > 8) score += 2;
      }
      if (score > bestScore) {
        bestScore = score;
        detectedLanguage = entry.key;
      }
    }

    return bestScore == 0 ? 'español' : detectedLanguage;
  }

  /// Guardar mensajes en almacenamiento local.
  ///
  /// La codificación JSON se hace en un isolate aparte porque el historial
  /// puede incluir el texto extraído de varios documentos (varios MB).
  static Future<void> saveMessages(List<Message> messages) async {
    try {
      // Copia defensiva: el historial se muta mientras se genera la respuesta.
      final messagesJson = List<Message>.of(messages)
          .map((message) => message.toJson())
          .toList();
      final encoded = await Isolate.run(() => json.encode(messagesJson));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_messagesKey, encoded);
    } catch (e) {
      debugPrint('Error guardando mensajes: $e');
    }
  }

  /// Guardar mensajes con debounce para no escribir en disco en cada token.
  static void saveMessagesDebounced(List<Message> messages) {
    _saveMessagesDebounceTimer?.cancel();
    _saveMessagesDebounceTimer =
        Timer(const Duration(milliseconds: 400), () async {
      await saveMessages(messages);
    });
  }

  /// Forzar escritura inmediata de mensajes pendientes (cancelar debounce).
  static Future<void> flushMessages(List<Message> messages) async {
    _saveMessagesDebounceTimer?.cancel();
    _saveMessagesDebounceTimer = null;
    await saveMessages(messages);
  }

  /// Cancelar cualquier guardado pendiente de debounce.
  static void cancelPendingSave() {
    _saveMessagesDebounceTimer?.cancel();
    _saveMessagesDebounceTimer = null;
  }

  /// Cargar mensajes desde almacenamiento local
  static Future<List<Message>> loadMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesString = prefs.getString(_messagesKey);

      if (messagesString != null) {
        final List<dynamic> messagesJson = json.decode(messagesString);
        return messagesJson.map((json) => Message.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint('Error cargando mensajes: $e');
    }

    return [];
  }

  /// Guardar idioma preferido del usuario
  static Future<void> saveUserLanguage(String language) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userLanguageKey, language);
    } catch (e) {
      debugPrint('Error guardando idioma: $e');
    }
  }

  /// Cargar idioma preferido del usuario
  static Future<String> loadUserLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_userLanguageKey) ?? 'español';
    } catch (e) {
      debugPrint('Error cargando idioma: $e');
      return 'español';
    }
  }

  /// Guardar modelo preferido
  static Future<void> savePreferredModel(String model) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_preferredModelKey, model);
    } catch (e) {
      debugPrint('Error guardando modelo: $e');
    }
  }

  /// Cargar modelo preferido
  static Future<String> loadPreferredModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_preferredModelKey) ?? '';
    } catch (e) {
      debugPrint('Error cargando modelo: $e');
      return '';
    }
  }

  /// Guardar URL del servidor Ollama
  static Future<void> saveOllamaServerUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_ollamaServerKey, url);
    } catch (e) {
      debugPrint('Error guardando URL del servidor: $e');
    }
  }

  /// Cargar URL del servidor Ollama
  static Future<String> loadOllamaServerUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_ollamaServerKey) ?? 'http://localhost:11434';
    } catch (e) {
      debugPrint('Error cargando URL del servidor: $e');
      return 'http://localhost:11434';
    }
  }

  /// Limpiar historial antiguo
  static List<Message> cleanOldHistory(List<Message> messages) {
    if (messages.length <= _maxHistoryMessages) return messages;

    const keepCount = _maxHistoryMessages ~/ 2;
    final recentMessages = messages.sublist(messages.length - keepCount);
    final olderMessages = messages.sublist(0, messages.length - keepCount);

    // Mantener mensajes importantes (no errores) de la parte antigua
    final importantOlderMessages = olderMessages
        .where((msg) => !msg.isError && msg.text.length > 20)
        .take(keepCount)
        .toList();

    return [...importantOlderMessages, ...recentMessages];
  }

  /// Limpiar todos los datos almacenados
  static Future<void> clearAllData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_messagesKey);
      await prefs.remove(_userLanguageKey);
      await prefs.remove(_preferredModelKey);
      // No eliminar la URL del servidor
    } catch (e) {
      debugPrint('Error limpiando datos: $e');
    }
  }
}
