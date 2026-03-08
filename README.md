# LightChat

A lightweight chat interface for local LLMs powered by [Ollama](https://ollama.com).

## Features

- **Easy Setup**: Get started in seconds, not minutes
- **Local & Private**: All processing happens on your machine
- **Multimodal Support**: Chat with images (using vision models)
- **Model Management**: Download and manage models directly from the app
- **Cross-Platform**: Works on Windows, macOS, and Linux
- **Streaming Responses**: Real-time chat experience
- **Minimal Resource Usage**: Optimized for efficiency

## Requirements

- [Ollama](https://ollama.com) installed and running
- Windows 10/11, macOS 10.15+, or Linux
- 4GB+ RAM (8GB+ recommended)

## Installation

### 1. Install Ollama

Download and install Ollama from [ollama.com](https://ollama.com/download) or use the automatic installer:

```powershell
# Windows PowerShell
.\installer\install_ollama.ps1
```

### 2. Download LightChat

Download the latest release or build from source:

```bash
git clone https://github.com/yourusername/lightchat.git
cd lightchat
flutter pub get
flutter build windows  # or macos, linux
```

### 3. Run

Start Ollama:
```bash
ollama serve
```

Then launch LightChat and download your first model from the catalog!

## Recommended Models

| Model | Size | Best For |
|-------|------|----------|
| `llama3.2` | ~2GB | General chat, balanced |
| `mistral` | ~4GB | Fast, good reasoning |
| `phi3` | ~2GB | Quick responses |
| `llava` | ~4.5GB | Image understanding |
| `codellama` | ~4GB | Programming tasks |

## Screenshots

![Chat Interface](screenshots/chat.png)
![Model Manager](screenshots/models.png)

## Architecture

```
LightChat (Flutter)
    ↓
Ollama API (HTTP localhost:11434)
    ↓
Local LLM Models (GGUF format)
```

## Project Structure

```
lib/
├── main.dart                    # App entry point
├── config/
│   └── ollama_config.dart       # Configuration
├── models/
│   ├── chat_message.dart        # Message models
│   └── local_model.dart         # Model definitions
├── screens/
│   ├── chat_screen.dart         # Main chat UI
│   └── ollama_manager_screen.dart # Model management
├── services/
│   ├── ollama_service.dart      # Ollama API client
│   ├── chat_service_ollama.dart # Chat logic
│   └── context_service.dart     # Conversation context
└── widgets/
    ├── chat_input.dart          # Message input
    ├── message_bubble.dart      # Message display
    └── ollama_status_widget.dart # Connection status
```

## Development

### Prerequisites

- Flutter SDK 3.0+
- Dart SDK 3.0+

### Build

```bash
# Get dependencies
flutter pub get

# Run in debug mode
flutter run

# Build for release
flutter build windows  # Windows
flutter build macos    # macOS
flutter build linux    # Linux
```

## License

MIT License - See [LICENSE](LICENSE) for details

## Acknowledgments

- [Ollama](https://ollama.com) - Making local LLMs accessible
- [Flutter](https://flutter.dev) - UI framework
- All the open-source model creators

## Support

For issues related to:
- **LightChat**: Open an issue on GitHub
- **Ollama**: Visit [ollama.com](https://ollama.com) or [GitHub](https://github.com/ollama/ollama)
- **Models**: Check [ollama.com/library](https://ollama.com/library)

---

Made with ❤️ for the local AI community
