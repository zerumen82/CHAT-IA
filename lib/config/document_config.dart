/// Límites locales de extracción, almacenamiento y selección documental.
class DocumentConfig {
  DocumentConfig._();

  static const int maxFileBytes = 25 * 1024 * 1024;
  static const int maxExpandedZipBytes = 80 * 1024 * 1024;
  static const int maxZipEntryBytes = 32 * 1024 * 1024;
  static const int maxZipEntries = 2000;
  static const int maxExtractedChars = 2 * 1024 * 1024;
  static const int previewChars = 16000;
  static const int persistedPreviewChars = 2000;
  static const int maxRowsPerSheet = 10000;
  static const int maxColumnsPerRow = 200;
  static const int maxStoredBytes = 256 * 1024 * 1024;
  static const int maxDocuments = 100;
  static const int chunkChars = 1800;
  static const int maxChunksPerDocument = 1500;
  static const int minExcerptChars = 16;
  static const String rootPreferenceKey = 'lightchat_document_root_v1';
  static const String storeDirectoryName = '.lightchat-documents';
  static const String indexFileName = 'index.json';
  static const String contextPreamble =
      'DOCUMENTOS ADJUNTOS (cita el archivo y las referencias; si la cobertura '
      'es parcial no calcules totales globales ni inventes datos ausentes):';
  static const String partialWarning =
      'Cobertura parcial: se han seleccionado fragmentos; no representan '
      'necesariamente el documento completo.';
}
