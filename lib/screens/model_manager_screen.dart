import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/model_manager_service.dart';
import '../services/model_catalog_service.dart';
import '../services/hardware_detector_service.dart';
import '../models/local_model.dart';
import '../widgets/model_download_card.dart';

/// Pantalla de gestión de modelos
class ModelManagerScreen extends StatefulWidget {
  const ModelManagerScreen({super.key});

  @override
  State<ModelManagerScreen> createState() => _ModelManagerScreenState();
}

class _ModelManagerScreenState extends State<ModelManagerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Modelos'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.inventory_2), text: 'Instalados'),
            Tab(icon: Icon(Icons.cloud_download), text: 'Catálogo'),
            Tab(icon: Icon(Icons.computer), text: 'Hardware'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _refreshModels,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInstalledTab(),
          _buildCatalogTab(),
          _buildHardwareTab(),
        ],
      ),
    );
  }

  /// Tab de modelos instalados
  Widget _buildInstalledTab() {
    return Consumer<ModelManagerService>(
      builder: (context, manager, child) {
        final models = manager.installedModels.where((m) {
          if (_searchQuery.isEmpty) return true;
          return m.name.toLowerCase().contains(_searchQuery) ||
              m.id.toLowerCase().contains(_searchQuery);
        }).toList();

        return Column(
          children: [
            // Barra de búsqueda
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Buscar modelos instalados...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
              ),
            ),

            // Espacio usado
            FutureBuilder<int>(
              future: manager.getUsedSpace(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Espacio usado:',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        manager.formatSize(snapshot.data!),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const Divider(),

            // Lista de modelos
            Expanded(
              child: models.isEmpty
                  ? _buildEmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: 'No hay modelos instalados',
                      subtitle: 'Explora el catálogo para descargar modelos',
                    )
                  : ListView.builder(
                      itemCount: models.length,
                      itemBuilder: (context, index) {
                        final model = models[index];
                        return ModelDownloadCard(
                          model: model,
                          onDelete: () => _deleteModel(model),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  /// Tab de catálogo online
  Widget _buildCatalogTab() {
    return Consumer<ModelCatalogService>(
      builder: (context, catalog, child) {
        if (catalog.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (catalog.error != null) {
          return _buildErrorState(catalog.error!);
        }

        final models = catalog.cachedModels.where((m) {
          if (_searchQuery.isEmpty) return true;
          return m.name.toLowerCase().contains(_searchQuery) ||
              (m.description?.toLowerCase().contains(_searchQuery) ?? false);
        }).toList();

        return Column(
          children: [
            // Barra de búsqueda
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Buscar en catálogo...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
              ),
            ),

            // Filtros rápidos
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('Sin censura'),
                    selected: false,
                    onSelected: (selected) {
                      // TODO: Implementar filtro
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Multimodal'),
                    selected: false,
                    onSelected: (selected) {
                      // TODO: Implementar filtro
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Recomendados'),
                    selected: false,
                    onSelected: (selected) {
                      // TODO: Implementar filtro
                    },
                  ),
                ],
              ),
            ),

            const Divider(),

            // Lista de modelos
            Expanded(
              child: models.isEmpty
                  ? _buildEmptyState(
                      icon: Icons.cloud_off,
                      title: 'No se encontraron modelos',
                      subtitle: 'Intenta con otra búsqueda',
                    )
                  : ListView.builder(
                      itemCount: models.length,
                      itemBuilder: (context, index) {
                        final model = models[index];
                        return ModelDownloadCard(
                          model: model,
                          onDownload: () => _downloadModel(model),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  /// Tab de información de hardware
  Widget _buildHardwareTab() {
    return FutureBuilder<HardwareInfo>(
      future: HardwareDetectorService.getHardwareInfo(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final hardware = snapshot.data!;
        final theme = Theme.of(context);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // CPU
              _buildHardwareSection(
                context,
                title: 'Procesador',
                icon: Icons.memory,
                children: [
                  _buildInfoRow('Modelo', hardware.cpuModel),
                  _buildInfoRow('Núcleos', '${hardware.cpuCores}'),
                ],
              ),

              const SizedBox(height: 16),

              // RAM
              _buildHardwareSection(
                context,
                title: 'Memoria RAM',
                icon: Icons.storage,
                children: [
                  _buildInfoRow(
                    'Total',
                    '${hardware.systemRAM} GB',
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // GPU
              _buildHardwareSection(
                context,
                title: 'Tarjeta Gráfica',
                icon: Icons.videogame_asset,
                children: hardware.hasGPU
                    ? [
                        _buildInfoRow(
                            'Modelo', hardware.gpuModel ?? 'Desconocido'),
                        _buildInfoRow(
                          'VRAM',
                          hardware.gpuVRAM != null
                              ? '${hardware.gpuVRAM} GB'
                              : 'Desconocido',
                        ),
                      ]
                    : [
                        _buildInfoRow(
                          'Estado',
                          'No se detectó GPU dedicada',
                          valueColor: theme.colorScheme.outline,
                        ),
                      ],
              ),

              const SizedBox(height: 16),

              // Recomendaciones
              _buildHardwareSection(
                context,
                title: 'Modelos Recomendados',
                icon: Icons.recommend,
                children: [
                  Text(
                    'Basado en tu hardware, se recomiendan modelos de:',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: hardware.recommendedModels.map((model) {
                      return Chip(
                        label: Text(model),
                        backgroundColor: theme.colorScheme.primaryContainer,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHardwareSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline,
              size: 64, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16),
          Text(
            'Error al cargar modelos',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _refreshModels,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshModels() async {
    final manager = context.read<ModelManagerService>();
    final catalog = context.read<ModelCatalogService>();

    await Future.wait([
      catalog.refreshCatalog(),
      // manager.refreshInstalledModels(), // TODO: implementar este método
    ]);
  }

  Future<void> _downloadModel(LocalModel model) async {
    final manager = context.read<ModelManagerService>();
    final success = await manager.downloadModel(model);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${model.name} descargado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al descargar ${model.name}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _deleteModel(LocalModel model) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar modelo'),
        content: Text('¿Estás seguro de que quieres eliminar ${model.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final manager = context.read<ModelManagerService>();
      await manager.deleteModel(model);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${model.name} eliminado'),
          ),
        );
      }
    }
  }
}
