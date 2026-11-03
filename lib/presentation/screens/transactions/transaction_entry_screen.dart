import '../../widgets/app_date_picker.dart';
import 'package:expencify/presentation/theme/app_icons.dart';
import 'amount_calculator_sheet.dart';
import '../../widgets/receipt_image.dart';
import '../../../application/services/security/receipt_store.dart';
import '../../../application/services/security/private_file_cleanup.dart';
import '../../widgets/saved_merchant_picker.dart';
import '../../../application/blocs/account/account_event.dart';
import '../../../application/services/search/semantic_search_service.dart';
import '../settings/smart_rules_screen.dart';
import '../../../infrastructure/database/database_helper.dart';
import '../../../infrastructure/repositories/sqlite_transaction_repository.dart';
import '../../widgets/receipt_scan_overlay.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:expencify/domain/entities/transaction.dart';
import 'package:expencify/domain/repositories/transaction_repository.dart';
import 'package:expencify/application/blocs/account/account_bloc.dart';
import 'package:expencify/application/blocs/account/account_state.dart';
import 'package:expencify/application/blocs/transaction/transaction_bloc.dart';
import 'package:expencify/application/blocs/transaction/transaction_event.dart';
import 'package:expencify/application/blocs/transaction/transaction_state.dart';
import 'package:expencify/application/blocs/category/category_bloc.dart';
import 'package:expencify/application/blocs/category/category_event.dart';
import 'package:expencify/application/blocs/category/category_state.dart';
import 'package:expencify/presentation/theme/app_theme.dart';
import 'package:expencify/application/services/ocr/ocr_service.dart';
import 'package:expencify/application/services/ocr/receipt_items.dart';
import 'split_expense_sheet.dart';
import 'package:expencify/application/services/ai/ai_service.dart';
import 'package:expencify/presentation/screens/transactions/receipt_fullscreen.dart';

class TransactionEntryScreen extends StatefulWidget {
  final OCRService? ocrService;
  final int initialTab;
  final AIAction? aiAction;
  final TransactionModel? existing;
  final bool isVoiceEntry;
  final TransactionModel? draft;
  final String? reviewIdentity;
  final bool initialRememberMerchant;
  const TransactionEntryScreen({
    super.key,
    this.ocrService,
    this.initialTab = 0,
    this.aiAction,
    this.existing,
    this.isVoiceEntry = false,
    this.draft,
    this.reviewIdentity,
    this.initialRememberMerchant = false,
  });

  @override
  State<TransactionEntryScreen> createState() => _TransactionEntryScreenState();
}

class _TransactionEntryScreenState extends State<TransactionEntryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final _ocrService = widget.ocrService ?? OCRService();

  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _merchantCtrl = TextEditingController();

  String _type = 'expense';
  String _selectedCategory = '';
  bool _ocrProcessed = false;
  bool _scanning = false;
  bool _readingReceipt = false;
  List<ReceiptItem> _receiptItems = [];
  List<SplitExpenseItem>? _expenseSplits;
  bool _dirty = false;
  bool _rememberMerchant = false;
  bool _reviewTypeConfirmed = false;
  bool _allowPop = false;
  bool _saving = false;
  bool _confirmingDiscard = false;
  String? _saveError;
  String? _amountError;
  String? _categoryError;
  final _amountFocus = FocusNode();
  DateTime _selectedDate = DateTime.now();
  int? _selectedAccountId;

  // Receipt image
  String? _receiptImagePath;

  @override
  void initState() {
    super.initState();
    _rememberMerchant = widget.initialRememberMerchant;
    _dirty =
        widget.existing != null &&
        widget.draft != null &&
        widget.existing != widget.draft;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.existing != null ? 0 : widget.initialTab.clamp(0, 1),
    );

    if (widget.existing != null || widget.draft != null) {
      final e = (widget.draft ?? widget.existing)!;
      _amountCtrl.text = e.amount > 0 ? e.amount.toStringAsFixed(2) : '';
      _type = e.type.isEmpty ? 'expense' : e.type;
      _reviewTypeConfirmed = e.type.isNotEmpty;
      _selectedCategory = e.category;
      _selectedDate = e.date;
      _selectedAccountId = e.accountId > 0 ? e.accountId : null;
      _noteCtrl.text = e.note;
      _merchantCtrl.text = e.merchant;
      _receiptImagePath = e.imagePath;
    } else if (widget.aiAction != null) {
      _ocrProcessed = widget.initialTab == 1;
      _merchantCtrl.text = widget.aiAction!.merchant ?? '';
      _selectedDate = widget.aiAction!.date ?? DateTime.now();
      if (widget.aiAction!.amount != null) {
        _amountCtrl.text = widget.aiAction!.amount.toString();
      }
      if (widget.aiAction!.category != null &&
          widget.aiAction!.category!.isNotEmpty) {
        _selectedCategory = widget.aiAction!.category!;
      }
      final parts = widget.aiAction!.items;
      if (widget.isVoiceEntry && parts != null && parts.length > 1) {
        _expenseSplits = [
          for (var i = 0; i < parts.length; i++)
            SplitExpenseItem(
              id: 'voice-$i',
              amount: parts[i].amount,
              category: parts[i].category,
              note: parts[i].label ?? '',
            ),
        ];
        _dirty = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_reviewExpenseSplits());
        });
      }
    }

    _loadData();
    for (final controller in [_amountCtrl, _noteCtrl, _merchantCtrl]) {
      controller.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  Future<void> _confirmClose(bool didPop, Object? result) async {
    if (didPop || _confirmingDiscard || _saving || _scanning) return;
    _confirmingDiscard = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this draft?'),
        content: const Text('Your unsaved transaction details will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    _confirmingDiscard = false;
    if (discard != true || !mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _pickReceiptImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Attach Receipt',
                style: Theme.of(
                  ctx,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(AppIcons.camera, color: Colors.teal),
                title: const Text('Take Photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(AppIcons.gallery, color: Colors.teal),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              if (_receiptImagePath != null)
                ListTile(
                  leading: const Icon(AppIcons.delete, color: Colors.red),
                  title: const Text(
                    'Remove Receipt',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    setState(() => _receiptImagePath = null);
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
    );
    if (picked != null && mounted) {
      final receipt = await _keepReceipt(picked.path);
      if (!mounted || receipt == null) return;
      setState(() {
        _dirty = true;
        _receiptImagePath = receipt;
        _receiptItems = [];
        _expenseSplits = null;
      });
    }
  }

  Future<String?> _keepReceipt(String source) async {
    try {
      if (await ReceiptStore().protected(source)) return source;
      final saved = await ReceiptStore().importPhoto(source);
      await const PrivateFileCleanup().removePickerCopy(source);
      return saved;
    } catch (error) {
      if (mounted) {
        setState(
          () => _saveError = error is ReceiptSecurityException
              ? error.message
              : 'Could not secure this receipt photo. Please try again.',
        );
      }
      return null;
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    context.read<CategoryBloc>().add(LoadCategories(type: _type));
    // Account data is managed by AccountBloc and we can access it via state
    final accountState = context.read<AccountBloc>().state;
    if (accountState is AccountLoaded &&
        mounted &&
        widget.reviewIdentity == null) {
      setState(() {
        _selectedAccountId ??=
            accountState.selectedAccountId ??
            accountState.accounts.firstOrNull?.id;
      });
    }
  }

  Future<void> _refreshCategories() async {
    context.read<CategoryBloc>().add(LoadCategories(type: _type));
  }

  Future<void> _handleOCR(ImageSource source) async {
    if (_scanning || _saving) return;
    setState(() {
      _scanning = true;
      _saveError = null;
    });
    try {
      final text = await _ocrService.pickAndRecognizeText(
        source,
        onProcessing: () async {
          if (!mounted) return;
          setState(() => _readingReceipt = true);
          await WidgetsBinding.instance.endOfFrame;
        },
      );
      if (!mounted || text == null) return;
      if (text.trim().isEmpty) {
        setState(
          () => _saveError =
              'No text found. Try another photo or enter the amount.',
        );
        return;
      }
      final result = _ocrService.parseReceipt(text);
      final image = _ocrService.lastImagePath;
      final receipt = image == null ? null : await _keepReceipt(image);
      if (!mounted) return;
      setState(() {
        _readingReceipt = false;
        if (result['amount'] != null) {
          _amountCtrl.text = (result['amount'] as double).toStringAsFixed(2);
        } else {
          _amountCtrl.clear();
          _saveError =
              'Check the receipt and enter its total. We could not identify a single total.';
        }
        _receiptImagePath = receipt;
        _receiptItems = List<ReceiptItem>.from(result['items'] as List);
        _expenseSplits = null;
        _ocrProcessed = true;
        _dirty = true;
      });
      _tabController.animateTo(0);
      if (_canSplitExpense &&
          _receiptItems.length > 1 &&
          (double.tryParse(_amountCtrl.text) ?? 0) > 0) {
        setState(() => _scanning = false);
        await _reviewExpenseSplits();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _saveError =
              'Could not read this receipt. Try another photo or enter the details.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _scanning = false;
          _readingReceipt = false;
        });
      }
    }
  }

  bool get _canSplitExpense =>
      widget.existing == null &&
      widget.reviewIdentity == null &&
      _type == 'expense';

  Future<void> _reviewExpenseSplits() async {
    final amount = double.tryParse(_amountCtrl.text);
    if (!_canSplitExpense ||
        amount == null ||
        !amount.isFinite ||
        amount <= 0) {
      setState(() => _amountError = 'Enter the expense total before splitting');
      return;
    }
    final initial =
        _expenseSplits ??
        [
          for (var i = 0; i < _receiptItems.length; i++)
            SplitExpenseItem(
              id: 'receipt-$i',
              amount: _receiptItems[i].amount ?? 0,
              category: _selectedCategory.isEmpty ? 'Other' : _selectedCategory,
              note: _receiptItems[i].name,
            ),
        ];
    if (initial.isEmpty) return;
    final splits = await showModalBottomSheet<List<SplitExpenseItem>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * .9,
        child: SplitExpenseSheet(
          transaction: TransactionModel(
            accountId: _selectedAccountId ?? 0,
            amount: amount,
            type: 'expense',
            category: _selectedCategory,
            date: _selectedDate,
          ),
          initialSplits: initial,
          onSplit: (parts) => Navigator.pop(ctx, parts),
        ),
      ),
    );
    if (!mounted || splits == null) return;
    setState(() {
      _expenseSplits = splits;
      _dirty = true;
      _categoryError = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final amountText = _amountCtrl.text.trim();
    final amount = double.tryParse(amountText);

    if (amount == null || !amount.isFinite || amount <= 0) {
      setState(() => _amountError = 'Enter an amount greater than zero');
      _amountFocus.requestFocus();
      return;
    }

    if (_selectedAccountId == null) {
      setState(() => _saveError = 'Select an account before saving.');
      return;
    }

    final splits = _canSplitExpense ? _expenseSplits : null;
    if (splits != null &&
        (splits.any((s) => !s.amount.isFinite || s.amount <= 0) ||
            splits.fold<int>(0, (sum, s) => sum + (s.amount * 100).round()) !=
                (amount * 100).round())) {
      setState(
        () => _saveError =
            'Review the split amounts. They must match the expense total.',
      );
      return;
    }
    if (_selectedCategory.isEmpty && splits == null) {
      setState(() => _categoryError = 'Choose a category');
      return;
    }
    if (widget.reviewIdentity != null && !_reviewTypeConfirmed) {
      setState(() => _saveError = 'Choose Expense or Income before saving.');
      return;
    }
    FocusScope.of(context).unfocus();
    final t = TransactionModel(
      id: widget.existing?.id,
      parentId: widget.existing?.parentId,
      accountId: _selectedAccountId!,
      amount: amount,
      type: _type,
      category: _selectedCategory.isEmpty ? 'Other' : _selectedCategory,
      date: _selectedDate,
      note: _noteCtrl.text.trim(),
      merchant: _merchantCtrl.text.trim(),
      isOcr: _ocrProcessed || (widget.existing?.isOcr ?? false),
      isVoice: widget.isVoiceEntry || (widget.existing?.isVoice ?? false),
      isSms: widget.existing?.isSms ?? widget.draft?.isSms ?? false,
      imagePath: _receiptImagePath,
    );

    final completion = Completer<bool>();
    setState(() {
      _saving = true;
      _saveError = null;
    });
    if (widget.reviewIdentity != null) {
      try {
        await SqliteTransactionRepository(
          DatabaseHelper(),
        ).saveSms(t, widget.reviewIdentity!);
        completion.complete(true);
        SemanticSearchService().schedule();
        if (mounted) {
          context.read<AccountBloc>().add(LoadAccounts());
          context.read<TransactionBloc>().add(LoadTransactions());
        }
      } catch (_) {
        completion.complete(false);
      }
    } else if (widget.existing != null) {
      context.read<TransactionBloc>().add(
        UpdateTransaction(t, widget.existing!, completion: completion),
      );
    } else {
      context.read<TransactionBloc>().add(
        AddTransaction(
          t,
          completion: completion,
          splitChildren: splits
              ?.map(
                (s) => TransactionModel(
                  accountId: t.accountId,
                  amount: s.amount,
                  type: t.type,
                  category: s.category,
                  date: t.date,
                  note: s.note,
                  merchant: t.merchant,
                  isOcr: t.isOcr,
                  isVoice: t.isVoice,
                ),
              )
              .toList(),
        ),
      );
    }
    final saved = await completion.future;
    if (!mounted) return;
    if (saved) {
      if (_rememberMerchant && _merchantCtrl.text.trim().isNotEmpty) {
        await showSavedMerchantEditor(
          context,
          keyword: widget.existing?.merchant ?? widget.draft?.merchant,
          name: t.merchant,
          category: t.category,
          type: t.type,
        );
        if (!mounted) return;
      }
      setState(() {
        _saving = false;
        _allowPop = true;
        _dirty = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
    } else {
      setState(() {
        _saving = false;
        _saveError =
            'Could not save. Your draft is still here. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: _allowPop || (!_dirty && !_saving && !_scanning),
      onPopInvokedWithResult: _confirmClose,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: theme.brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: theme.brightness, // For iOS
          ),
          title: Text(
            widget.existing != null ? 'Edit transaction' : 'Add transaction',
            style: theme.textTheme.titleLarge,
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            tooltip: 'Close transaction',
            icon: const Icon(AppIcons.close),
            onPressed: _scanning || _saving
                ? null
                : () => Navigator.maybePop(context),
          ),
        ),
        body: ReceiptScanOverlay(
          active: _readingReceipt,
          child: Column(
            children: [
              _buildModeSwitcher(theme),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [_buildManualTab(theme), _buildScanTab(theme)],
                ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: _buildSaveButton(theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeSwitcher(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildModeItem(0, 'Manual', AppIcons.edit, theme),
          _buildModeItem(1, 'Scan', AppIcons.camera, theme),
        ],
      ),
    );
  }

  Widget _buildModeItem(
    int index,
    String label,
    IconData icon,
    ThemeData theme,
  ) {
    final isSelected = _tabController.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: _scanning || _saving
            ? null
            : () => setState(() => _tabController.index = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? theme.colorScheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withOpacity(0.4),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withOpacity(0.4),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManualTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          _buildAmountInput(theme),
          const SizedBox(height: 16),
          _buildTypeToggle(theme),
          const SizedBox(height: 24),
          _buildSectionLabel(theme, 'Transaction Details'),
          const SizedBox(height: 12),
          _buildAccountSelector(theme),
          const SizedBox(height: 12),
          _buildCategorySelector(theme),
          const SizedBox(height: 12),
          _buildMerchantInput(theme),
          const SizedBox(height: 12),
          _buildNoteInput(theme),
          const SizedBox(height: 12),
          _buildDatePicker(theme),
          const SizedBox(height: 24),
          _buildReceiptPicker(theme),
          if (_canSplitExpense &&
              (_receiptItems.isNotEmpty || _expenseSplits != null))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.call_split_rounded),
              title: Text(
                _expenseSplits == null
                    ? 'Split ${_receiptItems.length} receipt items'
                    : '${_expenseSplits!.length} split parts',
              ),
              subtitle: Text(
                _expenseSplits == null
                    ? 'Review item amounts'
                    : 'Ready to save with this expense',
              ),
              onTap: _saving || _scanning ? null : _reviewExpenseSplits,
              trailing: _expenseSplits == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(
                      tooltip: 'Remove split',
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                              _expenseSplits = null;
                              _dirty = true;
                            }),
                      icon: const Icon(Icons.close),
                    ),
            ),
          // ── Split children (only when editing a split parent) ──
          if (widget.existing?.id != null) ..._buildSplitSection(theme),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(ThemeData theme, String label) {
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 1.0,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildMerchantInput(ThemeData theme) {
    return Column(
      children: [
        TextFormField(
          controller: _merchantCtrl,
          decoration: InputDecoration(
            suffixIcon: IconButton(
              tooltip: 'Saved merchants',
              icon: const Icon(AppIcons.expand),
              onPressed: _saving
                  ? null
                  : () async {
                      final merchant = await showSavedMerchantPicker(
                        context,
                        _type,
                      );
                      if (!mounted || merchant == null) return;
                      setState(() {
                        _merchantCtrl.text = merchant.name;
                        final categories = context.read<CategoryBloc>().state;
                        if (categories is CategoryLoaded &&
                            categories.categories.any(
                              (c) => c.name == merchant.category,
                            )) {
                          _selectedCategory = merchant.category;
                        }
                        _categoryError = null;
                        _dirty = true;
                      });
                    },
            ),
            hintText: 'Merchant name',
            prefixIcon: const Icon(AppIcons.merchant, size: 20),
            labelText: 'Merchant (optional)',
            helperText: (widget.existing?.merchant.trim().isNotEmpty ?? false)
                ? 'Renaming also updates matching past transactions.'
                : null,
            helperMaxLines: 2,
          ),
        ),
        if ((widget.existing?.isSms ?? widget.draft?.isSms ?? false))
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Remember for future SMS'),
            value: _rememberMerchant,
            onChanged: _saving
                ? null
                : (v) => setState(() {
                    _rememberMerchant = v ?? false;
                    _dirty = true;
                  }),
          ),
      ],
    );
  }

  Widget _buildNoteInput(ThemeData theme) {
    return TextFormField(
      controller: _noteCtrl,
      decoration: const InputDecoration(
        hintText: 'Add a quick note...',
        prefixIcon: Icon(Icons.notes_rounded, size: 20),
        labelText: 'Notes (optional)',
      ),
      maxLines: 1,
    );
  }

  Widget _buildScanTab(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildScanHero(theme),
            const SizedBox(height: 40),
            if (_amountCtrl.text.isNotEmpty) ...[
              _buildAmountPreview(theme),
              const SizedBox(height: 24),
              _buildTypeToggle(theme),
              const SizedBox(height: 12),
              _buildAccountSelector(theme),
              const SizedBox(height: 12),
              _buildCategorySelector(theme),
              const SizedBox(height: 12),
              _buildDatePicker(theme),
              const SizedBox(height: 16),
            ] else ...[
              Text(
                'Point & Scan',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Scan a receipt, then review its total and item amounts.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.4),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 40),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  _buildScanAction(
                    'Camera',
                    AppIcons.camera,
                    () => _handleOCR(ImageSource.camera),
                    theme,
                    isPrimary: true,
                  ),
                  _buildScanAction(
                    'Gallery',
                    AppIcons.gallery,
                    () => _handleOCR(ImageSource.gallery),
                    theme,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScanHero(ThemeData theme) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.1)),
      ),
      child: Center(
        child: Icon(
          Icons.qr_code_scanner_rounded,
          size: 32,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildScanAction(
    String label,
    IconData icon,
    VoidCallback onTap,
    ThemeData theme, {
    bool isPrimary = false,
  }) {
    return InkWell(
      onTap: _scanning || _saving ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isPrimary
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isPrimary ? Colors.white : theme.colorScheme.onSurface,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: isPrimary ? Colors.white : theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Shared form widgets ───────────────────────────────────────────────────

  Future<void> _openCalculator() async {
    if (_saving) return;
    final amount = await showAmountCalculator(context, _amountCtrl.text.trim());
    if (!mounted || amount == null) return;
    setState(() {
      _amountCtrl.text = amount;
      _amountError = null;
    });
  }

  Widget _buildAmountInput(ThemeData theme) {
    return TextFormField(
      controller: _amountCtrl,
      focusNode: _amountFocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      inputFormatters: [
        TextInputFormatter.withFunction(
          (oldValue, newValue) =>
              RegExp(r'^\d*(\.\d{0,2})?$').hasMatch(newValue.text)
              ? newValue
              : oldValue,
        ),
      ],
      style: theme.textTheme.displayLarge?.copyWith(fontSize: 40),
      cursorHeight: 42,
      autofocus: widget.existing == null && widget.initialTab == 0,
      onChanged: (_) {
        if (_amountError != null) setState(() => _amountError = null);
      },
      decoration: InputDecoration(
        labelText: 'Amount',
        prefixText: '₹ ',
        hintText: '0.00',
        suffixIcon: IconButton(
          tooltip: 'Calculate amount',
          onPressed: _saving ? null : _openCalculator,
          icon: const Icon(AppIcons.calculator),
        ),
        errorText: _amountError,
        hintStyle: theme.textTheme.displayLarge?.copyWith(
          fontSize: 40,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        prefixStyle: theme.textTheme.displayMedium?.copyWith(
          color: theme.colorScheme.primary,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }

  Widget _buildAmountPreview(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color:
            (_type == 'expense' ? AppTheme.errorColor : AppTheme.successColor)
                .withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '₹ ${_amountCtrl.text}',
        style: GoogleFonts.inter(
          fontSize: 26,
          fontWeight: FontWeight.bold,
          color: _type == 'expense'
              ? AppTheme.errorColor
              : AppTheme.successColor,
        ),
      ),
    );
  }

  Widget _buildTypeToggle(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _buildTypePill('expense', 'Expense', theme),
          _buildTypePill('income', 'Income', theme),
        ],
      ),
    );
  }

  Widget _buildTypePill(String type, String label, ThemeData theme) {
    final isSelected =
        _type == type &&
        (widget.reviewIdentity == null || _reviewTypeConfirmed);
    final color = type == 'expense' ? AppTheme.expense : AppTheme.income;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _dirty = true;
            _type = type;
            _reviewTypeConfirmed = true;
            _selectedCategory = '';
            _categoryError = null;
          });
          _refreshCategories();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? theme.colorScheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              color: isSelected
                  ? color
                  : theme.colorScheme.onSurface.withOpacity(0.4),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountSelector(ThemeData theme) {
    return BlocBuilder<AccountBloc, AccountState>(
      builder: (context, state) {
        if (state is AccountLoaded) {
          final accounts = state.accounts;
          if (accounts.isEmpty) return const SizedBox.shrink();

          final validValue = accounts.any((a) => a.id == _selectedAccountId)
              ? _selectedAccountId
              : widget.reviewIdentity != null
              ? null
              : state.selectedAccountId ?? accounts.first.id;

          if (_selectedAccountId != validValue) {
            _selectedAccountId = validValue;
          }

          return DropdownButtonFormField<int>(
            value: validValue,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Account',
              prefixIcon: Icon(AppIcons.accounts),
            ),
            items: accounts
                .map(
                  (a) => DropdownMenuItem(
                    value: a.id,
                    child: Text(
                      a.bankName.isEmpty ? a.name : '${a.name} (${a.bankName})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() {
              _dirty = true;
              _selectedAccountId = v;
            }),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildCategorySelector(ThemeData theme) {
    return BlocBuilder<CategoryBloc, CategoryState>(
      builder: (context, state) {
        if (state is CategoryLoaded) {
          final categories = state.categories;
          if (categories.isEmpty) return const SizedBox.shrink();

          final value = categories.any((c) => c.name == _selectedCategory)
              ? _selectedCategory
              : null;

          return DropdownButtonFormField<String>(
            value: value,
            isExpanded: true,
            hint: const Text('Choose a category'),
            decoration: InputDecoration(
              errorText: _categoryError,
              labelText: 'Category',
              prefixIcon: Icon(AppIcons.categories),
            ),
            items: categories
                .map(
                  (c) => DropdownMenuItem(value: c.name, child: Text(c.name)),
                )
                .toList(),
            onChanged: (v) => setState(() {
              _dirty = true;
              _selectedCategory = v ?? '';
              _categoryError = null;
            }),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildDatePicker(ThemeData theme) {
    return GestureDetector(
      onTap: () async {
        final picked = await showAppDatePicker(
          title: 'Transaction date',
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime(1900),
          lastDate: DateTime(2100),
        );
        if (picked != null && mounted) {
          setState(() {
            _dirty = true;
            _selectedDate = picked;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.onSurface.withOpacity(0.2),
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(AppIcons.calendar, color: theme.colorScheme.primary, size: 20),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                DateFormat('d MMM yyyy').format(_selectedDate),
                style: theme.textTheme.bodyLarge,
              ),
            ),
            const Spacer(),
            Icon(
              AppIcons.chevron,
              color: theme.colorScheme.onSurface.withOpacity(0.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptPicker(ThemeData theme) {
    if (_receiptImagePath == null) {
      // No image yet — show dashed attach button
      return GestureDetector(
        onTap: _pickReceiptImage,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(
              color: Colors.teal.withOpacity(0.5),
              style: BorderStyle.solid,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(14),
            color: Colors.teal.withOpacity(0.04),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.attach_file_rounded,
                color: Colors.teal,
                size: 20,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Attach receipt (optional)',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.teal,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Image selected — show thumbnail with remove badge
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(AppIcons.transactions, color: Colors.teal, size: 16),
            const SizedBox(width: 6),
            Text(
              'Receipt attached',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.teal,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _pickReceiptImage,
              icon: const Icon(Icons.swap_horiz_rounded, size: 14),
              label: const Text('Change'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.teal,
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () {
            // Fullscreen viewer
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    ReceiptFullscreen(imagePath: _receiptImagePath!),
              ),
            );
          },
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ReceiptImage(
                  path: _receiptImagePath!,
                  width: double.infinity,
                  height: 180,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: () => setState(() => _receiptImagePath = null),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      AppIcons.close,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.zoom_in_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Tap to view',
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton(ThemeData theme) {
    return BlocBuilder<TransactionBloc, TransactionState>(
      builder: (context, state) {
        final isSaving = _saving;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_saveError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _saveError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    isSaving ||
                        _scanning ||
                        (_tabController.index == 1 && _amountCtrl.text.isEmpty)
                    ? null
                    : _save,
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        widget.existing != null
                            ? 'Save changes'
                            : _type == 'expense'
                            ? 'Save expense'
                            : 'Save income',
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _amountFocus.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _merchantCtrl.dispose();
    _ocrService.dispose();
    super.dispose();
  }

  List<Widget> _buildSplitSection(ThemeData theme) {
    final repo = context.read<TransactionRepository>();
    return [
      const SizedBox(height: 24),
      Text(
        'SPLIT BREAKDOWN',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 1.0,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 12),
      _SplitChildrenView(
        parentId: widget.existing!.id!,
        repo: repo,
        theme: theme,
      ),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Split children view — shown inside the Edit Transaction screen
// ─────────────────────────────────────────────────────────────────────────────
class _SplitChildrenView extends StatefulWidget {
  final int parentId;
  final TransactionRepository repo;
  final ThemeData theme;
  const _SplitChildrenView({
    required this.parentId,
    required this.repo,
    required this.theme,
  });
  @override
  State<_SplitChildrenView> createState() => _SplitChildrenViewState();
}

class _SplitChildrenViewState extends State<_SplitChildrenView> {
  late Future<List<TransactionModel>> _future;
  final _rupeeFmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '\u20B9',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = widget.repo.getChildTransactions(widget.parentId);
  }

  Future<void> _editChild(TransactionModel child) async {
    final updated = await showModalBottomSheet<TransactionModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SplitPartEditor(child: child),
    );
    if (updated == null || !mounted) return;
    await widget.repo.save(updated);
    if (mounted) setState(() => _reload());
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final dark = theme.brightness == Brightness.dark;
    return FutureBuilder<List<TransactionModel>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
        final children = snap.data!;

        return Container(
          decoration: BoxDecoration(
            color: dark
                ? AppTheme.darkElevated.withOpacity(0.6)
                : AppTheme.lightElevated.withOpacity(0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.expense.withOpacity(0.15)),
          ),
          child: Column(
            children: [
              // Header row
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.call_split_rounded,
                      size: 14,
                      color: AppTheme.expense.withOpacity(0.8),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${children.length} split parts',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppTheme.expense.withOpacity(0.8),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Tap to edit',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(
                          0.4,
                        ),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                thickness: 0.5,
                color: AppTheme.expense.withOpacity(0.1),
              ),
              // One row per child
              ...children.asMap().entries.map((e) {
                final idx = e.key;
                final child = e.value;
                final isLast = idx == children.length - 1;
                final label = child.note.isNotEmpty
                    ? child.note
                    : (child.merchant.isNotEmpty
                          ? child.merchant
                          : child.category);
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: isLast
                        ? const BorderRadius.only(
                            bottomLeft: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          )
                        : BorderRadius.zero,
                    onTap: () => _editChild(child),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: !isLast
                          ? BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: dark
                                      ? AppTheme.darkBorder
                                      : AppTheme.lightBorder,
                                  width: 0.5,
                                ),
                              ),
                            )
                          : null,
                      child: Row(
                        children: [
                          // Number bubble
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: AppTheme.expense.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${idx + 1}',
                                style: TextStyle(
                                  color: AppTheme.expense,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              label,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '-${_rupeeFmt.format(child.amount)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.expense,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            AppIcons.edit,
                            size: 12,
                            color: theme.colorScheme.onSurface.withOpacity(0.2),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

/// Owns the controllers for the entire sheet lifetime, including its exit animation.
class SplitPartEditor extends StatefulWidget {
  final TransactionModel child;
  const SplitPartEditor({super.key, required this.child});

  @override
  State<SplitPartEditor> createState() => _SplitPartEditorState();
}

class _SplitPartEditorState extends State<SplitPartEditor> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _amountCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
      text: widget.child.note.isNotEmpty
          ? widget.child.note
          : widget.child.merchant,
    );
    _amountCtrl = TextEditingController(
      text: widget.child.amount.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Edit Split Part',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Lunch with team',
                prefixIcon: Icon(Icons.label_outline_rounded),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '\u20B9 ',
                prefixIcon: Icon(Icons.currency_rupee_rounded),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final name = _nameCtrl.text.trim();
                  final amount =
                      double.tryParse(_amountCtrl.text.trim()) ??
                      widget.child.amount;
                  Navigator.pop(
                    context,
                    widget.child.copyWith(
                      note: name,
                      merchant: name,
                      amount: amount,
                    ),
                  );
                },
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
