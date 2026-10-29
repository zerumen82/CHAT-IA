/// Estados observados por la app, sin deducir la fase interna de Ollama.
enum GenerationPhase {
  idle,
  preparing,
  waiting,
  thinking,
  responding,
  creatingFiles,
  saving,
}
