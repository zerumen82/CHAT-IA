import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/vllm_service.dart';
import '../screens/vllm_manager_screen.dart';

/// Widget minimalista pixelado para mostrar estado de vLLM y acceso rápido
class VllmStatusWidget extends StatelessWidget {
  final bool compact;

  const VllmStatusWidget({
    super.key,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<VllmService>(
      builder: (context, vllm, _) {
        final status = vllm.serverInfo.status;
        final isConnected = status == VllmStatus.running;

        if (compact) {
          return _buildCompactStatus(context, vllm, isConnected);
        }

        return _buildFullStatus(context, vllm, isConnected);
      },
    );
  }

  /// Estado compacto para AppBar
  Widget _buildCompactStatus(
      BuildContext context, VllmService vllm, bool isConnected) {
    final status = vllm.serverInfo.status;
    final statusColor = _getStatusColor(status);

    return GestureDetector(
      onTap: () => _openManager(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.2),
          border: Border.all(color: statusColor, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _getStatusLabel(status),
              style: TextStyle(
                fontFamily: 'Courier',
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: statusColor,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Estado completo para mostrar cuando no hay conexión
  Widget _buildFullStatus(
      BuildContext context, VllmService vllm, bool isConnected) {
    final status = vllm.serverInfo.status;
    final statusColor = _getStatusColor(status);

    return GestureDetector(
      onTap: () => _openManager(context),
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF16213e),
          border: Border.all(color: statusColor, width: 2),
          borderRadius: BorderRadius.circular(0),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.2),
                    border: Border.all(color: statusColor),
                  ),
                  child: Icon(
                    _getStatusIcon(status),
                    size: 18,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'vLLM ${_getStatusLabel(status)}',
                        style: const TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (vllm.serverInfo.modelLoaded != null)
                        Text(
                          vllm.serverInfo.modelLoaded!,
                          style: const TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 10,
                            color: Colors.white54,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                // Botón de acción
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Text(
                    'ABRIR',
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),

            // Mensaje de estado
            if (!isConnected && status != VllmStatus.installing) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0f3460),
                  border: Border.all(color: const Color(0xFF16213e)),
                ),
                child: Text(
                  _getStatusMessage(status),
                  style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 10,
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            // Progreso de instalación
            if (status == VllmStatus.installing) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(
                color: Color(0xFFe94560),
                backgroundColor: Color(0xFF0f3460),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Abrir gestor de vLLM
  void _openManager(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const VllmManagerScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  /// Color según estado
  Color _getStatusColor(VllmStatus status) {
    switch (status) {
      case VllmStatus.notInstalled:
        return Colors.orange;
      case VllmStatus.installing:
        return const Color(0xFF2196F3);
      case VllmStatus.installed:
        return const Color(0xFF4CAF50);
      case VllmStatus.starting:
        return const Color(0xFF2196F3);
      case VllmStatus.running:
        return const Color(0xFF4CAF50);
      case VllmStatus.stopping:
        return Colors.orange;
      case VllmStatus.error:
        return const Color(0xFFe94560);
    }
  }

  /// Icono según estado
  IconData _getStatusIcon(VllmStatus status) {
    switch (status) {
      case VllmStatus.notInstalled:
        return Icons.download;
      case VllmStatus.installing:
        return Icons.downloading;
      case VllmStatus.installed:
        return Icons.check_circle;
      case VllmStatus.starting:
        return Icons.play_arrow;
      case VllmStatus.running:
        return Icons.dns;
      case VllmStatus.stopping:
        return Icons.stop;
      case VllmStatus.error:
        return Icons.error;
    }
  }

  /// Etiqueta corta según estado
  String _getStatusLabel(VllmStatus status) {
    switch (status) {
      case VllmStatus.notInstalled:
        return 'NO INST';
      case VllmStatus.installing:
        return 'INSTALANDO';
      case VllmStatus.installed:
        return 'LISTO';
      case VllmStatus.starting:
        return 'INICIANDO';
      case VllmStatus.running:
        return 'ONLINE';
      case VllmStatus.stopping:
        return 'DETENIENDO';
      case VllmStatus.error:
        return 'ERROR';
    }
  }

  /// Mensaje descriptivo según estado
  String _getStatusMessage(VllmStatus status) {
    switch (status) {
      case VllmStatus.notInstalled:
        return 'Instala vLLM para comenzar a usar modelos locales';
      case VllmStatus.installing:
        return 'Instalando vLLM... Esto puede tardar varios minutos';
      case VllmStatus.installed:
        return 'vLLM instalado. Descarga un modelo para comenzar';
      case VllmStatus.starting:
        return 'Iniciando servidor...';
      case VllmStatus.running:
        return 'Servidor activo y funcionando';
      case VllmStatus.stopping:
        return 'Deteniendo servidor...';
      case VllmStatus.error:
        return 'Ha ocurrido un error. Revisa los logs para más detalles';
    }
  }
}

/// Indicador de conexión rápida para mostrar en el chat
class VllmQuickConnect extends StatelessWidget {
  const VllmQuickConnect({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VllmService>(
      builder: (context, vllm, _) {
        final status = vllm.serverInfo.status;
        final hasModels = vllm.downloadedModels.isNotEmpty;
        final isRunning = status == VllmStatus.running;
        final isStarting = status == VllmStatus.starting;

        // Si está corriendo, mostrar indicador verde
        if (isRunning) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1a3a1a),
              border: Border.all(
                color: const Color(0xFF4CAF50),
                width: 2,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.cloud_done,
                  size: 20,
                  color: Color(0xFF4CAF50),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'vLLM CONECTADO',
                        style: TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4CAF50),
                        ),
                      ),
                      if (vllm.serverInfo.modelLoaded != null)
                        Text(
                          vllm.serverInfo.modelLoaded!,
                          style: const TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 10,
                            color: Colors.white54,
                          ),
                        ),
                    ],
                  ),
                ),
                // Botón para detener
                GestureDetector(
                  onTap: () => vllm.stopServer(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFe94560),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Text(
                      'STOP',
                      style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Si está Instalado y hay modelos descargados, mostrar botón INICIAR
        if (status == VllmStatus.installed && hasModels) {
          final firstModel = vllm.downloadedModels.first;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF16213e),
              border: Border.all(
                color: const Color(0xFF4CAF50),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.cloud_queue,
                  size: 20,
                  color: Color(0xFF4CAF50),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'vLLM LISTO',
                        style: TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4CAF50),
                        ),
                      ),
                      Text(
                        firstModel.name,
                        style: const TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 10,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
                // Botón para iniciar
                GestureDetector(
                  onTap: isStarting
                      ? null
                      : () => vllm.startServer(firstModel),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isStarting ? Colors.grey : const Color(0xFF4CAF50),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      isStarting ? '...' : 'START',
                      style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Si está instalado pero sin modelos
        if (status == VllmStatus.installed && !hasModels) {
          return GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const VllmManagerScreen(),
                  fullscreenDialog: true,
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF16213e),
                border: Border.all(
                  color: const Color(0xFF4CAF50),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.download_done,
                    size: 20,
                    color: Color(0xFF4CAF50),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'vLLM instalado. Descarga un modelo para comenzar',
                      style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: Colors.white38,
                  ),
                ],
              ),
            ),
          );
        }

        // Si hay error
        if (status == VllmStatus.error) {
          return GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const VllmManagerScreen(),
                  fullscreenDialog: true,
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2a1a1a),
                border: Border.all(
                  color: const Color(0xFFe94560),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 20,
                    color: Color(0xFFe94560),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ERROR DE CONEXIÓN',
                          style: TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFe94560),
                          ),
                        ),
                        if (vllm.serverInfo.errorMessage != null)
                          Text(
                            vllm.serverInfo.errorMessage!,
                            style: const TextStyle(
                              fontFamily: 'Courier',
                              fontSize: 9,
                              color: Colors.white54,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: Colors.white38,
                  ),
                ],
              ),
            ),
          );
        }

        // Si no está instalado
        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const VllmManagerScreen(),
                fullscreenDialog: true,
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF16213e),
              border: Border.all(
                color: Colors.orange,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.cloud_off,
                  size: 20,
                  color: Colors.orange,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Instalar vLLM para usar modelos locales',
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 11,
                      color: Colors.white70,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: Colors.white38,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
