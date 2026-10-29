/// Límites de transporte y preferencias de interacción local.
class ChatConfig {
  // La recarga de contexto grande puede superar dos minutos en esta máquina.
  static const connectionTimeout = Duration(minutes: 5);
  static const inactivityTimeout = Duration(minutes: 5);
  static const maxErrorBodyBytes = 4096;
  static const settingsPrefix = 'lightchat_chat_settings_v1_';
  static const continuePrompt =
      'Continúa la respuesta anterior desde donde terminó, sin repetir lo ya escrito.';
}
