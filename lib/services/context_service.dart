import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/message.dart';
import '../models/chat_message.dart';

/// Servicio para gestión de contexto conversacional
/// Simplificado para chat general (sin programación)
class ContextService {
  static const String _messagesKey = 'chat_messages';
  static const String _userLanguageKey = 'user_language';
  static const String _preferredModelKey = 'preferred_model';
  static const String _vllmServerKey = 'vllm_server_url';
  static const int _maxContextMessages = 20;
  static const int _maxHistoryMessages = 100;

  /// Detectar idioma automáticamente
  static String detectLanguage(String text) {
    final spanishWords = [
      'hola',
      'gracias',
      'por favor',
      'ayuda',
      'necesito',
      'quiero',
      'puedes',
      'español',
      'cómo',
      'qué',
      'cuándo',
      'dónde',
    ];
    final englishWords = [
      'hello',
      'thanks',
      'please',
      'help',
      'need',
      'want',
      'can you',
      'english',
      'how',
      'what',
      'when',
      'where',
    ];
    final frenchWords = [
      'bonjour',
      'merci',
      's\'il vous plaît',
      'aide',
      'besoin',
      'français',
      'comment',
      'quoi',
    ];
    final portugueseWords = [
      'olá',
      'obrigado',
      'por favor',
      'ajuda',
      'preciso',
      'português',
      'como',
      'que',
    ];

    final lowerText = text.toLowerCase();

    int spanishCount =
        spanishWords.where((word) => lowerText.contains(word)).length;
    int englishCount =
        englishWords.where((word) => lowerText.contains(word)).length;
    int frenchCount =
        frenchWords.where((word) => lowerText.contains(word)).length;
    int portugueseCount =
        portugueseWords.where((word) => lowerText.contains(word)).length;

    if (spanishCount >= englishCount &&
        spanishCount >= frenchCount &&
        spanishCount >= portugueseCount) {
      return 'español';
    } else if (englishCount >= frenchCount && englishCount >= portugueseCount) {
      return 'english';
    } else if (frenchCount >= portugueseCount) {
      return 'français';
    } else if (portugueseCount > 0) {
      return 'português';
    }

    return 'español'; // Por defecto español
  }

  /// Generar contexto inteligente para chat general
  static String generateContext(List<Message> messages, String userLanguage) {
    if (messages.isEmpty) return '';

    final recentMessages = messages.length > _maxContextMessages
        ? messages.sublist(messages.length - _maxContextMessages)
        : messages;

    final contextMessages =
        recentMessages.where((msg) => !msg.isError).toList();

    if (contextMessages.isEmpty) return '';

    String context = 'CONTEXTO DE LA CONVERSACIÓN ANTERIOR:\n\n';

    for (final msg in contextMessages) {
      context += '${msg.isUser ? "Usuario" : "Asistente"}: ${msg.text}\n\n';
    }

    context += 'INSTRUCCIONES IMPORTANTES:\n';
    context += '- Responde SIEMPRE en $userLanguage\n';
    context += '- Mantén la coherencia con el contexto anterior\n';
    context +=
        '- Si el usuario cambia de tema, adapta tu respuesta apropiadamente\n';
    context += '- Responde de manera natural y conversacional\n';
    context += '- Sé amigable y útil en cada respuesta\n\n';

    return context;
  }

  /// Generar contexto para ChatMessage (multimodal)
  static String generateContextFromChatMessages(
      List<ChatMessage> messages, String userLanguage) {
    if (messages.isEmpty) return '';

    final recentMessages = messages.length > _maxContextMessages
        ? messages.sublist(messages.length - _maxContextMessages)
        : messages;

    String context = 'CONTEXTO DE LA CONVERSACIÓN ANTERIOR:\n\n';

    for (final msg in recentMessages) {
      context += '${msg.isUser ? "Usuario" : "Asistente"}: ${msg.text}\n\n';
    }

    context += 'INSTRUCCIONES IMPORTANTES:\n';
    context += '- Responde SIEMPRE en $userLanguage\n';
    context += '- Mantén la coherencia con el contexto anterior\n';
    context += '- Responde de manera natural y conversacional\n\n';

    return context;
  }

  /// Seleccionar modelo automáticamente basado en el contenido
  /// Prioriza modelos uncensored
  static String selectOptimalModel(
      String text, List<String> availableModels, String userLanguage) {
    if (availableModels.isEmpty) return '';

    final lowerText = text.toLowerCase();

    // Detectar tipo de consulta
    bool isCreativeRequest = lowerText.contains('escribir') ||
        lowerText.contains('crear') ||
        lowerText.contains('historia') ||
        lowerText.contains('poema') ||
        lowerText.contains('cuento') ||
        lowerText.contains('write') ||
        lowerText.contains('create') ||
        lowerText.contains('story');

    bool isTechnicalRequest = lowerText.contains('técnico') ||
        lowerText.contains('algoritmo') ||
        lowerText.contains('matemática') ||
        lowerText.contains('ciencia') ||
        lowerText.contains('technical') ||
        lowerText.contains('math');

    bool isImageRequest = lowerText.contains('imagen') ||
        lowerText.contains('foto') ||
        lowerText.contains('ver') ||
        lowerText.contains('image') ||
        lowerText.contains('photo') ||
        lowerText.contains('picture');

    // Si hay solicitud de imagen, buscar modelo multimodal
    if (isImageRequest) {
      for (final model in availableModels) {
        final lowerModel = model.toLowerCase();
        if (lowerModel.contains('vision') ||
            lowerModel.contains('vl') ||
            lowerModel.contains('pixtral')) {
          return model;
        }
      }
    }

    // Priorizar modelos uncensored (Dolphin, Nous-Hermes, WizardLM)
    final uncensoredModels = [
      'dolphin',
      'openhermes',
      'nous-hermes',
      'wizardlm',
      'wizard',
      'uncensored',
    ];

    // Buscar modelo uncensored
    for (final uncensored in uncensoredModels) {
      for (final model in availableModels) {
        if (model.toLowerCase().contains(uncensored)) {
          // Para solicitudes creativas, preferir modelos más creativos
          if (isCreativeRequest && model.toLowerCase().contains('mistral')) {
            return model;
          }
          return model;
        }
      }
    }

    // Para solicitudes técnicas, preferir modelos más grandes
    if (isTechnicalRequest) {
      for (final model in availableModels) {
        final lowerModel = model.toLowerCase();
        if (lowerModel.contains('70b') ||
            lowerModel.contains('mixtral') ||
            lowerModel.contains('llama3')) {
          return model;
        }
      }
    }

    // Preferir modelos en español si están disponibles
    for (final model in availableModels) {
      if (userLanguage == 'español' &&
          model.toLowerCase().contains('spanish')) {
        return model;
      }
    }

    // Por defecto, usar el primer modelo disponible
    return availableModels.first;
  }

  /// Guardar mensajes en almacenamiento local
  static Future<void> saveMessages(List<Message> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesJson = messages.map((msg) => msg.toJson()).toList();
      await prefs.setString(_messagesKey, json.encode(messagesJson));
    } catch (e) {
      debugPrint('Error guardando mensajes: $e');
    }
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

  /// Guardar ChatMessages (multimodal)
  static Future<void> saveChatMessages(List<ChatMessage> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesJson = messages.map((msg) => msg.toJson()).toList();
      await prefs.setString(_messagesKey, json.encode(messagesJson));
    } catch (e) {
      debugPrint('Error guardando chat messages: $e');
    }
  }

  /// Cargar ChatMessages (multimodal)
  static Future<List<ChatMessage>> loadChatMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesString = prefs.getString(_messagesKey);

      if (messagesString != null) {
        final List<dynamic> messagesJson = json.decode(messagesString);
        return messagesJson.map((json) => ChatMessage.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint('Error cargando chat messages: $e');
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

  /// Guardar URL del servidor vLLM
  static Future<void> saveVllmServerUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_vllmServerKey, url);
    } catch (e) {
      debugPrint('Error guardando URL del servidor: $e');
    }
  }

  /// Cargar URL del servidor vLLM
  static Future<String> loadVllmServerUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_vllmServerKey) ?? 'http://localhost:8000';
    } catch (e) {
      debugPrint('Error cargando URL del servidor: $e');
      return 'http://localhost:8000';
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

  /// Limpiar historial antiguo de ChatMessages
  static List<ChatMessage> cleanOldChatHistory(List<ChatMessage> messages) {
    if (messages.length <= _maxHistoryMessages) return messages;

    const keepCount = _maxHistoryMessages ~/ 2;
    final recentMessages = messages.sublist(messages.length - keepCount);
    final olderMessages = messages.sublist(0, messages.length - keepCount);

    // Mantener mensajes importantes de la parte antigua
    final importantOlderMessages = olderMessages
        .where((msg) => !msg.isError && msg.text.length > 20)
        .take(keepCount)
        .toList();

    return [...importantOlderMessages, ...recentMessages];
  }

  /// Generar resumen del contexto para modelos con limitaciones
  static String generateContextSummary(List<Message> messages) {
    if (messages.length <= 5) return '';

    final userMessages = messages.where((msg) => msg.isUser).toList();
    String summary = 'RESUMEN DEL CONTEXTO:\n';
    summary += '- Total de intercambios: ${userMessages.length}\n';
    summary += '- Últimos temas discutidos: ';

    if (userMessages.isNotEmpty) {
      final lastTopics = userMessages.length > 3
          ? userMessages.sublist(userMessages.length - 3)
          : userMessages;
      final topicsText = lastTopics
          .map((msg) => msg.text.length > 50
              ? '${msg.text.substring(0, 50)}...'
              : msg.text)
          .join(', ');
      summary += topicsText;
    }

    summary +=
        '\n- El usuario prefiere respuestas en: ${detectLanguage(messages.isNotEmpty ? messages.last.text : '')}\n';

    return summary;
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
