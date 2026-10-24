/// Datos ligeros de una conversación guardada.
///
/// Los mensajes viven en su propia clave de almacenamiento, para que cambiar
/// de conversación no obligue a reescribir todo el historial.
class ConversationSummary {
  final String id;
  final String title;
  final DateTime updatedAt;
  final int messageCount;

  const ConversationSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messageCount,
  });

  ConversationSummary copyWith({
    String? id,
    String? title,
    DateTime? updatedAt,
    int? messageCount,
  }) {
    return ConversationSummary(
      id: id ?? this.id,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      messageCount: messageCount ?? this.messageCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'updatedAt': updatedAt.toIso8601String(),
      'messageCount': messageCount,
    };
  }

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    return ConversationSummary(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? defaultTitle,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      messageCount: json['messageCount'] as int? ?? 0,
    );
  }

  static const String defaultTitle = 'Conversación nueva';
}
