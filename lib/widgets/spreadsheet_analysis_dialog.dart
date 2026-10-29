import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/spreadsheet_config.dart';
import '../models/spreadsheet_data.dart';
import '../services/document_service.dart';
import '../services/spreadsheet_analysis_service.dart';
import 'file_actions.dart';

Future<void> showSpreadsheetAnalysisDialog(BuildContext context) =>
    showDialog<void>(
        context: context, builder: (_) => const SpreadsheetAnalysisDialog());

/// Selección explícita de datos completos; el modelo no interpreta las cifras.
class SpreadsheetAnalysisDialog extends StatefulWidget {
  const SpreadsheetAnalysisDialog({super.key});

  @override
  State<SpreadsheetAnalysisDialog> createState() =>
      _SpreadsheetAnalysisDialogState();
}

class _SpreadsheetAnalysisDialogState extends State<SpreadsheetAnalysisDialog> {
  SpreadsheetData? _data;
  SpreadsheetAnalysis? _result;
  final Set<String> _selected = {};
  int? _valueColumn;
  int? _groupColumn;
  bool _header = true;
  bool _busy = false;
  String? _error;
  String _delimiter = ',';
  String? _path;
  NumberTextFormat _numberFormat = NumberTextFormat.decimalComma;

  List<int> get _columns {
    final sheets =
        _data?.sheets.where((s) => _selected.contains(s.name)).toList() ?? [];
    if (sheets.isEmpty) {
      return [];
    }
    var columns = sheets.first.columns.toSet();
    for (final sheet in sheets.skip(1)) {
      columns = columns.intersection(sheet.columns.toSet());
    }
    return columns.toList()..sort();
  }

  void _invalidate() {
    _result = null;
    _error = null;
    final columns = _columns;
    if (!columns.contains(_valueColumn)) {
      _valueColumn = columns.length > 1 ? columns[1] : columns.firstOrNull;
    }
    if (!columns.contains(_groupColumn) || _groupColumn == _valueColumn) {
      _groupColumn = null;
    }
  }

  Future<void> _pick() async {
    try {
      final file = await openFile(acceptedTypeGroups: [
        const XTypeGroup(
            label: 'Excel y tablas',
            extensions: ['xlsx', 'xlsm', 'xls', 'csv', 'tsv'])
      ]);
      if (file == null || !mounted) {
        return;
      }
      await _load(file.path);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'No se pudo abrir el selector: $error');
      }
    }
  }

  Future<void> _load(String path) async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _data = null;
      _path = path;
    });
    try {
      final data =
          await DocumentService.readSpreadsheet(path, csvDelimiter: _delimiter);
      if (!mounted) {
        return;
      }
      setState(() {
        _data = data;
        _selected
          ..clear()
          ..add(data.sheets.firstWhere((s) => s.rows.isNotEmpty).name);
        _invalidate();
      });
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = 'No se puede calcular sobre este archivo: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _calculate() async {
    final data = _data;
    final value = _valueColumn;
    if (data == null || value == null || _selected.isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await SpreadsheetAnalysisService.calculate(
          data: data,
          sheetNames: Set.of(_selected),
          valueColumn: value,
          groupColumn: _groupColumn,
          firstRowIsHeader: _header,
          textFormat: _numberFormat);
      if (mounted) {
        setState(() => _result = result);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'No se pudo calcular: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _columnLabel(int column) {
    var index = column + 1;
    var letters = '';
    while (index > 0) {
      letters = String.fromCharCode(65 + (index - 1) % 26) + letters;
      index = (index - 1) ~/ 26;
    }
    final sheet =
        _data?.sheets.where((s) => _selected.contains(s.name)).firstOrNull;
    final heading =
        _header ? sheet?.rows.firstOrNull?.cells[column]?.text ?? '' : '';
    return heading.isEmpty ? letters : '$letters · $heading';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AlertDialog(
      title: const Text('Calcular tabla localmente'),
      content: SizedBox(
        width: size.width * 0.85,
        height: size.height * 0.70,
        child: _result == null ? _buildSelection() : _buildResult(_result!),
      ),
      actions: [
        if (_result != null)
          TextButton(
              onPressed: () => setState(() => _result = null),
              child: const Text('Cambiar selección')),
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cerrar')),
      ],
    );
  }

  Widget _buildSelection() {
    final columns = _columns;
    final firstSheet =
        _data?.sheets.where((s) => _selected.contains(s.name)).firstOrNull;
    return SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text(
          'Se lee el archivo completo, sin fragmentos del chat. Elige las hojas y columnas que quieres sumar. Las fórmulas no se ejecutan ni recalculan.'),
      const SizedBox(height: 12),
      FilledButton.tonalIcon(
          onPressed: _busy ? null : _pick,
          icon: const Icon(Icons.file_open_outlined),
          label: Text(_data?.name ?? 'Elegir archivo completo')),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _delimiter,
        decoration: const InputDecoration(labelText: 'Separador CSV'),
        items: const [
          DropdownMenuItem(value: ',', child: Text('Coma')),
          DropdownMenuItem(value: ';', child: Text('Punto y coma')),
          DropdownMenuItem(value: '\t', child: Text('Tabulación'))
        ],
        onChanged: _busy
            ? null
            : (value) {
                if (value == null) {
                  return;
                }
                setState(() => _delimiter = value);
                if (_path != null &&
                    DocumentService.extensionOf(_path!) == 'csv') {
                  _load(_path!);
                }
              },
      ),
      const SizedBox(height: 12),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
      if (_data != null) ...[
        Text(
            '${_data!.sheets.length} hojas leídas. No se ha recortado ninguna fila ni columna.'),
        for (final warning in _data!.warnings)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(warning)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final sheet in _data!.sheets)
            FilterChip(
                label: Text('${sheet.name} · ${sheet.rows.length} filas'),
                selected: _selected.contains(sheet.name),
                onSelected: _busy || sheet.rows.isEmpty
                    ? null
                    : (value) => setState(() {
                          value
                              ? _selected.add(sheet.name)
                              : _selected.remove(sheet.name);
                          _invalidate();
                        }))
        ]),
        CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('La primera fila de cada hoja es cabecera'),
            value: _header,
            onChanged: _busy
                ? null
                : (v) => setState(() {
                      _header = v ?? true;
                      _invalidate();
                    })),
        if (_selected.length > 1)
          const Text(
              'Se usan las mismas posiciones de columna en todas las hojas seleccionadas. Comprueba que sus cabeceras corresponden.'),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          key: ValueKey('value-${_selected.join()}-$_valueColumn-$_header'),
          initialValue: _valueColumn,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Columna a sumar'),
          items: [
            for (final column in columns)
              DropdownMenuItem(
                  value: column,
                  child: Text(_columnLabel(column),
                      overflow: TextOverflow.ellipsis))
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() {
                    _valueColumn = value;
                    _invalidate();
                  }),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          key: ValueKey(
              'group-${_selected.join()}-$_groupColumn-$_valueColumn-$_header'),
          initialValue: _groupColumn ?? -1,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Agrupar por'),
          items: [
            const DropdownMenuItem(value: -1, child: Text('Sin agrupación')),
            for (final column in columns.where((c) => c != _valueColumn))
              DropdownMenuItem(
                  value: column,
                  child: Text(_columnLabel(column),
                      overflow: TextOverflow.ellipsis))
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() {
                    _groupColumn = value == -1 ? null : value;
                    _result = null;
                  }),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<NumberTextFormat>(
          initialValue: _numberFormat,
          isExpanded: true,
          decoration:
              const InputDecoration(labelText: 'Números en texto / CSV'),
          items: const [
            DropdownMenuItem(
                value: NumberTextFormat.decimalComma,
                child: Text('1.234,56 · coma decimal')),
            DropdownMenuItem(
                value: NumberTextFormat.decimalPoint,
                child: Text('1,234.56 · punto decimal'))
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() {
                    _numberFormat = value ?? _numberFormat;
                    _result = null;
                  }),
        ),
        const SizedBox(height: 12),
        const Text(
            'Vista previa de la primera hoja elegida (las demás también se procesan):'),
        if (firstSheet != null)
          for (final row in firstSheet.rows.take(SpreadsheetConfig.previewRows))
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    'Fila ${row.number}: ${row.cells.entries.map((c) => '${_columnLabel(c.key)} = ${c.value.text}').join(' | ')}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis)),
        const SizedBox(height: 16),
        FilledButton.icon(
            onPressed: _busy || _valueColumn == null || _selected.isEmpty
                ? null
                : _calculate,
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('Calcular selección completa')),
      ],
    ]));
  }

  Widget _buildResult(SpreadsheetAnalysis result) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_data!.name, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
            'Hojas: ${result.sheets.join(', ')}. ${result.rows} filas de datos procesadas; ${result.numbers} valores sumados.'),
        Text(
            'Excluidos: ${result.empty} vacíos, ${result.nonNumeric} no numéricos, ${result.formulas} fórmulas y ${result.errors} errores.'),
        if (result.hasExcludedValues)
          Text(
              'Hay valores excluidos: la suma no representa todos los importes de la tabla.',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 12),
        Text('Suma de valores admitidos: ${result.total}',
            style: Theme.of(context).textTheme.titleMedium),
        const Divider(),
        Expanded(
            child: ListView.builder(
                itemCount: result.groups.length,
                itemBuilder: (_, i) {
                  final group = result.groups[i];
                  return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(group.label),
                      subtitle: Text('${group.numbers} valores'),
                      trailing: Text(group.total));
                })),
        Wrap(spacing: 8, children: [
          TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                    ClipboardData(text: result.toMarkdown(_data!.name)));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Resultado copiado')));
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copiar resultado')),
          TextButton.icon(
              onPressed: () => showExportDialog(context,
                  title: 'Cálculo ${_data!.name}',
                  text: result.toMarkdown(_data!.name)),
              icon: const Icon(Icons.save_alt),
              label: const Text('Exportar resultado')),
        ]),
      ]);
}
