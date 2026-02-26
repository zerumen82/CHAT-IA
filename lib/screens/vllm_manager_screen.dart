import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/vllm_service.dart';
import '../services/model_catalog_service.dart';
import '../models/local_model.dart';

/// Pantalla de gestión de vLLM con estilo pixelado minimalista
class VllmManagerScreen extends StatefulWidget {
  const VllmManagerScreen({super.key});

  @override
  State<VllmManagerScreen> createState() => _VllmManagerScreenState();
}

class _VllmManagerScreenState extends State<VllmManagerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Consola flotante
  bool _showConsole = false;
  final ScrollController _consoleScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // Inicializar servicios (solo si no están ya inicializados)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vllmService = context.read<VllmService>();
      if (!vllmService.isInitialized) {
        vllmService.initialize();
      }
      context.read<ModelCatalogService>().refreshCatalog();
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
      body: Stack(
        children: [
          Column(
            children: [
              // Header pixelado
              _buildPixelHeader(),

              // Status bar
              _buildStatusBar(),

              // Tabs
              _buildPixelTabs(),

              // Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildModelsTab(),
                    _buildDownloadedTab(),
                    _buildServerTab(),
                  ],
                ),
              ),
            ],
          ),

          // Botón flotante de consola
          Positioned(
            bottom: 16,
            right: 16,
            child: _buildConsoleToggleButton(),
          ),

          // Consola flotante
          if (_showConsole) _buildFloatingConsole(),
        ],
      ),
    );
  }

  /// Botón para mostrar/ocultar consola
  Widget _buildConsoleToggleButton() {
    return Consumer<VllmService>(
      builder: (context, vllm, _) {
        // Solo mostrar si el servidor está corriendo o iniciando
        if (vllm.serverInfo.status != VllmStatus.running &&
            vllm.serverInfo.status != VllmStatus.starting) {
          return const SizedBox.shrink();
        }

        return GestureDetector(
          onTap: () {
            setState(() {
              _showConsole = !_showConsole;
            });
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _showConsole
                  ? const Color(0xFFe94560)
                  : const Color(0xFF16213e),
              border: Border.all(
                color: const Color(0xFF0f3460),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _showConsole ? Icons.terminal : Icons.terminal_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
        );
      },
    );
  }

  /// Consola flotante con stdout/stderr
  Widget _buildFloatingConsole() {
    return Consumer<VllmService>(
      builder: (context, vllm, _) {
        // Auto-scroll al final cuando llegan nuevos logs
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_consoleScrollController.hasClients) {
            _consoleScrollController.animateTo(
              _consoleScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
            );
          }
        });

        return Positioned(
          bottom: 70,
          right: 16,
          width: 400,
          height: 300,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0a0a14),
              border: Border.all(
                color: const Color(0xFFe94560),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                // Header de la consola
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF16213e),
                    border: Border(
                      bottom: BorderSide(color: Color(0xFF0f3460)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'CONSOLA vLLM',
                        style: TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 10,
                          color: Color(0xFFe94560),
                          letterSpacing: 2,
                        ),
                      ),
                      Row(
                        children: [
                          // Indicador de estado
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color:
                                  vllm.serverInfo.status == VllmStatus.running
                                      ? Colors.green
                                      : Colors.orange,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Botón cerrar
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _showConsole = false;
                              });
                            },
                            child: const Icon(
                              Icons.close,
                              color: Colors.white54,
                              size: 16,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Contenido de la consola
                Expanded(
                  child: Container(
                    color: const Color(0xFF050508),
                    child: ListView.builder(
                      controller: _consoleScrollController,
                      padding: const EdgeInsets.all(4),
                      itemCount: _parseConsoleLines(vllm.logs).length,
                      itemBuilder: (context, index) {
                        final line = _parseConsoleLines(vllm.logs)[index];
                        return _buildConsoleLine(line);
                      },
                    ),
                  ),
                ),

                // Footer con acciones
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF16213e),
                    border: Border(
                      top: BorderSide(color: Color(0xFF0f3460)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildPixelButton(
                        'COPIAR',
                        onPressed: () => _copyLogs(vllm.logs),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      _buildPixelButton(
                        'LIMPIAR',
                        onPressed: vllm.clearLogs,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Parsear líneas de consola
  List<String> _parseConsoleLines(String logs) {
    return logs.split('\n').where((line) => line.trim().isNotEmpty).toList();
  }

  /// Copiar logs al portapapeles
  void _copyLogs(String logs) {
    Clipboard.setData(ClipboardData(text: logs));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logs copiados al portapapeles'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Construir línea de consola con color según tipo
  Widget _buildConsoleLine(String line) {
    Color textColor = Colors.white54;

    // Colorear según tipo de mensaje
    if (line.contains('ERROR') ||
        line.contains('Error') ||
        line.contains('error')) {
      textColor = Colors.red.shade400;
    } else if (line.contains('WARNING') ||
        line.contains('Warning') ||
        line.contains('warning')) {
      textColor = Colors.orange.shade400;
    } else if (line.contains('INFO') ||
        line.contains('INFO:') ||
        line.contains('Starting') ||
        line.contains('Started')) {
      textColor = Colors.blue.shade400;
    } else if (line.contains('SUCCESS') ||
        line.contains('Success') ||
        line.contains('ready') ||
        line.contains('Ready')) {
      textColor = Colors.green.shade400;
    } else if (line.contains('stdout') || line.contains('STDOUT')) {
      textColor = Colors.white;
    } else if (line.contains('stderr') || line.contains('STDERR')) {
      textColor = Colors.yellow.shade400;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Text(
        line,
        style: TextStyle(
          fontFamily: 'Courier',
          fontSize: 9,
          color: textColor,
        ),
      ),
    );
  }

  /// Header pixelado minimalista
  Widget _buildPixelHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: const BoxDecoration(
        color: Color(0xFF16213e),
        border: Border(
          bottom: BorderSide(color: Color(0xFF0f3460), width: 2),
        ),
      ),
      child: Row(
        children: [
          // Logo pixelado
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFe94560),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Center(
              child: Text(
                'LC',
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'LIGHTCHAT',
            style: TextStyle(
              fontFamily: 'Courier',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFFe94560),
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          // Botón cerrar
          _buildPixelButton(
            'X',
            onPressed: () => Navigator.of(context).pop(),
            size: 28,
          ),
        ],
      ),
    );
  }

  /// Barra de estado del servidor
  Widget _buildStatusBar() {
    return Consumer<VllmService>(
      builder: (context, vllm, _) {
        final status = vllm.serverInfo.status;
        final statusColor = _getStatusColor(status);
        final statusText = _getStatusText(status);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0f3460),
            border: Border.all(color: statusColor, width: 1),
          ),
          child: Row(
            children: [
              // Indicador de estado
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 11,
                  color: Colors.white70,
                ),
              ),
              if (vllm.serverInfo.modelLoaded != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16213e),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    vllm.serverInfo.modelLoaded!,
                    style: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 10,
                      color: Color(0xFFe94560),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (vllm.serverInfo.version != null)
                Text(
                  'v${vllm.serverInfo.version}',
                  style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 10,
                    color: Colors.white38,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Tabs pixelados
  Widget _buildPixelTabs() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF16213e),
        border: Border(
          bottom: BorderSide(color: Color(0xFF0f3460), width: 2),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: const BoxDecoration(
          color: Color(0xFFe94560),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorWeight: 3,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white38,
        labelStyle: const TextStyle(
          fontFamily: 'Courier',
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
        tabs: const [
          Tab(text: 'MODELOS'),
          Tab(text: 'DESCARGADOS'),
          Tab(text: 'SERVIDOR'),
        ],
      ),
    );
  }

  /// Tab de catálogo de modelos
  Widget _buildModelsTab() {
    return Column(
      children: [
        // Barra de búsqueda
        Padding(
          padding: const EdgeInsets.all(12),
          child: _buildPixelSearchBar(
            controller: _searchController,
            onChanged: (value) {
              setState(() => _searchQuery = value);
            },
          ),
        ),

        // Filtro de hardware
        Consumer<VllmService>(
          builder: (context, vllm, _) {
            final hw = vllm.hardwareInfo;
            if (hw != null) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0f3460),
                  border: Border.all(color: const Color(0xFF16213e)),
                ),
                child: Row(
                  children: [
                    Icon(
                      hw.hasGPU ? Icons.videogame_asset : Icons.memory,
                      size: 14,
                      color: const Color(0xFFe94560),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hw.hasGPU
                            ? 'GPU: ${hw.gpuModel} (${hw.gpuVRAM}GB VRAM)'
                            : 'CPU: ${hw.cpuModel} (${hw.systemRAM}GB RAM)',
                        style: const TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 10,
                          color: Colors.white70,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildInfoChip('FILTRO ACTIVO',
                        color: const Color(0xFF4CAF50)),
                  ],
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
        const SizedBox(height: 8),

        // Lista de modelos
        Expanded(
          child: Consumer2<ModelCatalogService, VllmService>(
            builder: (context, catalog, vllm, _) {
              if (catalog.isLoading) {
                return const Center(
                  child: _PixelLoadingIndicator(),
                );
              }

              var models = catalog.cachedModels;

              // Filtrar por hardware disponible
              final hw = vllm.hardwareInfo;
              if (hw != null) {
                final availableVram = (hw.gpuVRAM ?? 0).toDouble();
                final availableRam = hw.systemRAM.toDouble();

                // Filtrar modelos que quepan en el hardware
                models = models.where((m) {
                  // Si tiene GPU, usar VRAM como límite
                  if (hw.hasGPU && availableVram > 0) {
                    if (m.requiredVram != null &&
                        m.requiredVram! > availableVram) {
                      return false;
                    }
                  } else {
                    // Sin GPU, usar RAM del sistema (con margen para SO)
                    final usableRam = availableRam - 4; // 4GB para SO
                    if (m.requiredRam != null && m.requiredRam! > usableRam) {
                      return false;
                    }
                    // Para modelos sin requiredRam, estimar por VRAM
                    if (m.requiredVram != null && m.requiredVram! > usableRam) {
                      return false;
                    }
                  }
                  return true;
                }).toList();
              }

              // Filtrar por búsqueda
              if (_searchQuery.isNotEmpty) {
                models = models.where((m) {
                  return m.id
                          .toLowerCase()
                          .contains(_searchQuery.toLowerCase()) ||
                      m.name.toLowerCase().contains(_searchQuery.toLowerCase());
                }).toList();
              }

              if (models.isEmpty) {
                return _buildEmptyState(
                  'No hay modelos compatibles con tu hardware',
                  icon: Icons.inventory_2_outlined,
                  subtitle: 'Intenta con una búsqueda diferente',
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: models.length,
                itemBuilder: (context, index) {
                  return _buildModelCard(models[index], vllm);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Tab de modelos descargados
  Widget _buildDownloadedTab() {
    return Consumer<VllmService>(
      builder: (context, vllm, _) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: vllm.scanModelsOnDisk(),
          builder: (context, snapshot) {
            final modelsOnDisk = snapshot.data ?? [];
            final registeredModels = vllm.downloadedModels;

            // Combinar modelos registrados y modelos en disco
            final allModels = <Widget>[];

            // Mostrar modelos en disco
            if (modelsOnDisk.isEmpty && registeredModels.isEmpty) {
              return _buildEmptyState(
                'No hay modelos descargados',
                icon: Icons.download_outlined,
                subtitle: 'Ve a la pestaña MODELOS para descargar',
              );
            }

            // Mostrar modelos parciales/fallidos primero
            final partialModels =
                modelsOnDisk.where((m) => m['isPartial'] == true).toList();
            final completeModels =
                modelsOnDisk.where((m) => m['isComplete'] == true).toList();

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // Modelos parciales/fallidos
                if (partialModels.isNotEmpty) ...[
                  _buildSectionTitle('DESCARGAS INCOMPLETAS'),
                  const SizedBox(height: 8),
                  ...partialModels.map((m) => _buildPartialModelCard(m, vllm)),
                  const SizedBox(height: 16),
                ],

                // Modelos completos
                if (completeModels.isNotEmpty) ...[
                  _buildSectionTitle('MODELOS DESCARGADOS'),
                  const SizedBox(height: 8),
                  ...completeModels.map((m) => _buildDiskModelCard(m, vllm)),
                ],

                // Botón para sincronizar
                const SizedBox(height: 16),
                Center(
                  child: _buildPixelButton(
                    'SINCRONIZAR',
                    onPressed: () => vllm.syncDownloadedModels(),
                    size: 28,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Tarjeta para modelo parcial/fallido
  Widget _buildPartialModelCard(Map<String, dynamic> model, VllmService vllm) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF16213e),
        border: Border.all(color: const Color(0xFFe94560)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFe94560).withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.warning,
                size: 18,
                color: Color(0xFFe94560),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model['name'] ?? 'Modelo desconocido',
                    style: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFe94560),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tamaño: ${model['sizeFormatted']} | Archivos: ${model['fileCount']}',
                    style: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 10,
                      color: Colors.white54,
                    ),
                  ),
                  const Text(
                    '⚠️ Descarga incompleta o fallida',
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 9,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
            _buildPixelButton(
              'ELIMINAR',
              onPressed: () => _deleteModelByPath(model['path'], vllm),
              color: const Color(0xFFf44336),
              size: 32,
            ),
          ],
        ),
      ),
    );
  }

  /// Tarjeta para modelo completo en disco
  Widget _buildDiskModelCard(Map<String, dynamic> model, VllmService vllm) {
    final isLoaded = vllm.serverInfo.modelLoaded != null &&
        model['name']
            .toString()
            .contains(vllm.serverInfo.modelLoaded!.replaceAll('/', '_'));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF16213e),
        border: Border.all(
          color: isLoaded ? const Color(0xFFe94560) : const Color(0xFF0f3460),
          width: isLoaded ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isLoaded ? const Color(0xFF4CAF50) : Colors.white24,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model['name'] ?? 'Modelo',
                    style: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '${model['sizeFormatted']} | ${model['fileCount']} archivos',
                    style: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 10,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
            if (isLoaded)
              _buildPixelButton(
                'STOP',
                onPressed: () => vllm.stopServer(),
                color: const Color(0xFFe94560),
                size: 32,
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPixelButton(
                    'RUN',
                    onPressed: vllm.serverInfo.status == VllmStatus.running
                        ? null
                        : () => _startServerFromPath(
                            model['path'], model['name'], vllm),
                    color: const Color(0xFF4CAF50),
                    size: 32,
                  ),
                  const SizedBox(width: 8),
                  _buildPixelButton(
                    'DEL',
                    onPressed: () => _deleteModelByPath(model['path'], vllm),
                    color: const Color(0xFFf44336),
                    size: 32,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Eliminar modelo por ruta
  Future<void> _deleteModelByPath(String path, VllmService vllm) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => _PixelConfirmDialog(
        title: 'ELIMINAR MODELO',
        message:
            '¿Eliminar este modelo del disco?\nEsta acción no se puede deshacer.',
      ),
    );

    if (confirm == true) {
      await vllm.deleteModelByPath(path);
    }
  }

  /// Iniciar servidor desde ruta
  Future<void> _startServerFromPath(
      String path, String name, VllmService vllm) async {
    // Crear un modelo temporal para iniciar
    final model = LocalModel(
      id: name,
      name: name,
      localPath: path,
      status: ModelStatus.ready,
    );
    await vllm.startServer(model);
  }

  /// Tab del servidor
  Widget _buildServerTab() {
    return Consumer<VllmService>(
      builder: (context, vllm, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Estado de instalación
              _buildSectionTitle('INSTALACIÓN'),
              const SizedBox(height: 8),
              _buildInstallationCard(vllm),

              const SizedBox(height: 24),

              // Hardware detectado
              _buildSectionTitle('HARDWARE'),
              const SizedBox(height: 8),
              _buildHardwareCard(vllm),

              const SizedBox(height: 24),

              // Almacenamiento de modelos
              _buildSectionTitle('ALMACENAMIENTO'),
              const SizedBox(height: 8),
              _buildStorageCard(vllm),

              const SizedBox(height: 24),

              // Logs
              _buildSectionTitle('LOGS'),
              const SizedBox(height: 8),
              _buildLogsCard(vllm),
            ],
          ),
        );
      },
    );
  }

  /// Tarjeta de información de almacenamiento
  Widget _buildStorageCard(VllmService vllm) {
    return FutureBuilder<Map<String, dynamic>>(
      future: vllm.getStorageInfo(),
      builder: (context, snapshot) {
        final data = snapshot.data ?? {};
        final totalSize = data['totalSizeFormatted'] ?? 'Calculando...';
        final modelCount = data['modelCount'] ?? 0;
        final path = data['path'] ?? 'No disponible';

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF16213e),
            border: Border.all(color: const Color(0xFF0f3460)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.folder,
                    size: 16,
                    color: Color(0xFFe94560),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Modelos: $modelCount | Tamaño: $totalSize',
                      style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 11,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(
                path,
                style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 9,
                  color: Colors.white38,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildPixelButton(
                    'ABRIR CARPETA',
                    onPressed: () => vllm.openModelsFolder(),
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  _buildPixelButton(
                    'ACTUALIZAR',
                    onPressed: () => setState(() {}),
                    size: 28,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Tarjeta de modelo en catálogo
  Widget _buildModelCard(LocalModel model, VllmService vllm) {
    final isDownloaded = vllm.downloadedModels.any((m) => m.id == model.id);
    final isDownloading = vllm.modelDownloading?.id == model.id;

    // Verificar compatibilidad con hardware
    final hw = vllm.hardwareInfo;
    bool isCompatible = true;
    String? compatibilityNote;

    if (hw != null) {
      if (hw.hasGPU && (hw.gpuVRAM ?? 0) > 0) {
        if (model.requiredVram != null &&
            model.requiredVram! > (hw.gpuVRAM ?? 0)) {
          isCompatible = false;
          compatibilityNote = 'Requiere ${model.requiredVram!.toInt()}GB VRAM';
        }
      } else {
        final usableRam = hw.systemRAM - 4;
        if (model.requiredVram != null && model.requiredVram! > usableRam) {
          isCompatible = false;
          compatibilityNote = 'Requiere ${model.requiredVram!.toInt()}GB RAM';
        }
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF16213e),
        border: Border.all(
          color: isCompatible
              ? const Color(0xFF0f3460)
              : const Color(0xFFe94560).withOpacity(0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Icono de tipo
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: model.supportsImages
                    ? const Color(0xFF533483)
                    : const Color(0xFF0f3460),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                model.supportsImages ? Icons.image : Icons.text_fields,
                size: 18,
                color: Colors.white70,
              ),
            ),
            const SizedBox(width: 12),

            // Info del modelo
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.name,
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isCompatible ? Colors.white : Colors.white54,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Tamaño destacado
                  Row(
                    children: [
                      if (model.sizeFormatted != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFe94560).withOpacity(0.3),
                            border: Border.all(color: const Color(0xFFe94560)),
                          ),
                          child: Text(
                            model.sizeFormatted!,
                            style: const TextStyle(
                              fontFamily: 'Courier',
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFe94560),
                            ),
                          ),
                        ),
                      const SizedBox(width: 4),
                      if (model.requiredVram != null)
                        _buildInfoChip('${model.requiredVram!.toInt()}GB VRAM'),
                      if (model.isUncensored)
                        _buildInfoChip('UNCENSORED',
                            color: const Color(0xFF4CAF50)),
                    ],
                  ),
                  if (compatibilityNote != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '⚠️ $compatibilityNote',
                      style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 9,
                        color: Color(0xFFe94560),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Botón de descarga
            if (isDownloading)
              SizedBox(
                width: 70,
                child: Column(
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: vllm.downloadProgress,
                            strokeWidth: 3,
                            backgroundColor: Colors.white10,
                            color: const Color(0xFFe94560),
                          ),
                          Text(
                            '${(vllm.downloadProgress * 100).toInt()}%',
                            style: const TextStyle(
                              fontFamily: 'Courier',
                              fontSize: 8,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else if (isDownloaded)
              _buildPixelButton(
                'OK',
                color: const Color(0xFF4CAF50),
                size: 32,
              )
            else
              _buildPixelButton(
                'DL',
                onPressed:
                    isCompatible ? () => _downloadModel(model, vllm) : null,
                size: 32,
              ),
          ],
        ),
      ),
    );
  }

  /// Tarjeta de modelo descargado
  Widget _buildDownloadedModelCard(LocalModel model, VllmService vllm) {
    final isLoaded = vllm.serverInfo.modelLoaded == model.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF16213e),
        border: Border.all(
          color: isLoaded ? const Color(0xFFe94560) : const Color(0xFF0f3460),
          width: isLoaded ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Estado
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isLoaded ? const Color(0xFF4CAF50) : Colors.white24,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.name,
                    style: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (model.sizeFormatted != null)
                    Text(
                      model.sizeFormatted!,
                      style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 10,
                        color: Colors.white54,
                      ),
                    ),
                ],
              ),
            ),

            // Botones
            if (isLoaded)
              _buildPixelButton(
                'STOP',
                onPressed: () => vllm.stopServer(),
                color: const Color(0xFFe94560),
                size: 32,
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPixelButton(
                    'RUN',
                    onPressed: vllm.serverInfo.status == VllmStatus.running
                        ? null
                        : () => _startServer(model, vllm),
                    color: const Color(0xFF4CAF50),
                    size: 32,
                  ),
                  const SizedBox(width: 8),
                  _buildPixelButton(
                    'DEL',
                    onPressed: () => _deleteModel(model, vllm),
                    color: const Color(0xFFf44336),
                    size: 32,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Tarjeta de instalación
  Widget _buildInstallationCard(VllmService vllm) {
    final status = vllm.serverInfo.status;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16213e),
        border: Border.all(color: const Color(0xFF0f3460)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _getStatusColor(status),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _getStatusText(status),
                style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 12,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              _buildPixelButton(
                'REFRESCAR',
                onPressed: vllm.isCheckingInstallation
                    ? null
                    : () => _refreshVllm(vllm),
                size: 24,
              ),
            ],
          ),
          if (vllm.serverInfo.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              vllm.serverInfo.errorMessage!,
              style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 10,
                color: Color(0xFFe94560),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (status == VllmStatus.notInstalled)
            SizedBox(
              width: double.infinity,
              child: _buildPixelButton(
                'INSTALAR vLLM',
                onPressed: vllm.isCheckingInstallation
                    ? null
                    : () => _installVllm(vllm),
                isLarge: true,
              ),
            )
          else if (status == VllmStatus.installing)
            const Center(
              child: _PixelLoadingIndicator(),
            ),
        ],
      ),
    );
  }

  /// Tarjeta de hardware
  Widget _buildHardwareCard(VllmService vllm) {
    final hw = vllm.hardwareInfo;

    if (hw == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF16213e),
          border: Border.all(color: const Color(0xFF0f3460)),
        ),
        child: const Center(
          child: _PixelLoadingIndicator(),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16213e),
        border: Border.all(color: const Color(0xFF0f3460)),
      ),
      child: Column(
        children: [
          _buildHardwareRow('CPU', hw.cpuModel),
          const SizedBox(height: 8),
          _buildHardwareRow('CORES', '${hw.cpuCores}'),
          const SizedBox(height: 8),
          _buildHardwareRow('RAM', '${hw.systemRAM} GB'),
          if (hw.hasGPU) ...[
            const SizedBox(height: 8),
            _buildHardwareRow('GPU', hw.gpuModel ?? 'Unknown'),
            const SizedBox(height: 8),
            _buildHardwareRow('VRAM', '${hw.gpuVRAM ?? 0} GB'),
          ],
        ],
      ),
    );
  }

  Widget _buildHardwareRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Courier',
              fontSize: 10,
              color: Colors.white38,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: 'Courier',
              fontSize: 11,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Tarjeta de logs
  Widget _buildLogsCard(VllmService vllm) {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0a0a14),
        border: Border.all(color: const Color(0xFF0f3460)),
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              reverse: true,
              child: SelectableText(
                vllm.logs.isEmpty ? 'Sin logs...' : vllm.logs,
                style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 10,
                  color: Colors.white54,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildPixelButton(
                'COPIAR',
                onPressed: () {
                  // Copiar al portapapeles
                  Clipboard.setData(ClipboardData(text: vllm.logs));
                },
                size: 24,
              ),
              const SizedBox(width: 8),
              _buildPixelButton(
                'LIMPIAR',
                onPressed: vllm.clearLogs,
                size: 24,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Título de sección
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: 'Courier',
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: Colors.white38,
        letterSpacing: 2,
      ),
    );
  }

  /// Estado vacío
  Widget _buildEmptyState(String message, {IconData? icon, String? subtitle}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null)
            Icon(
              icon,
              size: 48,
              color: Colors.white24,
            ),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              fontFamily: 'Courier',
              fontSize: 12,
              color: Colors.white38,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 10,
                color: Colors.white24,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Barra de búsqueda pixelada
  Widget _buildPixelSearchBar({
    required TextEditingController controller,
    required void Function(String) onChanged,
  }) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFF0f3460),
        border: Border.all(color: const Color(0xFF16213e)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Icon(
            Icons.search,
            size: 16,
            color: Colors.white38,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 12,
                color: Colors.white,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'BUSCAR MODELO...',
                hintStyle: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 12,
                  color: Colors.white38,
                ),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                controller.clear();
                onChanged('');
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: Colors.white38,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Botón pixelado
  Widget _buildPixelButton(
    String text, {
    VoidCallback? onPressed,
    Color? color,
    double size = 36,
    bool isLarge = false,
  }) {
    final bgColor = color ?? const Color(0xFFe94560);
    final isDisabled = onPressed == null;

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: isLarge ? 40 : size,
        padding: EdgeInsets.symmetric(
          horizontal: isLarge ? 24 : 12,
          vertical: isLarge ? 8 : 4,
        ),
        decoration: BoxDecoration(
          color: isDisabled ? bgColor.withOpacity(0.3) : bgColor,
          border: Border.all(
            color: isDisabled ? Colors.white10 : Colors.white24,
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Courier',
              fontSize: isLarge ? 12 : (size < 30 ? 9 : 10),
              fontWeight: FontWeight.bold,
              color: isDisabled ? Colors.white38 : Colors.white,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }

  /// Chip de información
  Widget _buildInfoChip(String text, {Color? color}) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (color ?? const Color(0xFF0f3460)).withOpacity(0.5),
        border: Border.all(color: color ?? const Color(0xFF0f3460)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Courier',
          fontSize: 8,
          color: Colors.white70,
        ),
      ),
    );
  }

  /// Color según estado
  Color _getStatusColor(VllmStatus status) {
    switch (status) {
      case VllmStatus.notInstalled:
        return Colors.orange;
      case VllmStatus.installing:
        return Colors.blue;
      case VllmStatus.installed:
        return const Color(0xFF4CAF50);
      case VllmStatus.starting:
        return Colors.blue;
      case VllmStatus.running:
        return const Color(0xFF4CAF50);
      case VllmStatus.stopping:
        return Colors.orange;
      case VllmStatus.error:
        return const Color(0xFFe94560);
    }
  }

  /// Texto según estado
  String _getStatusText(VllmStatus status) {
    switch (status) {
      case VllmStatus.notInstalled:
        return 'NO INSTALADO';
      case VllmStatus.installing:
        return 'INSTALANDO...';
      case VllmStatus.installed:
        return 'INSTALADO';
      case VllmStatus.starting:
        return 'INICIANDO...';
      case VllmStatus.running:
        return 'EJECUTANDO';
      case VllmStatus.stopping:
        return 'DETENIENDO...';
      case VllmStatus.error:
        return 'ERROR';
    }
  }

  /// Descargar modelo
  Future<void> _downloadModel(LocalModel model, VllmService vllm) async {
    await vllm.downloadModel(model, onProgress: () {
      // Forzar actualización de UI
      setState(() {});
    });
  }

  /// Iniciar servidor con modelo
  Future<void> _startServer(LocalModel model, VllmService vllm) async {
    await vllm.startServer(model);
  }

  /// Eliminar modelo
  Future<void> _deleteModel(LocalModel model, VllmService vllm) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => _PixelConfirmDialog(
        title: 'ELIMINAR MODELO',
        message: '¿Eliminar ${model.name}?\nEsta acción no se puede deshacer.',
      ),
    );

    if (confirm == true) {
      await vllm.deleteModel(model);
    }
  }

  /// Instalar vLLM
  Future<void> _installVllm(VllmService vllm) async {
    await vllm.installVllm(onProgress: () {
      setState(() {});
    });
  }

  /// Refrescar detección de vLLM
  Future<void> _refreshVllm(VllmService vllm) async {
    await vllm.checkVllmInstallation();
    setState(() {});
  }
}

/// Indicador de carga pixelado
class _PixelLoadingIndicator extends StatelessWidget {
  const _PixelLoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Color(0xFFe94560),
      ),
    );
  }
}

/// Diálogo de confirmación pixelado
class _PixelConfirmDialog extends StatelessWidget {
  final String title;
  final String message;

  const _PixelConfirmDialog({
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF16213e),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFe94560), width: 2),
        borderRadius: BorderRadius.circular(0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFFe94560),
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 11,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0f3460),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Text(
                      'CANCELAR',
                      style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 11,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFe94560),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Text(
                      'CONFIRMAR',
                      style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 11,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
