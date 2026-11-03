import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../application/services/amount_calculator.dart';
import '../../theme/app_icons.dart';

Future<String?> showAmountCalculator(
  BuildContext context,
  String initialAmount,
) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => AmountCalculatorSheet(initialAmount: initialAmount),
  );
}

class AmountCalculatorSheet extends StatefulWidget {
  final String initialAmount;
  const AmountCalculatorSheet({super.key, this.initialAmount = ''});
  @override
  State<AmountCalculatorSheet> createState() => _AmountCalculatorSheetState();
}

class _AmountCalculatorSheetState extends State<AmountCalculatorSheet> {
  late String _expression;
  String? _result, _error;
  static const _operators = ['+', '−', '×', '÷'];
  @override
  void initState() {
    super.initState();
    _expression =
        RegExp(r'^\d{1,12}(\.\d{0,2})?$').hasMatch(widget.initialAmount)
        ? widget.initialAmount
        : '';
    _calculate();
  }

  void _calculate() {
    _result = null;
    _error = null;
    if (_expression.isEmpty ||
        _operators.contains(_expression.characters.last)) {
      return;
    }
    try {
      _result = AmountCalculator.evaluate(_expression);
    } on FormatException catch (e) {
      _error = e.message;
    }
  }

  void _key(String key) {
    setState(() {
      if (key == 'Clear') {
        _expression = '';
      } else if (key == 'Backspace') {
        if (_expression.isNotEmpty) {
          _expression = _expression.substring(0, _expression.length - 1);
        }
      } else if (_operators.contains(key)) {
        if (_expression.isNotEmpty) {
          _expression = _operators.contains(_expression.characters.last)
              ? '${_expression.substring(0, _expression.length - 1)}$key'
              : '$_expression$key';
        }
      } else if (_expression.length < 118) {
        final start = _expression.lastIndexOf(RegExp('[+−×÷]')) + 1;
        final current = _expression.substring(start);
        if (key == '.') {
          if (!current.contains('.')) {
            _expression += current.isEmpty ? '0.' : '.';
          }
        } else {
          var next = current == '0' ? key : '$current$key';
          if (next == '00') next = '0';
          final parts = next.split('.');
          if (parts[0].length <= 12 &&
              (parts.length == 1 || parts[1].length <= 2)) {
            _expression = '${_expression.substring(0, start)}$next';
          }
        }
      }
      _calculate();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = AppIcons.actionColor(theme);
    final result = _result == null
        ? '0.00'
        : NumberFormat('#,##,##0.00', 'en_IN').format(double.parse(_result!));
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Calculate amount',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close calculator',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(AppIcons.close),
                  ),
                ],
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: .06),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Semantics(
                              label: 'Calculation',
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                reverse: true,
                                child: Text(
                                  _expression.isEmpty ? '0' : _expression,
                                  key: const Key('calculator-expression'),
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Semantics(
                              liveRegion: true,
                              label: _result == null
                                  ? 'No amount to apply'
                                  : 'Result $result rupees',
                              child: ExcludeSemantics(
                                child: SizedBox(
                                  width: double.infinity,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      _result == null && _expression.isNotEmpty
                                          ? '—'
                                          : '₹$result',
                                      key: const Key('calculator-result'),
                                      style: theme.textTheme.displaySmall
                                          ?.copyWith(
                                            color: accent,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  _error!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colors.error,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: _expression.isEmpty
                                ? null
                                : () => _key('Clear'),
                            child: const Text('Clear'),
                          ),
                          IconButton(
                            tooltip: 'Delete last character',
                            onPressed: _expression.isEmpty
                                ? null
                                : () => _key('Backspace'),
                            icon: const Icon(Icons.backspace_outlined),
                          ),
                        ],
                      ),
                      for (final row in [
                        ['7', '8', '9', '÷'],
                        ['4', '5', '6', '×'],
                        ['1', '2', '3', '−'],
                        ['00', '0', '.', '+'],
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              for (var i = 0; i < row.length; i++) ...[
                                if (i > 0) const SizedBox(width: 8),
                                Expanded(
                                  child: Semantics(
                                    label: switch (row[i]) {
                                      '÷' => 'Divide',
                                      '×' => 'Multiply',
                                      '−' => 'Subtract',
                                      '+' => 'Add',
                                      '.' => 'Decimal point',
                                      _ => row[i],
                                    },
                                    button: true,
                                    onTap: () => _key(row[i]),
                                    excludeSemantics: true,
                                    child: FilledButton.tonal(
                                      key: ValueKey('calculator-${row[i]}'),
                                      onPressed: () => _key(row[i]),
                                      style: FilledButton.styleFrom(
                                        minimumSize: const Size(48, 64),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        backgroundColor: i == 3
                                            ? colors.primary.withValues(
                                                alpha: .13,
                                              )
                                            : colors.surfaceContainerHighest,
                                        foregroundColor: i == 3
                                            ? accent
                                            : colors.onSurface,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        row[i],
                                        style: const TextStyle(fontSize: 24),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _result == null
                      ? null
                      : () => Navigator.pop(context, _result),
                  child: Text(
                    'Use amount',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: _result == null
                          ? colors.onSurface.withValues(alpha: .38)
                          : colors.onPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
