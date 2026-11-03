import '../../widgets/app_menu_item.dart';
import '../../widgets/app_date_picker.dart';
import '../../widgets/page_loading.dart';
import 'package:expencify/presentation/theme/app_icons.dart';
import '../../widgets/sms_correction_sheet.dart';
import 'dart:async';
import '../settings/semantic_search_screen.dart';
import '../../../application/services/search/semantic_search_service.dart';
import '../settings/sms_review_screen.dart';
import '../../../application/services/sms/sms_review_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:expencify/presentation/theme/app_theme.dart';
import 'package:expencify/domain/entities/transaction.dart';
import 'package:expencify/domain/repositories/transaction_repository.dart';

import 'package:expencify/application/blocs/transaction/transaction_bloc.dart';
import 'package:expencify/application/blocs/transaction/transaction_event.dart';
import 'package:expencify/application/blocs/transaction/transaction_state.dart';
import 'package:expencify/application/blocs/account/account_bloc.dart';
import 'package:expencify/application/blocs/account/account_state.dart';

import 'package:expencify/presentation/screens/transactions/receipt_fullscreen.dart';
import 'package:expencify/presentation/screens/transactions/transaction_entry_screen.dart';
import 'package:expencify/presentation/screens/transactions/split_expense_sheet.dart';

class TransactionListScreen extends StatefulWidget {
  final VoidCallback? onRefresh;
  final bool isActive;
  final SmsReviewStore? reviewStore;
  const TransactionListScreen({
    super.key,
    this.onRefresh,
    this.reviewStore,
    this.isActive = false,
  });

  @override
  State<TransactionListScreen> createState() => _TransactionListScreenState();
}

class _TransactionListScreenState extends State<TransactionListScreen> {
  final _searchCtrl = TextEditingController();
  final _rupeeFmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '\u20B9',
    decimalDigits: 0,
  );

  Timer? _searchDebounce;
  late Future<List<Map<String, Object?>>> _reviewFuture;
  final _searchService = SemanticSearchService();
  late bool _improvedSearchEnabled;
  String? _filterType;
  String? _filterCategory;
  DateTime? _filterDateFrom;
  DateTime? _filterDateTo;
  String? _dateLabel;

  // Optimistic-deletion: track items removed but not yet committed (undo window)
  final Set<int> _removedIds = {};

  @override
  void initState() {
    super.initState();
    _reviewFuture = (widget.reviewStore ?? SmsReviewStore()).pending();
    _improvedSearchEnabled = _searchService.enabled;
    _searchService.addListener(_onSearchSettingsChanged);
    unawaited(_searchService.activate().catchError((Object _) {}));
    _load();
    _searchCtrl.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 350), _load);
    });
  }

  void _onSearchSettingsChanged() {
    if (!mounted || _improvedSearchEnabled == _searchService.enabled) return;
    setState(() => _improvedSearchEnabled = _searchService.enabled);
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;

    final accountState = context.read<AccountBloc>().state;
    int? selectedId;
    if (accountState is AccountLoaded) {
      selectedId = accountState.selectedAccountId;
    }

    final bloc = context.read<TransactionBloc>();
    await waitForPageLoad(
      bloc.stream,
      (state) =>
          state is TransactionError ||
          (state is TransactionLoaded && !state.refreshing),
      () => bloc.add(
        LoadTransactions(
          accountId: selectedId,
          type: _filterType,
          category: _filterCategory,
          from: _filterDateFrom,
          to: _filterDateTo,
          search: _searchCtrl.text.trim(),
          semantic: _searchService.enabled,
        ),
      ),
    );
  }

  Future<void> _deleteTransaction(TransactionModel t) async {
    if (t.id == null) return;
    final txBloc = context.read<TransactionBloc>();
    final children = await context
        .read<TransactionRepository>()
        .getChildTransactions(t.id!);
    if (!mounted) return;

    // 1. Optimistically hide the row immediately.
    setState(() => _removedIds.add(t.id!));

    // 2. Commit deletion to DB immediately — balance & home card update now.
    txBloc.add(DeleteTransaction(t));
    widget.onRefresh?.call();

    // 3. Allow a readable Undo window; let ScaffoldMessenger own dismissal.
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        persist: false,
        content: Text(
          'Deleted: ${t.merchant.isNotEmpty
              ? t.merchant
              : t.note.isNotEmpty
              ? t.note
              : t.category}',
        ),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            // Re-insert the transaction (new row, balance reversed).
            txBloc.add(
              AddTransaction(
                TransactionModel(
                  accountId: t.accountId,
                  amount: t.amount,
                  type: t.type,
                  category: t.category,
                  date: t.date,
                  note: t.note,
                  merchant: t.merchant,
                  isOcr: t.isOcr,
                  isVoice: t.isVoice,
                  isSms: t.isSms,
                  imagePath: t.imagePath,
                  parentId: t.parentId,
                ),
                splitChildren: children,
              ),
            );
            if (mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              setState(() => _removedIds.remove(t.id));
              // Give the bloc time to process AddTransaction and save to DB
              // before refreshing the home balance via onRefresh.
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted) widget.onRefresh?.call();
              });
            }
          },
        ),
      ),
    );

    // Clean up the optimistic-hide set after the snackbar window.
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _removedIds.remove(t.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocListener<TransactionBloc, TransactionState>(
      listenWhen: (previous, current) =>
          current is TransactionLoaded && previous != current,
      listener: (_, state) {
        setState(() {
          _reviewFuture = (widget.reviewStore ?? SmsReviewStore()).pending();
        });
      },
      child: _buildContent(theme),
    );
  }

  Widget _buildContent(ThemeData theme) {
    return BlocListener<AccountBloc, AccountState>(
      listenWhen: (previous, current) {
        if (previous is AccountLoaded && current is AccountLoaded) {
          return previous.selectedAccountId != current.selectedAccountId;
        }
        return false;
      },
      listener: (context, state) {
        if (state is AccountLoaded) _load();
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: const Text('Transactions'),
          automaticallyImplyLeading: false,
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(
              tooltip: 'SMS to review',
              icon: const Icon(Icons.fact_check_outlined),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SmsReviewScreen()),
                );
                if (mounted) {
                  setState(() {});
                  _load();
                }
              },
            ),
            IconButton(
              tooltip: 'Filter transactions',
              icon: const Icon(AppIcons.filter),
              onPressed: _showFilterSheet,
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                controller: _searchCtrl,
                maxLength: 600,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'Search transactions…',
                  counterText: '',
                  suffixIcon: PopupMenuButton<String>(
                    clipBehavior: Clip.antiAlias,
                    tooltip: 'Search options',
                    icon: Icon(
                      Icons.tune_rounded,
                      color: _improvedSearchEnabled
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    itemBuilder: (_) => [
                      if (_searchService.enabled &&
                          (_searchService.indexing ||
                              _searchService.error != null))
                        AppMenuItem<String>(
                          enabled: false,
                          label: _searchService.error ?? 'Improving search…',
                          icon: AppIcons.search,
                        ),
                      AppMenuItem(
                        value: 'improve',
                        label: _searchService.enabled
                            ? 'Manage improved search'
                            : 'Improve search',
                        icon: AppIcons.search,
                      ),
                    ],
                    onSelected: (_) async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SemanticSearchScreen(),
                        ),
                      );
                      if (mounted) _load();
                    },
                  ),
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  prefixIcon: Icon(
                    AppIcons.search,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  filled: true,
                  fillColor: theme.brightness == Brightness.dark
                      ? AppTheme.darkElevated
                      : AppTheme.lightElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            FutureBuilder<List<Map<String, Object?>>>(
              future: _reviewFuture,
              builder: (context, snapshot) {
                final count = snapshot.data?.length ?? 0;
                if (count == 0) return const SizedBox.shrink();
                return ListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: Text('$count SMS to review'),
                  trailing: const Icon(AppIcons.chevron),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SmsReviewScreen(),
                      ),
                    );
                    if (mounted) {
                      setState(() {
                        _reviewFuture = (widget.reviewStore ?? SmsReviewStore())
                            .pending();
                      });
                      _load();
                    }
                  },
                );
              },
            ),
            if (_filterType != null ||
                _filterCategory != null ||
                _dateLabel != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            if (_filterType != null)
                              _buildFilterChip(
                                'Type: ${_filterType!.capitalize()}',
                                () {
                                  setState(() => _filterType = null);
                                  _load();
                                },
                              ),
                            if (_filterCategory != null)
                              _buildFilterChip('Cat: $_filterCategory', () {
                                setState(() => _filterCategory = null);
                                _load();
                              }),
                            if (_dateLabel != null)
                              _buildFilterChip(_dateLabel!, () {
                                setState(() {
                                  _dateLabel = null;
                                  _filterDateFrom = null;
                                  _filterDateTo = null;
                                });
                                _load();
                              }),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _filterType = null;
                          _filterCategory = null;
                          _dateLabel = null;
                          _filterDateFrom = null;
                          _filterDateTo = null;
                        });
                        _load();
                      },
                      child: Text(
                        'Clear',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: RefreshFeedback<TransactionBloc, TransactionState>(
                onRetry: _load,
                child: BlocBuilder<TransactionBloc, TransactionState>(
                  builder: (context, state) {
                    if (state is TransactionLoading ||
                        state is TransactionInitial) {
                      return const PageLoading(label: 'Loading transactions');
                    } else if (state is TransactionLoaded) {
                      if (state.transactions.isEmpty) {
                        return _buildEmpty(theme);
                      }
                      return RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          itemCount: state.transactions.length,
                          itemBuilder: (ctx, i) {
                            final t = state.transactions[i];
                            // Skip optimistically removed items without rebuilding
                            if (_removedIds.contains(t.id)) {
                              return const SizedBox.shrink();
                            }
                            return _buildItem(theme, t);
                          },
                        ),
                      );
                    } else if (state is TransactionError) {
                      return Center(child: Text(state.message));
                    }
                    return _buildEmpty(theme);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, VoidCallback onRemove) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: onRemove,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: dark ? AppTheme.darkElevated : AppTheme.lightElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: dark ? AppTheme.darkBorder : AppTheme.lightBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              AppIcons.close,
              size: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(ThemeData theme, TransactionModel t) {
    final isExpense = t.type == 'expense';
    final color = isExpense ? AppTheme.expense : AppTheme.income;
    return Dismissible(
      key: Key('txn_${t.id}'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => _deleteTransaction(t),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          _showSplitSheet(t);
          return false;
        }
        return true;
      },
      secondaryBackground: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.expense,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(AppIcons.delete, color: Colors.white),
      ),
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Row(
          children: [
            Icon(Icons.call_split_rounded, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Split',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      child: InkWell(
        onTap: () async {
          if (t.isSms) {
            await showSmsCorrection(context, t);
            if (mounted) _load();
            return;
          }
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TransactionEntryScreen(existing: t),
            ),
          );
          _load();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.brightness == Brightness.dark
                    ? AppTheme.darkBorder
                    : AppTheme.lightBorder,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              BarIndicator(color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.merchant.isNotEmpty
                          ? t.merchant
                          : t.note.isNotEmpty
                          ? t.note
                          : t.category,
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${t.merchant.isEmpty && t.note.isEmpty ? '' : '${t.category} · '}${DateFormat('d MMM yyyy').format(t.date)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isExpense)
                        IconButton(
                          tooltip: 'Split expense',
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          icon: Icon(
                            Icons.call_split_rounded,
                            size: 20,
                            color: color,
                          ),
                          onPressed: () => _showSplitSheet(t),
                        ),
                      if (isExpense) const SizedBox(width: 8),
                      Text(
                        '${isExpense ? '-' : '+'}${_rupeeFmt.format(t.amount)}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (t.isSms) _buildSourceBadge('SMS', Colors.green),
                      if (t.isVoice) _buildSourceBadge('Voice', Colors.purple),
                      if (t.isOcr) _buildSourceBadge('OCR', Colors.orange),
                      if (t.imagePath != null)
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ReceiptFullscreen(imagePath: t.imagePath!),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.attach_file_rounded,
                              color: theme.colorScheme.onSurfaceVariant,
                              size: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showSplitSheet(TransactionModel t) {
    if (t.type != 'expense') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          persist: false,
          content: Text('Only expenses can be distributed.'),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SplitExpenseSheet(
        transaction: t,
        onSplit: (splits) {
          final parts = splits
              .map(
                (s) => TransactionModel(
                  accountId: t.accountId,
                  amount: s.amount,
                  type: 'expense',
                  category: s.category,
                  date: t.date,
                  note: s.note,
                  merchant: t.merchant,
                  isSms: t.isSms,
                  isVoice: t.isVoice,
                  isOcr: t.isOcr,
                ),
              )
              .toList();

          context.read<TransactionBloc>().add(SplitTransactions(t, parts));
          Navigator.pop(ctx);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              persist: false,
              content: Text('Expense split saved'),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            AppIcons.transactions,
            size: 64,
            color: theme.colorScheme.primary.withOpacity(0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'No transactions found',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filter',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Date Range',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    [
                      'All Time',
                      'Today',
                      'This Month',
                      'This Year',
                      'Custom Range',
                    ].map((p) {
                      final isSelected =
                          (p == 'All Time' && _dateLabel == null) ||
                          (_dateLabel == p);
                      return ChoiceChip(
                        label: Text(p),
                        selected: isSelected,
                        onSelected: (val) async {
                          if (!val) return;
                          if (p == 'Custom Range') {
                            Navigator.pop(ctx);
                            // Delay slightly to ensure sheet is dismissed before showing picker
                            Future.delayed(
                              const Duration(milliseconds: 100),
                              () => _applyDateFilter(p),
                            );
                          } else {
                            _applyDateFilter(p);
                            Navigator.pop(ctx);
                          }
                        },
                      );
                    }).toList(),
              ),
              const SizedBox(height: 24),
              Text(
                'Transaction Type',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: ['All Types', 'expense', 'income']
                    .map(
                      (t) => ChoiceChip(
                        label: Text(
                          t == 'All Types' ? 'All Types' : t.capitalize(),
                        ),
                        selected: (t == 'All Types'
                            ? _filterType == null
                            : _filterType == t),
                        onSelected: (_) {
                          setState(
                            () => _filterType = t == 'All Types' ? null : t,
                          );
                          Navigator.pop(ctx);
                          _load();
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _applyDateFilter(String period) async {
    final now = DateTime.now();
    DateTime? from;
    DateTime? to;
    String? label = period;

    if (period == 'Today') {
      from = DateTime(now.year, now.month, now.day);
      to = from
          .add(const Duration(days: 1))
          .subtract(const Duration(milliseconds: 1));
    } else if (period == 'This Month') {
      from = DateTime(now.year, now.month, 1);
      to = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    } else if (period == 'This Year') {
      from = DateTime(now.year, 1, 1);
      to = DateTime(now.year, 12, 31, 23, 59, 59);
    } else if (period == 'Custom Range') {
      final picked = await showAppDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDateRange: _filterDateFrom != null && _filterDateTo != null
            ? DateTimeRange(start: _filterDateFrom!, end: _filterDateTo!)
            : null,
      );
      if (picked != null) {
        from = picked.start;
        to = picked.end
            .add(const Duration(days: 1))
            .subtract(const Duration(milliseconds: 1));
        label =
            '${DateFormat('d MMM').format(from)} - ${DateFormat('d MMM').format(to)}';
      } else {
        return;
      }
    } else {
      // All Time
      from = null;
      to = null;
      label = null;
    }

    setState(() {
      _filterDateFrom = from;
      _filterDateTo = to;
      _dateLabel = label;
    });
    _load();
  }

  @override
  void dispose() {
    _searchService.removeListener(_onSearchSettingsChanged);
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }
}

extension StringCapitalize on String {
  String capitalize() =>
      isEmpty ? '' : '${this[0].toUpperCase()}${substring(1)}';
}
