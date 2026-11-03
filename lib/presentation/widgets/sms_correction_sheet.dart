import 'package:expencify/presentation/theme/app_icons.dart';
import '../screens/transactions/transaction_entry_screen.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/account.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/account_repository.dart';
import '../../domain/repositories/category_repository.dart';
import '../../application/blocs/account/account_bloc.dart';
import '../../application/blocs/account/account_event.dart';
import '../../application/blocs/transaction/transaction_bloc.dart';
import '../../application/blocs/transaction/transaction_event.dart';
import '../../application/services/search/semantic_search_service.dart';
import '../../infrastructure/database/database_helper.dart';
import '../../infrastructure/repositories/sqlite_transaction_repository.dart';
import '../screens/settings/smart_rules_screen.dart';

Future<bool> showSmsCorrection(
  BuildContext context,
  TransactionModel draft, {
  String? reviewIdentity,
}) async {
  final bloc = context.read<TransactionBloc>();
  final accounts = context.read<AccountBloc>();
  final result = await showModalBottomSheet<(TransactionModel, bool, bool)>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => SmsCorrectionSheet(
      draft: draft,
      onSave: (value) async {
        if (reviewIdentity != null) {
          await SqliteTransactionRepository(
            DatabaseHelper(),
          ).saveSms(value, reviewIdentity);
          SemanticSearchService().schedule();
          bloc.add(const RefreshTransactions());
          accounts.add(LoadAccounts());
        } else {
          final completion = Completer<bool>();
          bloc.add(UpdateTransaction(value, draft, completion: completion));
          if (!await completion.future) {
            throw StateError('Could not save correction.');
          }
        }
      },
    ),
  );
  if (result == null) return false;
  if (result.$3) {
    if (!context.mounted) return false;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionEntryScreen(
          existing: draft,
          draft: result.$1,
          initialRememberMerchant: result.$2,
        ),
      ),
    );
    return saved == true;
  }

  if (context.mounted && result.$2) {
    await showSavedMerchantEditor(
      context,
      keyword: draft.merchant,
      name: result.$1.merchant,
      category: result.$1.category,
      type: result.$1.type,
    );
  }
  return true;
}

class SmsCorrectionSheet extends StatefulWidget {
  final TransactionModel draft;
  final Future<void> Function(TransactionModel) onSave;
  const SmsCorrectionSheet({
    super.key,
    required this.draft,
    required this.onSave,
  });
  @override
  State<SmsCorrectionSheet> createState() => _SmsCorrectionSheetState();
}

class _SmsCorrectionSheetState extends State<SmsCorrectionSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount, _merchant;
  List<Account>? _accounts;
  List<Category> _categories = [];
  int? _account;
  String? _type, _category, _error;
  bool _busy = false, _remember = false;
  @override
  void initState() {
    super.initState();
    final t = widget.draft;
    _amount = TextEditingController(
      text: t.amount > 0 ? t.amount.toStringAsFixed(2) : '',
    );
    _merchant = TextEditingController(text: t.merchant);
    _type = ['income', 'expense'].contains(t.type) ? t.type : null;
    _category = t.category;
    _account = t.accountId;
    _load();
  }

  Future<void> _load() async {
    try {
      final a = await context.read<AccountRepository>().getAll();
      if (!mounted) return;
      final c = await context.read<CategoryRepository>().getAll();
      if (mounted) {
        setState(() {
          _accounts = a;
          _categories = c;
          _error = null;
          if (!a.any((v) => v.id == _account)) _account = null;
          if (!c.any((v) => v.name == _category && v.type == _type)) {
            _category = null;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load accounts and categories.');
      }
    }
  }

  TransactionModel _currentDraft() => widget.draft.copyWith(
    amount: double.parse(_amount.text.trim()),
    merchant: _merchant.text.trim(),
    accountId: _account!,
    type: _type!,
    category: _category!,
  );
  void _fullDetails() {
    if (_busy || !_form.currentState!.validate()) return;
    Navigator.pop(context, (_currentDraft(), _remember, true));
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = _currentDraft();
      await widget.onSave(t);
      if (mounted) {
        Navigator.pop(context, (t, _remember && t.merchant.isNotEmpty, false));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save. Your changes are still here. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .85,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.draft.id == null
                              ? 'Review transaction'
                              : 'Correct transaction',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        icon: const Icon(AppIcons.close),
                      ),
                    ],
                  ),
                  if (_accounts == null) ...[
                    if (_error != null)
                      TextButton(onPressed: _load, child: Text(_error!))
                    else
                      const LinearProgressIndicator(),
                  ] else ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _type,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Transaction type',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'expense',
                          child: Text('Expense'),
                        ),
                        DropdownMenuItem(
                          value: 'income',
                          child: Text('Income'),
                        ),
                      ],
                      validator: (v) =>
                          v == null ? 'Choose expense or income' : null,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                              _type = v;
                              _category = null;
                            }),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _amount,
                      enabled: !_busy,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        prefixText: '₹ ',
                      ),
                      validator: (v) {
                        final n = double.tryParse(v ?? '');
                        return n == null || !n.isFinite || n > 1e12 || n <= 0
                            ? 'Enter an amount greater than zero'
                            : null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: _account,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Account'),
                      items: _accounts!
                          .map(
                            (a) => DropdownMenuItem(
                              value: a.id,
                              child: Text(
                                '${a.name} · ${a.accountNumber}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      validator: (v) => v == null ? 'Choose an account' : null,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _account = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _category,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: _categories
                          .where((c) => c.type == _type)
                          .map(
                            (c) => DropdownMenuItem(
                              value: c.name,
                              child: Text(c.name),
                            ),
                          )
                          .toList(),
                      validator: (v) => v == null ? 'Choose a category' : null,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _category = v),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _merchant,
                      enabled: !_busy,
                      decoration: InputDecoration(
                        labelText: 'Merchant',
                        helperText:
                            widget.draft.id != null &&
                                widget.draft.merchant.trim().isNotEmpty
                            ? 'Renaming updates matching past transactions.'
                            : null,
                        helperMaxLines: 2,
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _remember,
                      title: const Text('Remember for future SMS'),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _remember = v ?? false),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: Text(_busy ? 'Saving…' : 'Save correction'),
                    ),
                    if (widget.draft.id != null)
                      TextButton(
                        onPressed: _busy ? null : _fullDetails,
                        child: const Text('Edit all details'),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
