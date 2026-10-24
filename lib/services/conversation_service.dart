import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/conversation.dart';
import '../models/message.dart';

/// Guarda las conversaciones en `SharedPreferences`.
///
/// Cada conversación tiene su propia clave para los mensajes; el índice solo
/// guarda título, fecha y número de mensajes. La escritura de mensajes se
/// codifica en un isolate porque puede incluir el texto de varios documentos.
class ConversationService {
  ConversationService._();

  static const String _indexKey = 'lightchat_conversations_v1';
  static const String _activeKey = 'lightchat_active_conversation_v1';
  static const String _messagesPrefix = 'lightchat_conversation_messages_v1_';

  static final Random _random = Random();
  static Timer? _messagesTimer;
  static Timer? _indexTimer;

  static String newId() {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final suffix = _random.nextInt(1 << 20).toRadixString(36);
    return '$stamp-$suffix';
  }

  static String _messagesKey(String id) => '$_messagesPrefix$id';

  static Future<List<ConversationSummary>> loadIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_indexKey);
      if (raw == null || raw.isEmpty) {
        return [];
      }
      final decoded = json.decode(raw);
      if (decoded is! List) {
        return [];
      }
      final conversations = decoded
          .whereType<Map<String, dynamic>>()
          .map(ConversationSummary.fromJson)
          .where((conversation) => conversation.id.isNotEmpty)
          .toList();
      conversations.sort(
        (first, second) => second.updatedAt.compareTo(first.updatedAt),
      );
      return conversations;
    } catch (error) {
      debugPrint('Error cargando conversaciones: $error');
      return [];
    }
  }

  static Future<void> saveIndex(
    List<ConversationSummary> conversations,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = json.encode(
        conversations.map((conversation) => conversation.toJson()).toList(),
      );
      await prefs.setString(_indexKey, encoded);
    } catch (error) {
      debugPrint('Error guardando conversaciones: $error');
    }
  }

  static void saveIndexDebounced(List<ConversationSummary> conversations) {
    _indexTimer?.cancel();
    final snapshot = List<ConversationSummary>.of(conversations);
    _indexTimer = Timer(
      const Duration(milliseconds: 400),
      () => saveIndex(snapshot),
    );
  }

  static Future<void> flushIndex(
    List<ConversationSummary> conversations,
  ) async {
    _indexTimer?.cancel();
    _indexTimer = null;
    await saveIndex(conversations);
  }

  static Future<String?> loadActiveId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_activeKey);
    } catch (error) {
      debugPrint('Error cargando conversación activa: $error');
      return null;
    }
  }

  static Future<void> saveActiveId(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_activeKey, id);
    } catch (error) {
      debugPrint('Error guardando conversación activa: $error');
    }
  }

  static Future<List<Message>> loadMessages(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_messagesKey(id));
      if (raw == null || raw.isEmpty) {
        return [];
      }
      final decoded = json.decode(raw);
      if (decoded is! List) {
        return [];
      }
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(Message.fromJson)
          .toList();
    } catch (error) {
      debugPrint('Error cargando mensajes de $id: $error');
      return [];
    }
  }

  static Future<void> saveMessages(String id, List<Message> messages) async {
    if (id.isEmpty) return;
    try {
      // Copia defensiva: el historial se muta mientras se genera la respuesta.
      final messagesJson = List<Message>.of(messages)
          .map((message) => message.toJson())
          .toList();
      final encoded = await Isolate.run(() => json.encode(messagesJson));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_messagesKey(id), encoded);
    } catch (error) {
      debugPrint('Error guardando mensajes de $id: $error');
    }
  }

  static void saveMessagesDebounced(String id, List<Message> messages) {
    if (id.isEmpty) return;
    _messagesTimer?.cancel();
    final snapshot = List<Message>.of(messages);
    _messagesTimer = Timer(
      const Duration(milliseconds: 400),
      () => saveMessages(id, snapshot),
    );
  }

  static Future<void> flushMessages(String id, List<Message> messages) async {
    _messagesTimer?.cancel();
    _messagesTimer = null;
    await saveMessages(id, messages);
  }

  /// Escribe mensajes e índice sin esperar al debounce (cambio de chat, cierre).
  static Future<void> flushAll(
    String id,
    List<Message> messages,
    List<ConversationSummary> conversations,
  ) async {
    await flushMessages(id, messages);
    await flushIndex(conversations);
  }

  static Future<void> delete(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_messagesKey(id));
    } catch (error) {
      debugPrint('Error borrando la conversación $id: $error');
    }
  }

  static void cancelPendingSaves() {
    _messagesTimer?.cancel();
    _messagesTimer = null;
    _indexTimer?.cancel();
    _indexTimer = null;
  }
}
