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
  bool _filterUncensored = false;
  bool _filterMultimodal = false;
  bool _filterSmall = false;

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
      // Cargar modelos del catálogo online de Ollama
      ollamaService.fetchAvailableModels();
      // Cargar modelos instalados localmente
      ollamaService.checkInstallation();
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
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
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
                  'Gestor de Ollama',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Gestiona tus modelos locales',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
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
        final statusColor =
            isRunning ? colorScheme.tertiary : colorScheme.error;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.14),
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
                      isRunning
                          ? 'Ollama ejecutándose'
                          : 'Ollama no disponible',
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
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13,
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
                )
              else
                TextButton.icon(
                  onPressed: _freeGpu,
                  icon: const Icon(Icons.memory, size: 18),
                  label: const Text('Liberar GPU'),
                  style: TextButton.styleFrom(
                    foregroundColor: statusColor,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Descarga de la VRAM los modelos cargados, sin detener Ollama.
  Future<void> _freeGpu() async {
    final messenger = ScaffoldMessenger.of(context);
    final freed = await OllamaService.instance.unloadLoadedModels();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          freed == 0
              ? 'No había modelos cargados en la GPU'
              : '$freed modelo(s) liberados. Ollama sigue en marcha.',
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildTabs(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        labelPadding: const EdgeInsets.symmetric(horizontal: 12),
        indicator: BoxDecoration(
          color: colorScheme.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        labelColor: colorScheme.onPrimary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        tabs: const [
          Tab(text: 'Catálogo', icon: Icon(Icons.explore)),
          Tab(text: 'Instalados', icon: Icon(Icons.download_done)),
          Tab(text: 'Ajustes', icon: Icon(Icons.settings)),
          Tab(text: 'Registros', icon: Icon(Icons.terminal)),
        ],
      ),
    );
  }

  /// Catálogo de modelos disponibles para descargar desde Ollama
  Widget _buildModelsTab() {
    return Consumer<OllamaService>(
      builder: (context, ollama, _) {
        final colorScheme = Theme.of(context).colorScheme;
        final available = ollama.availableModels;
        final filtered = OllamaService.filterAvailableModels(
          models: available,
          query: _searchQuery,
          uncensoredOnly: _filterUncensored,
          multimodalOnly: _filterMultimodal,
          smallOnly: _filterSmall,
        );

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
                  labelText: 'Buscar modelos',
                  hintText: 'Ej.: llama3, mistral',
                  hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                  prefixIcon: Icon(
                    Icons.search,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  suffixIcon: IconButton(
                    icon: ollama.isLoadingAvailableModels
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    tooltip: 'Actualizar catálogo desde ollama.com',
                    onPressed: () async {
                      if (!ollama.isLoadingAvailableModels) {
                        await ollama.fetchAvailableModels(forceRefresh: true);
                      }
                      if (mounted) setState(() {});
                    },
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('Menos censura'),
                    selected: _filterUncensored,
                    onSelected: (selected) =>
                        setState(() => _filterUncensored = selected),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Multimodal'),
                    selected: _filterMultimodal,
                    onSelected: (selected) =>
                        setState(() => _filterMultimodal = selected),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Pequeños (≤8B)'),
                    selected: _filterSmall,
                    onSelected: (selected) =>
                        setState(() => _filterSmall = selected),
                  ),
                ],
              ),
            ),
            if (_filterUncensored)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Muestra variantes Dolphin y modelos marcados como uncensored; el Llama original no se etiqueta así.',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),

            // Instalar modelo personalizado
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildCustomInstallCard(context, ollama),
            ),

            const SizedBox(height: 8),

            // Indicador de modelos disponibles
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.cloud_download,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${filtered.length} de ${available.length} modelo(s)',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (ollama.availableModelsLastUpdate != null) ...[
                    const SizedBox(width: 12),
                    Text(
                      'Actualizado ${_formatRelativeTime(ollama.availableModelsLastUpdate!)}',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 8),

            if (ollama.availableModelsError != null && available.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.wifi_off, color: colorScheme.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No se pudo actualizar; mostrando modelos anteriores.',
                            style: TextStyle(
                              color: colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            Expanded(
              child: available.isEmpty
                  ? _buildCatalogEmptyState(ollama, colorScheme)
                  : filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No hay modelos que coincidan con la búsqueda y los filtros.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final model = filtered[index];
                            final name = model['name'] as String;

                            final isInstalled =
                                ollama.models.any((m) => m.name == name);
                            final isPulling =
                                ollama.isPulling && ollama.pullingModel == name;

                            return _buildAvailableModelCard(
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

  Widget _buildCatalogEmptyState(
    OllamaService ollama,
    ColorScheme colorScheme,
  ) {
    final isLoading = ollama.isLoadingAvailableModels;
    final error = ollama.availableModelsError;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const CircularProgressIndicator()
            else
              Icon(
                error == null ? Icons.cloud_download_outlined : Icons.wifi_off,
                size: 56,
                color: error == null ? colorScheme.primary : colorScheme.error,
              ),
            const SizedBox(height: 16),
            Text(
              isLoading
                  ? 'Cargando modelos oficiales de Ollama…'
                  : error == null
                      ? 'No hay modelos disponibles'
                      : 'No se pudo cargar el catálogo',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (!isLoading) ...[
              const SizedBox(height: 8),
              Text(
                error ??
                    'Comprueba la conexión a internet y vuelve a intentarlo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: ollama.isLoadingAvailableModels
                    ? null
                    : () => ollama.fetchAvailableModels(forceRefresh: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar catálogo'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Tarjeta de modelo disponible para descargar (del catálogo de ollama.com)
  Widget _buildAvailableModelCard(
    Map<String, dynamic> model,
    bool isInstalled,
    bool isPulling,
    OllamaService ollama,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final name = model['name'] as String;
    final description = model['description'] as String;
    final tags = (model['tags'] as List<dynamic>?)?.cast<String>() ?? [];
    final size = model['size'] as String? ?? 'Desconocido';
    final isMultimodal = model['multimodal'] == true;
    final isUncensored = model['uncensored'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isInstalled
              ? colorScheme.tertiary.withValues(alpha: 0.55)
              : colorScheme.outlineVariant,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isMultimodal
                        ? colorScheme.primary.withValues(alpha: 0.15)
                        : colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isMultimodal
                          ? colorScheme.primary.withValues(alpha: 0.3)
                          : colorScheme.outline.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Icon(
                    isMultimodal ? Icons.image : Icons.smart_toy,
                    size: 24,
                    color: isMultimodal
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          ..._buildModelBadges(
                            isMultimodal,
                            isUncensored,
                            isInstalled,
                            colorScheme,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (tags.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...tags.map((tag) {
                    final tagLower = tag.toLowerCase();
                    Color tagColor;
                    if (tagLower.contains('uncensored')) {
                      tagColor = colorScheme.secondary;
                    } else if (tagLower.contains('vision') ||
                        tagLower.contains('multimodal') ||
                        tagLower.contains('llava')) {
                      tagColor = colorScheme.primary;
                    } else if (RegExp(r'\d+b').hasMatch(tag)) {
                      tagColor = colorScheme.secondary;
                    } else {
                      tagColor = colorScheme.onSurfaceVariant;
                    }
                    return Chip(
                      label: Text(
                        tag,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: tagColor,
                        ),
                      ),
                      backgroundColor: tagColor.withValues(alpha: 0.1),
                      side: BorderSide.none,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    );
                  }),
                ],
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  Icons.storage,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    size,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (isPulling)
                  SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(
                      value: ollama.pullProgress,
                      backgroundColor: colorScheme.outline.withValues(
                        alpha: 0.2,
                      ),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorScheme.primary,
                      ),
                      minHeight: 4,
                    ),
                  )
                else if (isInstalled)
                  OutlinedButton.icon(
                    onPressed: () => _confirmDelete(name, ollama),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Eliminar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      side: BorderSide(
                        color: colorScheme.error.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  )
                else
                  FilledButton.icon(
                    onPressed: () => _pullModel(name, ollama),
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Instalar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Formatear tiempo relativo (ej: "hace 5 minutos")
  String _formatRelativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inHours < 1) return 'hace ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'hace ${diff.inHours} h';
    return 'hace ${diff.inDays} días';
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
                  color: Theme.of(context).colorScheme.outline,
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
    final isMultimodal = model.name.toLowerCase().contains('llava') ||
        model.name.toLowerCase().contains('vision');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.tertiary.withValues(alpha: 0.55),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: colorScheme.tertiary.withValues(alpha: 0.45),
                ),
              ),
              child: Icon(
                isMultimodal ? Icons.image : Icons.check_circle,
                color: colorScheme.onTertiaryContainer,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          model.name,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (isMultimodal) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.image,
                                size: 12,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Visión',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.storage,
                        size: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Tamaño: ${model.sizeFormatted}',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  if (model.modifiedAt != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 14,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.6,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Actualizado: ${_formatDate(model.modifiedAt!)}',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _confirmDelete(model.name, ollama),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Eliminar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.error,
                side: BorderSide(
                  color: colorScheme.error.withValues(alpha: 0.5),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
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
                        color: colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                        fontSize: 12,
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
                    onPressed: () => ollama.clearLogs(),
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
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 14,
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
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
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
          backgroundColor: Theme.of(context).colorScheme.tertiary,
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
        title: Text('Eliminar modelo',
            style: TextStyle(color: colorScheme.onSurface)),
        content: Text(
          '¿Estás seguro de que quieres eliminar "$name"?',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
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
            backgroundColor: colorScheme.tertiary,
          ),
        );
      }
    }
  }

  /// Construye los badges de estado del modelo (visión, sin censura, instalado/disponible)
  List<Widget> _buildModelBadges(
    bool isMultimodal,
    bool isUncensored,
    bool isInstalled,
    ColorScheme colorScheme,
  ) {
    final badges = <Widget>[];

    if (isMultimodal) {
      badges.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.image,
                size: 12,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                'Visión',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (isUncensored) {
      badges.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_open,
                size: 12,
                color: colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 4),
              Text(
                'Menos censura',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
      );
    }

    badges.add(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isInstalled
              ? colorScheme.tertiaryContainer
              : colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isInstalled ? Icons.check_circle : Icons.cloud_download,
              size: 12,
              color: isInstalled
                  ? colorScheme.onTertiaryContainer
                  : colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 4),
            Text(
              isInstalled ? 'Instalado' : 'Disponible',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isInstalled
                    ? colorScheme.onTertiaryContainer
                    : colorScheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );

    return badges;
  }

  /// Campo para instalar un modelo personalizado (ej: dolphin3:8b)
  Widget _buildCustomInstallCard(BuildContext context, OllamaService ollama) {
    final colorScheme = Theme.of(context).colorScheme;
    final controller = TextEditingController();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.add_circle_outline,
                color: colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Instalar modelo personalizado',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            style: TextStyle(color: colorScheme.onSurface),
            decoration: InputDecoration(
              labelText: 'Nombre y etiqueta del modelo',
              hintText: 'Ej.: dolphin3:8b',
              hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
              prefixIcon: Icon(
                Icons.model_training,
                color: colorScheme.onSurfaceVariant,
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (value) async {
              final name = value.trim();
              if (name.isEmpty) return;
              await _pullModel(name, ollama);
              controller.clear();
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Escribe el nombre completo del modelo (con tag, ej: :8b) y presiona Enter',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
      return colorScheme.error;
    }
    if (lower.contains('warning')) {
      return colorScheme.secondary;
    }
    if (lower.contains('info') ||
        lower.contains('starting') ||
        lower.contains('started')) {
      return colorScheme.primary;
    }
    if (lower.contains('success') || lower.contains('ready')) {
      return colorScheme.tertiary;
    }
    if (lower.contains('stderr')) {
      return colorScheme.error;
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
          fontSize: 12,
          color: _logLineColor(line, colorScheme),
        ),
      ),
    );
  }
}
