/// Límites de presentación y persistencia de borradores.
class UiConfig {
  static const sidebarBreakpoint = 720.0;
  static const sidebarWidth = 280.0;
  static const readingWidth = 960.0;
  static const bubbleWidth = 820.0;
  static const draftDebounceMs = 350;
  static const smallDraftChars = 4000;
  static const maxDraftBytes = 16 * 1024 * 1024;
  static const draftsPreferencePrefix = 'lightchat_draft_v1_';
  static const draftsDirectory = '.lightchat-drafts';
  static const applicationDataDirectory = 'LightChat';
  static const generationTick = Duration(seconds: 1);
  static const draftFlushTimeout = Duration(seconds: 5);
}
