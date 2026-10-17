import 'package:flutter/material.dart';
import '../models/local_model.dart';
import 'model_capability_icons.dart';

/// Tarjeta para mostrar información de un modelo y su descarga
class ModelDownloadCard extends StatelessWidget {
  final LocalModel model;
  final VoidCallback? onDownload;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;
  final VoidCallback? onSelect;
  final bool isSelected;
  final bool isDownloading;

  const ModelDownloadCard({
    super.key,
    required this.model,
    this.onDownload,
    this.onCancel,
    this.onDelete,
    this.onSelect,
    this.isSelected = false,
    this.isDownloading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isInstalled = model.isInstalled;

    return Card(
      elevation: isSelected ? 4 : 1,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: isInstalled ? onSelect : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header con nombre y estado
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (model.author != null)
                          Text(
                            model.author!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                      ],
                    ),
                  ),
                  _buildStatusChip(context),
                ],
              ),

              const SizedBox(height: 8),

              // Descripción
              if (model.description != null)
                Text(
                  model.description!,
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

              const SizedBox(height: 8),

              // Capacidades
              ModelCapabilityChips(model: model),

              const SizedBox(height: 8),

              // Requisitos de hardware
              ModelHardwareRequirements(model: model),

              // Progreso de descarga
              if (model.isDownloading) ...[
                const SizedBox(height: 12),
                _buildDownloadProgress(context),
              ],

              const SizedBox(height: 12),

              // Acciones
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context) {
    final theme = Theme.of(context);
    Color color;
    String label;
    IconData icon;

    switch (model.status) {
      case ModelStatus.ready:
        color = Colors.green;
        label = 'Instalado';
        icon = Icons.check_circle;
        break;
      case ModelStatus.downloading:
        color = theme.colorScheme.primary;
        label = 'Descargando';
        icon = Icons.downloading;
        break;
      case ModelStatus.installing:
        color = theme.colorScheme.primary;
        label = 'Instalando';
        icon = Icons.install_desktop;
        break;
      case ModelStatus.error:
        color = theme.colorScheme.error;
        label = 'Error';
        icon = Icons.error;
        break;
      case ModelStatus.updating:
        color = Colors.orange;
        label = 'Actualizando';
        icon = Icons.update;
        break;
      case ModelStatus.notInstalled:
        color = theme.colorScheme.outline;
        label = 'No instalado';
        icon = Icons.download;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadProgress(BuildContext context) {
    final theme = Theme.of(context);
    final progress = model.downloadProgress ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${(progress * 100).toStringAsFixed(1)}%',
              style: theme.textTheme.bodySmall,
            ),
            if (model.downloadSpeed != null)
              Text(
                '${model.downloadSpeed!.toStringAsFixed(1)} MB/s',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Botón de descarga
        if (model.status == ModelStatus.notInstalled && onDownload != null)
          FilledButton.icon(
            onPressed: onDownload,
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Descargar'),
          ),

        // Botón cancelar descarga
        if (model.isDownloading && onCancel != null)
          OutlinedButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.cancel, size: 18),
            label: const Text('Cancelar'),
          ),

        // Botón eliminar (si está instalado)
        if (model.isInstalled && onDelete != null)
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Eliminar modelo',
            color: theme.colorScheme.error,
          ),

        // Indicador de seleccionado
        if (model.isInstalled && isSelected)
          Icon(
            Icons.check_circle,
            color: theme.colorScheme.primary,
          ),
      ],
    );
  }
}

/// Tarjeta compacta para listas de modelos
class ModelDownloadCardCompact extends StatelessWidget {
  final LocalModel model;
  final VoidCallback? onTap;
  final bool isSelected;

  const ModelDownloadCardCompact({
    super.key,
    required this.model,
    this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      selected: isSelected,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(
          _getTypeIcon(model.type),
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(
        model.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: ModelCapabilityIcons(model: model, iconSize: 16),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
          : model.isInstalled
              ? const Icon(Icons.chevron_right)
              : _buildStatusBadge(context),
    );
  }

  Widget _buildStatusBadge(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        model.sizeFormatted ?? '',
        style: theme.textTheme.labelSmall,
      ),
    );
  }

  IconData _getTypeIcon(ModelType type) {
    switch (type) {
      case ModelType.multimodal:
        return Icons.image;
      case ModelType.embedding:
        return Icons.data_array;
      case ModelType.textOnly:
        return Icons.chat;
    }
  }
}
