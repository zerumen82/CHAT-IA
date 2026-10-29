import 'context_plan.dart';
import '../services/context_profile_service.dart';
import '../services/ollama_service.dart';

class PreparedContext {
  final ContextPlan documents;
  final ModelContextProfile profile;
  final List<OllamaMessage> messages;
  final int responseTokens;
  final int documentBudgetChars;
  final int estimatedPromptTokens;
  final bool historyPartial;

  const PreparedContext({
    required this.documents,
    required this.profile,
    required this.messages,
    required this.responseTokens,
    required this.documentBudgetChars,
    required this.estimatedPromptTokens,
    required this.historyPartial,
  });
}
