import 'package:flutter/material.dart';
import '../models/local_model.dart';

/// Widget que muestra iconos de capacidades del modelo
class ModelCapabilityIcons extends StatelessWidget {
  final LocalModel model;
  final double iconSize;
  final Color? activeColor;
  final Color? inactiveColor;

  const ModelCapabilityIcons({
    super.key,
    required this.model,
    this.iconSize = 20,
    this.activeColor,
    this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = activeColor ?? theme.colorScheme.primary;
    final inactive = inactiveColor ?? theme.colorScheme.outline;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Texto / Chat
        _CapabilityIcon(
          icon: Icons.chat_bubble_outline,
          tooltip: 'Chat de texto',
          isActive: true, // Todos los modelos soportan texto
          activeColor: active,
          inactiveColor: inactive,
          size: iconSize,
        ),
        const SizedBox(width: 4),

        // Multimodal / Vision
        _CapabilityIcon(
          icon: Icons.image_outlined,
          tooltip: 'Visión / Multimodal',
          isActive: model.type == ModelType.multimodal || model.supportsImages,
          activeColor: active,
          inactiveColor: inactive,
          size: iconSize,
        ),
        const SizedBox(width: 4),

        // Embeddings
        _CapabilityIcon(
          icon: Icons.data_array,
          tooltip: 'Embeddings',
          isActive: model.type == ModelType.embedding,
          activeColor: active,
          inactiveColor: inactive,
          size: iconSize,
        ),
        const SizedBox(width: 4),

        // Uncensored
        _CapabilityIcon(
          icon: Icons.lock_open,
          tooltip: 'Sin censura',
          isActive: model.isUncensored,
          activeColor: active,
          inactiveColor: inactive,
          size: iconSize,
        ),
      ],
    );
  }
}

class _CapabilityIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final double size;

  const _CapabilityIcon({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Icon(
        icon,
        size: size,
        color: isActive ? activeColor : inactiveColor,
      ),
    );
  }
}

/// Widget extendido con etiquetas de capacidades
class ModelCapabilityChips extends StatelessWidget {
  final LocalModel model;

  const ModelCapabilityChips({
    super.key,
    required this.model,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        // Tipo de modelo
        _buildChip(
          context,
          label: _getTypeLabel(model.type),
          icon: _getTypeIcon(model.type),
          color: theme.colorScheme.primaryContainer,
        ),

        // Sin censura
        if (model.isUncensored)
          _buildChip(
            context,
            label: 'Sin censura',
            icon: Icons.lock_open,
            color: Colors.orange.withValues(alpha: 0.2),
          ),

        // Tamaño
        if (model.sizeFormatted != null)
          _buildChip(
            context,
            label: model.sizeFormatted!,
            icon: Icons.storage,
            color: theme.colorScheme.secondaryContainer,
          ),

        // Contexto máximo
        if (model.maxContext != null)
          _buildChip(
            context,
            label: '${model.maxContext!} ctx',
            icon: Icons.text_fields,
            color: theme.colorScheme.tertiaryContainer,
          ),
      ],
    );
  }

  Widget _buildChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  String _getTypeLabel(ModelType type) {
    switch (type) {
      case ModelType.multimodal:
        return 'Multimodal';
      case ModelType.embedding:
        return 'Embeddings';
      case ModelType.textOnly:
        return 'Texto';
    }
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

/// Indicador de requisitos de hardware
class ModelHardwareRequirements extends StatelessWidget {
  final LocalModel model;

  const ModelHardwareRequirements({
    super.key,
    required this.model,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (model.requiredRam != null)
          _RequirementRow(
            icon: Icons.memory,
            label: 'RAM mínima',
            value: '${model.requiredRam!.round()} GB',
          ),
        if (model.requiredVram != null)
          _RequirementRow(
            icon: Icons.videogame_asset,
            label: 'VRAM mínima',
            value: '${model.requiredVram!.round()} GB',
          ),
        if (model.sizeBytes != null)
          _RequirementRow(
            icon: Icons.storage,
            label: 'Espacio en disco',
            value: _formatBytes(model.sizeBytes!),
          ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
  }
}

class _RequirementRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _RequirementRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Spacer(),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}
