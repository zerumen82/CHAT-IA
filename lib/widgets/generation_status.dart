import 'dart:async';

import 'package:flutter/material.dart';

import '../config/ui_config.dart';
import '../models/generation_phase.dart';

class GenerationStatus extends StatefulWidget {
  final GenerationPhase phase;
  final DateTime? startedAt;
  final VoidCallback onStop;

  const GenerationStatus(
      {super.key,
      required this.phase,
      required this.startedAt,
      required this.onStop});

  @override
  State<GenerationStatus> createState() => _GenerationStatusState();
}

class _GenerationStatusState extends State<GenerationStatus> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(UiConfig.generationTick, (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (widget.phase) {
      GenerationPhase.idle => 'Actualizando conversación…',
      GenerationPhase.preparing => 'Preparando petición…',
      GenerationPhase.waiting => 'Esperando al modelo…',
      GenerationPhase.thinking => 'El modelo está razonando…',
      GenerationPhase.responding => 'Escribiendo respuesta…',
      GenerationPhase.creatingFiles => 'Creando archivos…',
      GenerationPhase.saving => 'Guardando conversación…',
    };
    final elapsed = widget.startedAt == null
        ? null
        : DateTime.now().difference(widget.startedAt!).inSeconds;
    final time = elapsed == null
        ? ''
        : elapsed < 60
            ? ' · ${elapsed}s'
            : ' · ${elapsed ~/ 60}m ${elapsed % 60}s';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            Text('$label$time', style: Theme.of(context).textTheme.bodySmall),
            if (widget.phase != GenerationPhase.idle &&
                widget.phase != GenerationPhase.saving)
              TextButton.icon(
                  onPressed: widget.onStop,
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text('Detener')),
          ]),
    );
  }
}
