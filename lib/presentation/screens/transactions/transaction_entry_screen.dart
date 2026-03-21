import 'dart:io';
import 'package:flutter/material.dart';
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
import 'package:expencify/application/services/ai/ai_service.dart';
import 'package:expencify/presentation/screens/transactions/receipt_fullscreen.dart';

class TransactionEntryScreen extends StatefulWidget {
  final int initialTab;
  final AIAction? aiAction;
  final TransactionModel? existing;
  const TransactionEntryScreen({
    super.key,
    this.initialTab = 0,
    this.aiAction,
    this.existing,
  });

  @override
  State<TransactionEntryScreen> createState() => _TransactionEntryScreenState();
}

class _TransactionEntryScreenState extends State<TransactionEntryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _ocrService = OCRService();

  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _merchantCtrl = TextEditingController();

  String _type = 'expense';
  String _selectedCategory = 'Food';
  DateTime _selectedDate = DateTime.now();
  int? _selectedAccountId;

  // Receipt image
  String? _receiptImagePath;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.existing != null ? 0 : widget.initialTab.clamp(0, 1),
    );

    if (widget.existing != null) {
      final e = widget.existing!;
      _amountCtrl.text = e.amount.toStringAsFixed(0);
      _type = e.type;
      _selectedCategory = e.category;
      _selectedDate = e.date;
      _selectedAccountId = e.accountId;
      _noteCtrl.text = e.note;
      _merchantCtrl.text = e.merchant;
      _receiptImagePath = e.imagePath;
    } else if (widget.aiAction != null) {
      if (widget.aiAction!.amount != null) {
        _amountCtrl.text = widget.aiAction!.amount.toString();
      }
      if (widget.aiAction!.category != null &&
          widget.aiAction!.category!.isNotEmpty) {
        _selectedCategory = widget.aiAction!.category!;
      }
    }

    _loadData();
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
                leading: const Icon(
                  Icons.camera_alt_rounded,
                  color: Colors.teal,
                ),
                title: const Text('Take Photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: Colors.teal,
                ),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              if (_receiptImagePath != null)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red,
                  ),
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
      setState(() => _receiptImagePath = picked.path);
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    context.read<CategoryBloc>().add(LoadCategories(type: _type));
    // Account data is managed by AccountBloc and we can access it via state
    final accountState = context.read<AccountBloc>().state;
    if (accountState is AccountLoaded && mounted) {
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
    final text = await _ocrService.pickAndRecognizeText(source);
    if (text == null || text.isEmpty) return;
    final result = _ocrService.parseReceipt(text);
    if (result['amount'] != null && mounted) {
      setState(() {
        _amountCtrl.text = (result['amount'] as double).toStringAsFixed(0);
        _type = 'expense';
      });
    }
  }

  Future<void> _save() async {
    final amountText = _amountCtrl.text.trim();
    final amount = double.tryParse(amountText);

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }

    if (_selectedAccountId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select an account')));
      return;
    }

    final t = TransactionModel(
      id: widget.existing?.id,
      accountId: _selectedAccountId!,
      amount: amount,
      type: _type,
      category: _selectedCategory,
      date: _selectedDate,
      note: _noteCtrl.text.trim(),
      merchant: _merchantCtrl.text.trim(),
      isOcr: _tabController.index == 1,
      isVoice: false,
      isSms: widget.existing?.isSms ?? false,
      imagePath: _receiptImagePath,
    );

    if (widget.existing != null) {
      context.read<TransactionBloc>().add(
        UpdateTransaction(t, widget.existing!),
      );
    } else {
      context.read<TransactionBloc>().add(AddTransaction(t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocListener<TransactionBloc, TransactionState>(
      listener: (context, state) {
        if (state is TransactionLoaded) {
          // Safety check: only pop if widget is mounted and navigator can pop
          if (mounted && Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        } else if (state is TransactionError) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.message)));
        }
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: Text(
            (widget.existing != null ? 'Edit Transaction' : 'Add Transaction')
                .toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.maybePop(context),
          ),
        ),
        body: Column(
          children: [
            _buildModeSwitcher(theme),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [_buildManualTab(theme), _buildScanTab(theme)],
              ),
            ),
          ],
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
          _buildModeItem(0, 'Manual', Icons.edit_rounded, theme),
          _buildModeItem(1, 'Scan', Icons.camera_rounded, theme),
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
        onTap: () => setState(() => _tabController.index = index),
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
          const SizedBox(height: 32),
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
          _buildSectionLabel(theme, 'Receipts'),
          const SizedBox(height: 12),
          _buildReceiptPicker(theme),
          // ── Split children (only when editing a split parent) ──
          if (widget.existing?.id != null) ..._buildSplitSection(theme),
          const SizedBox(height: 40),
          _buildSaveButton(theme),
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
    return TextFormField(
      controller: _merchantCtrl,
      decoration: const InputDecoration(
        hintText: 'Where did you spend?',
        prefixIcon: Icon(Icons.store_rounded, size: 20),
        labelText: 'Merchant',
      ),
    );
  }

  Widget _buildNoteInput(ThemeData theme) {
    return TextFormField(
      controller: _noteCtrl,
      decoration: const InputDecoration(
        hintText: 'Add a quick note...',
        prefixIcon: Icon(Icons.notes_rounded, size: 20),
        labelText: 'Notes',
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
              const SizedBox(height: 32),
              _buildSaveButton(theme),
            ] else ...[
              Text(
                'Point & Scan',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Snap a receipt photo and Expencify will extract the amounts for you automatically.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.4),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildScanAction(
                    'Camera',
                    Icons.camera_alt_rounded,
                    () => _handleOCR(ImageSource.camera),
                    theme,
                    isPrimary: true,
                  ),
                  const SizedBox(width: 16),
                  _buildScanAction(
                    'Gallery',
                    Icons.photo_library_rounded,
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
      onTap: onTap,
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

  Widget _buildAmountInput(ThemeData theme) {
    return Column(
      children: [
        Text(
          'AMOUNT',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 8),
        IntrinsicWidth(
          child: TextFormField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppTheme.darkTheme.textTheme.displayLarge?.copyWith(
              fontSize: 48,
              color: theme.colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              prefixText: '₹ ',
              prefixStyle: theme.textTheme.displaySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
              hintText: '0',
              hintStyle: theme.textTheme.displayLarge?.copyWith(
                fontSize: 48,
                color: theme.colorScheme.onSurface.withOpacity(0.1),
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
            ),
            textAlign: TextAlign.center,
            autofocus: true,
          ),
        ),
      ],
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
    final isSelected = _type == type;
    final color = type == 'expense' ? AppTheme.expense : AppTheme.income;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _type = type);
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

          _selectedAccountId ??= state.selectedAccountId ?? accounts.first.id;

          return DropdownButtonFormField<int>(
            value: _selectedAccountId,
            decoration: const InputDecoration(
              labelText: 'Account',
              prefixIcon: Icon(Icons.account_balance_wallet_rounded),
            ),
            items: accounts
                .map(
                  (a) => DropdownMenuItem(
                    value: a.id,
                    child: Text('${a.name} (${a.bankName})'),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _selectedAccountId = v),
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
              : categories.first.name;

          // Sync internal state if needed
          if (_selectedCategory != value) {
            _selectedCategory = value;
          }

          return DropdownButtonFormField<String>(
            value: value,
            decoration: const InputDecoration(
              labelText: 'Category',
              prefixIcon: Icon(Icons.category_rounded),
            ),
            items: categories
                .map(
                  (c) => DropdownMenuItem(value: c.name, child: Text(c.name)),
                )
                .toList(),
            onChanged: (v) =>
                setState(() => _selectedCategory = v ?? categories.first.name),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildDatePicker(ThemeData theme) {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (picked != null) setState(() => _selectedDate = picked);
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
            Icon(
              Icons.calendar_today_rounded,
              color: theme.colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              DateFormat('d MMM yyyy').format(_selectedDate),
              style: theme.textTheme.bodyLarge,
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right_rounded,
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
          height: 56,
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
              Text(
                'Attach Receipt Photo (optional)',
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.teal),
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
            const Icon(
              Icons.receipt_long_rounded,
              color: Colors.teal,
              size: 16,
            ),
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
                child: Image.file(
                  File(_receiptImagePath!),
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
                      Icons.close_rounded,
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
        final isSaving = state is TransactionLoading;
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: isSaving ? null : _save,
            child: isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save Transaction'),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
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
    final nameCtrl = TextEditingController(
      text: child.note.isNotEmpty ? child.note : child.merchant,
    );
    final amountCtrl = TextEditingController(
      text: child.amount.toStringAsFixed(0),
    );

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
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
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. Lunch with team',
                    prefixIcon: Icon(Icons.label_outline_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: amountCtrl,
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
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (saved == true && mounted) {
      final newNote = nameCtrl.text.trim();
      final newAmount = double.tryParse(amountCtrl.text.trim()) ?? child.amount;
      await widget.repo.save(
        child.copyWith(note: newNote, merchant: newNote, amount: newAmount),
      );
      setState(() => _reload());
    }
    nameCtrl.dispose();
    amountCtrl.dispose();
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
                            Icons.edit_outlined,
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
