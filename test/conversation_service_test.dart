import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lightchat/models/conversation.dart';
import 'package:lightchat/models/message.dart';
import 'package:lightchat/services/conversation_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saves, reorders and restores conversations', () async {
    final older = ConversationSummary(
      id: ConversationService.newId(),
      title: 'Antigua',
      updatedAt: DateTime(2026, 10, 1),
      messageCount: 1,
    );
    final newer = ConversationSummary(
      id: ConversationService.newId(),
      title: 'Reciente',
      updatedAt: DateTime(2026, 10, 20),
      messageCount: 0,
    );

    await ConversationService.saveIndex([older, newer]);
    await ConversationService.saveActiveId(newer.id);
    await ConversationService.saveMessages(older.id, [
      Message.text(
        text: 'Hola',
        isUser: true,
        timestamp: DateTime(2026, 10, 1),
      ),
    ]);

    final index = await ConversationService.loadIndex();
    expect(index.map((conversation) => conversation.title), [
      'Reciente',
      'Antigua',
    ]);
    expect(await ConversationService.loadActiveId(), newer.id);

    final messages = await ConversationService.loadMessages(older.id);
    expect(messages.single.text, 'Hola');
    expect(messages.single.isUser, isTrue);
  });

  test('deletes the messages of a conversation', () async {
    final id = ConversationService.newId();
    await ConversationService.saveMessages(id, [
      Message.text(
        text: 'Temporal',
        isUser: true,
        timestamp: DateTime(2026, 10, 1),
      ),
    ]);
    expect(await ConversationService.loadMessages(id), hasLength(1));

    await ConversationService.delete(id);
    expect(await ConversationService.loadMessages(id), isEmpty);
  });

  test('ignores a corrupt index instead of throwing', () async {
    SharedPreferences.setMockInitialValues({
      'lightchat_conversations_v1': 'esto no es json',
    });

    expect(await ConversationService.loadIndex(), isEmpty);
  });

  test('generates unique conversation ids', () {
    final ids = List.generate(50, (_) => ConversationService.newId()).toSet();
    expect(ids, hasLength(50));
  });
}
