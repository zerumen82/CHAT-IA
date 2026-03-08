import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    _tabController = TabController(length: 3, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: Column(
        children: [
          _buildHeader(),
          _buildStatusBar(),
          _buildTabs(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildModelsTab(),
                _buildInstalledTab(),
                _buildSettingsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF16213e),
            const Color(0xFF1a1a2e),
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.smart_toy, color: Color(0xFFe94560)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'OLLAMA MANAGER',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  'Gestiona tus modelos locales',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
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

  Widget _buildStatusBar() {
    return Consumer<OllamaService>(
      builder: (context, ollama, _) {
        final status = ollama.serverInfo.status;
        final isRunning = status == OllamaStatus.running;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isRunning
                ? Colors.green.withOpacity(0.1)
                : const Color(0xFF16213e),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isRunning
                  ? Colors.green.withOpacity(0.3)
                  : const Color(0xFFe94560).withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: isRunning ? Colors.green : const Color(0xFFe94560),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (isRunning ? Colors.green : const Color(0xFFe94560))
                          .withOpacity(0.5),
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
                        color: isRunning ? Colors.green : const Color(0xFFe94560),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (ollama.serverInfo.version != null)
                      Text(
                        'Versión: ${ollama.serverInfo.version}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
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
                    backgroundColor: const Color(0xFFe94560),
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF16213e),
        borderRadius: BorderRadius.circular(8),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: const Color(0xFFe94560),
          borderRadius: BorderRadius.circular(8),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white60,
        tabs: const [
          Tab(text: 'CATÁLOGO', icon: Icon(Icons.explore)),
          Tab(text: 'INSTALADOS', icon: Icon(Icons.download_done)),
          Tab(text: 'CONFIG', icon: Icon(Icons.settings)),
        ],
      ),
    );
  }

  Widget _buildModelsTab() {
    return Consumer<OllamaService>(
      builder: (context, ollama, _) {
        final popularModels = OllamaService.popularModels;

        return Column(
          children: [
            // Barra de búsqueda
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Buscar modelo (ej: llama3, mistral, codellama)...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                  prefixIcon: const Icon(Icons.search, color: Colors.white60),
                  filled: true,
                  fillColor: const Color(0xFF16213e),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            // Lista de modelos
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: popularModels.length,
                itemBuilder: (context, index) {
                  final model = popularModels[index];
                  final name = model['name'] as String;
                  
                  if (_searchQuery.isNotEmpty && !name.toLowerCase().contains(_searchQuery)) {
                    return const SizedBox.shrink();
                  }

                  final isInstalled = ollama.models.any((m) => m.name.startsWith(name));
                  final isPulling = ollama.isPulling && ollama.pullingModel == name;

                  return _buildModelCard(model, isInstalled, isPulling, ollama);
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
    final name = model['name'] as String;
    final description = model['description'] as String;
    final tags = (model['tags'] as List<dynamic>?)?.cast<String>() ?? [];
    final size = model['size'] as String? ?? 'Unknown';
    final isMultimodal = model['multimodal'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16213e),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isInstalled
              ? Colors.green.withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
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
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (isMultimodal) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.image,
                            size: 16,
                            color: Colors.blue.shade300,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (isInstalled)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, color: Colors.green, size: 14),
                      SizedBox(width: 4),
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
          // Tags
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...tags.map((tag) => Chip(
                    label: Text(
                      tag,
                      style: const TextStyle(fontSize: 11),
                    ),
                    backgroundColor: const Color(0xFF1a1a2e),
                    side: BorderSide.none,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  )),
            ],
          ),
          const SizedBox(height: 12),
          // Tamaño y botones
          Row(
            children: [
              Icon(
                Icons.storage,
                size: 14,
                color: Colors.white.withOpacity(0.5),
              ),
              const SizedBox(width: 4),
              Text(
                size,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              if (isPulling)
                SizedBox(
                  width: 100,
                  child: LinearProgressIndicator(
                    value: ollama.pullProgress,
                    backgroundColor: Colors.white.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      const Color(0xFFe94560),
                    ),
                  ),
                )
              else if (isInstalled)
                OutlinedButton.icon(
                  onPressed: () => _confirmDelete(name, ollama),
                  icon: const Icon(Icons.delete, size: 16),
                  label: const Text('Eliminar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFe94560),
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: () => _pullModel(name, ollama),
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Instalar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFe94560),
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

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
                  color: Colors.white.withOpacity(0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'No hay modelos instalados',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16213e),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.green.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tamaño: ${model.sizeFormatted}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 13,
                  ),
                ),
                if (model.modifiedAt != null)
                  Text(
                    'Actualizado: ${_formatDate(model.modifiedAt!)}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
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

  Widget _buildSettingsTab() {
    return Consumer<OllamaService>(
      builder: (context, ollama, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Configuración de host
            _buildSettingCard(
              icon: Icons.computer,
              title: 'Host',
              subtitle: 'Dirección del servidor Ollama',
              child: TextField(
                controller: TextEditingController(text: ollama.serverInfo.port.toString()),
                enabled: false,
                style: const TextStyle(color: Colors.white70),
                decoration: InputDecoration(
                  hintText: 'localhost:11434',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  filled: true,
                  fillColor: const Color(0xFF16213e),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Logs
            _buildSettingCard(
              icon: Icons.terminal,
              title: 'Logs',
              subtitle: 'Registro de actividad',
              child: Container(
                height: 200,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0d0d1a),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  itemCount: ollama.logs.length,
                  itemBuilder: (context, index) {
                    return Text(
                      ollama.logs[index],
                      style: TextStyle(
                        color: Colors.green.shade300,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Información
            _buildSettingCard(
              icon: Icons.info_outline,
              title: 'Información',
              subtitle: 'Detalles de Ollama',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow('Estado', _getStatusText(ollama.serverInfo.status)),
                  _buildInfoRow('Versión', ollama.serverInfo.version ?? 'Desconocida'),
                  _buildInfoRow('Puerto', ollama.serverInfo.port.toString()),
                  _buildInfoRow('Modelos', ollama.models.length.toString()),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSettingCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16213e),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFFe94560)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 13,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('Eliminar modelo', style: TextStyle(color: Colors.white)),
        content: Text(
          '¿Estás seguro de que quieres eliminar "$name"?',
          style: TextStyle(color: Colors.white.withOpacity(0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFe94560),
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
}
