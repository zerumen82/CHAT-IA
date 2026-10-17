import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ollama_service.dart';

/// Pantalla de gestión de Ollama
class OllamaManagerScreen extends StatefulWidget {
  const OllamaManagerScreen({super.key});

  @override
  State<OllamaManagerScreen> createState() => _OllamaManagerScreenState();
}

class _OllamaManagerScreenState extends State<OllamaManagerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ollamaService = context.read<OllamaService>();
      if (!ollamaService.isInitialized) {
        ollamaService.initialize();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Column(
        children: [
          _buildHeader(context),
          _buildStatusBar(),
          _buildTabs(context),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildModelsTab(),
                _buildInstalledTab(),
                _buildSettingsTab(),
                _buildLogsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colorScheme.primary.withValues(alpha: 0.15),
            colorScheme.surface,
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.smart_toy, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OLLAMA MANAGER',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  'Gestiona tus modelos locales',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Status bar con Consumer propio para no reconstruir el resto de la pantalla
  Widget _buildStatusBar() {
    return Consumer<OllamaService>(
      builder: (context, ollama, _) {
        final status = ollama.serverInfo.status;
        final isRunning = status == OllamaStatus.running;
        final colorScheme = Theme.of(context).colorScheme;
        final statusColor = isRunning ? Colors.green : colorScheme.error;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: statusColor.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.5),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isRunning ? 'Ollama ejecutándose' : 'Ollama no disponible',
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (ollama.serverInfo.version != null)
                      Text(
                        'Versión: ${ollama.serverInfo.version}',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (!isRunning)
                ElevatedButton.icon(
                  onPressed: () => ollama.checkInstallation(),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Verificar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: statusColor,
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabs(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: colorScheme.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        labelColor: colorScheme.onPrimary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        tabs: const [
          Tab(text: 'CATÁLOGO', icon: Icon(Icons.explore)),
          Tab(text: 'INSTALADOS', icon: Icon(Icons.download_done)),
          Tab(text: 'CONFIG', icon: Icon(Icons.settings)),
          Tab(text: 'LOGS', icon: Icon(Icons.terminal)),
        ],
      ),
    );
  }

  /// Catálogo de modelos con Consumer propio
  Widget _buildModelsTab() {
    return Consumer<OllamaService>(
      builder: (context, ollama, _) {
        final popularModels = OllamaService.popularModels;
        final colorScheme = Theme.of(context).colorScheme;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                onChanged: (value) =>
                    setState(() => _searchQuery = value.toLowerCase()),
                style: TextStyle(color: colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: 'Buscar modelo (ej: llama3, mistral, codellama)...',
                  hintStyle: TextStyle(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: popularModels.length,
                itemBuilder: (context, index) {
                  final model = popularModels[index];
                  final name = model['name'] as String;

                  if (_searchQuery.isNotEmpty &&
                      !name.toLowerCase().contains(_searchQuery)) {
                    return const SizedBox.shrink();
                  }

                  final isInstalled =
                      ollama.models.any((m) => m.name.startsWith(name));
                  final isPulling =
                      ollama.isPulling && ollama.pullingModel == name;

                  return _buildModelCard(
                    model,
                    isInstalled,
                    isPulling,
                    ollama,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildModelCard(
    Map<String, dynamic> model,
    bool isInstalled,
    bool isPulling,
    OllamaService ollama,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final name = model['name'] as String;
    final description = model['description'] as String;
    final tags =
        (model['tags'] as List<dynamic>?)?.cast<String>() ?? [];
    final size = model['size'] as String? ?? 'Unknown';
    final isMultimodal = model['multimodal'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isInstalled
              ? Colors.green.withValues(alpha: 0.3)
              : colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (isMultimodal) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.image,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (isInstalled)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check, color: Colors.green, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'INSTALADO',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...tags.map((tag) => Chip(
                    label: Text(
                      tag,
                      style: TextStyle(fontSize: 11),
                    ),
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    side: BorderSide.none,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  )),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.storage,
                size: 14,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 4),
              Text(
                size,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              if (isPulling)
                SizedBox(
                  width: 100,
                  child: LinearProgressIndicator(
                    value: ollama.pullProgress,
                    backgroundColor: colorScheme.outline.withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      colorScheme.primary,
                    ),
                  ),
                )
              else if (isInstalled)
                OutlinedButton.icon(
                  onPressed: () => _confirmDelete(name, ollama),
                  icon: const Icon(Icons.delete, size: 16),
                  label: const Text('Eliminar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.error,
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: () => _pullModel(name, ollama),
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Instalar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Modelos instalados con Consumer propio
  Widget _buildInstalledTab() {
    return Consumer<OllamaService>(
      builder: (context, ollama, _) {
        if (ollama.models.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 16),
                Text(
                  'No hay modelos instalados',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _tabController.animateTo(0),
                  child: const Text('Ir al catálogo'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: ollama.models.length,
          itemBuilder: (context, index) {
            final model = ollama.models[index];
            return _buildInstalledModelCard(model, ollama);
          },
        );
      },
    );
  }

  Widget _buildInstalledModelCard(OllamaModel model, OllamaService ollama) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.green.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.check_circle,
              color: Colors.green,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.name,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tamaño: ${model.sizeFormatted}',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
                if (model.modifiedAt != null)
                  Text(
                    'Actualizado: ${_formatDate(model.modifiedAt!)}',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _confirmDelete(model.name, ollama),
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: 'Eliminar',
          ),
        ],
      ),
    );
  }

  /// Configuración con Consumer propio
  Widget _buildSettingsTab() {
    return Consumer<OllamaService>(
      builder: (context, ollama, _) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSettingCard(
              context,
              icon: Icons.computer,
              title: 'Host',
              subtitle: 'Dirección del servidor Ollama',
              child: TextField(
                controller: TextEditingController(
                    text: ollama.serverInfo.port.toString()),
                enabled: false,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
                decoration: InputDecoration(
                  hintText: 'localhost:11434',
                  hintStyle: TextStyle(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildSettingCard(
              context,
              icon: Icons.terminal,
              title: 'Logs',
              subtitle: 'Registro de actividad',
              child: Container(
                height: 200,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  itemCount: ollama.logs.length,
                  itemBuilder: (context, index) {
                    return Text(
                      ollama.logs[index],
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildSettingCard(
              context,
              icon: Icons.info_outline,
              title: 'Información',
              subtitle: 'Detalles de Ollama',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow(
                      'Estado', _getStatusText(ollama.serverInfo.status)),
                  _buildInfoRow(
                      'Versión', ollama.serverInfo.version ?? 'Desconocida'),
                  _buildInfoRow(
                      'Puerto', ollama.serverInfo.port.toString()),
                  _buildInfoRow(
                      'Modelos', ollama.models.length.toString()),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Logs con Consumer propio
  Widget _buildLogsTab() {
    return Consumer<OllamaService>(
      builder: (context, ollama, _) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${ollama.logs.length} entradas de registro',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('Limpiar'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                color: colorScheme.surfaceContainerLow,
                child: ListView.builder(
                  itemCount: ollama.logs.length,
                  itemBuilder: (context, index) {
                    final line = ollama.logs[index];
                    return _buildConsoleLine(line);
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSettingCard(BuildContext context,
      {required IconData icon,
      required String title,
      required String subtitle,
      required Widget child}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pullModel(String name, OllamaService ollama) async {
    final success = await ollama.pullModel(name);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Modelo $name instalado correctamente'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _confirmDelete(String name, OllamaService ollama) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.surface,
        title: Text('Eliminar modelo', style: TextStyle(color: colorScheme.onSurface)),
        content: Text(
          '¿Estás seguro de que quieres eliminar "$name"?',
          style: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.error,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await ollama.deleteModel(name);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Modelo $name eliminado'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  String _getStatusText(OllamaStatus status) {
    switch (status) {
      case OllamaStatus.notInstalled:
        return 'No instalado';
      case OllamaStatus.installing:
        return 'Instalando';
      case OllamaStatus.installed:
        return 'Instalado';
      case OllamaStatus.starting:
        return 'Iniciando';
      case OllamaStatus.running:
        return 'Ejecutando';
      case OllamaStatus.stopping:
        return 'Deteniendo';
      case OllamaStatus.error:
        return 'Error';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Color _logLineColor(String line, ColorScheme colorScheme) {
    final lower = line.toLowerCase();
    if (lower.contains('error')) {
      return Colors.red.shade400;
    }
    if (lower.contains('warning')) {
      return Colors.orange.shade400;
    }
    if (lower.contains('info') ||
        lower.contains('starting') ||
        lower.contains('started')) {
      return Colors.blue.shade400;
    }
    if (lower.contains('success') ||
        lower.contains('ready')) {
      return Colors.green.shade400;
    }
    if (lower.contains('stderr')) {
      return Colors.yellow.shade400;
    }
    return colorScheme.onSurfaceVariant;
  }

  Widget _buildConsoleLine(String line) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Text(
        line,
        style: TextStyle(
          fontFamily: 'Courier',
          fontSize: 9,
          color: _logLineColor(line, colorScheme),
        ),
      ),
    );
  }
}
