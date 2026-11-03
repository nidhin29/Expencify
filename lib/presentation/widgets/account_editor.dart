import 'package:expencify/presentation/theme/app_icons.dart';
import 'form_save_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../domain/entities/account.dart';

class AccountEditor extends StatefulWidget {
  final Account? existing;
  final bool allowCash;
  final ValueChanged<Account>? onSave;
  final Future<bool> Function(Account)? onSubmit;
  const AccountEditor({
    super.key,
    this.existing,
    this.allowCash = true,
    this.onSave,
    this.onSubmit,
  });
  static bool isCash(Account account) =>
      account.bankName.toLowerCase() == 'cash' ||
      account.accountNumber.toUpperCase() == 'CASH';
  static bool hasSmsDetails(Account account) =>
      !isCash(account) &&
      account.bankName.trim().isNotEmpty &&
      RegExp(r'^\d{4}$').hasMatch(account.accountNumber);
  @override
  State<AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<AccountEditor> {
  static const banks = [
    'HDFC Bank',
    'SBI',
    'ICICI Bank',
    'Axis Bank',
    'BOB',
    'Canara Bank',
    'PNB',
    'Union Bank',
    'Kotak Mahindra Bank',
    'Bank of India',
    'IDFC FIRST Bank',
    'Federal Bank',
    'Indian Bank',
  ];
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _bankName, _digits, _balance;
  late bool _cash;
  String? _bank;
  Account? _submitted;
  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    _cash = a != null && AccountEditor.isCash(a);
    _name = TextEditingController(text: a?.name ?? '');
    _bankName = TextEditingController(text: _cash ? '' : a?.bankName ?? '');
    final suffix = a == null
        ? null
        : RegExp(r'\d{4}$').firstMatch(a.accountNumber)?.group(0);
    _digits = TextEditingController(
      text: _cash ? '' : suffix ?? a?.accountNumber ?? '',
    );
    _balance = TextEditingController(
      text: a?.balance.toStringAsFixed(2) ?? '0',
    );
    if (!_cash && a != null && a.bankName.isNotEmpty) {
      _bank = banks.contains(a.bankName) ? a.bankName : 'Other bank';
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _bankName, _digits, _balance]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.existing == null ? 'Add account' : 'Edit account',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(AppIcons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // An existing account keeps its type so editing cannot silently change SMS routing.
              if (widget.existing == null && widget.allowCash) ...[
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(AppIcons.bank),
                      label: Text('Bank account'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(AppIcons.accounts),
                      label: Text('Cash wallet'),
                    ),
                  ],
                  selected: {_cash},
                  onSelectionChanged: (value) =>
                      setState(() => _cash = value.single),
                ),
                const SizedBox(height: 20),
              ],
              if (!_cash) ...[
                DropdownButtonFormField<String>(
                  initialValue: _bank,
                  isExpanded: true,
                  menuMaxHeight: 320,
                  decoration: const InputDecoration(labelText: 'Bank'),
                  hint: const Text('Choose bank'),
                  items: [...banks, 'Other bank']
                      .map(
                        (bank) => DropdownMenuItem(
                          value: bank,
                          child: Text(
                            bank == 'BOB'
                                ? 'Bank of Baroda (BOB)'
                                : bank == 'SBI'
                                ? 'State Bank of India (SBI)'
                                : bank,
                          ),
                        ),
                      )
                      .toList(),
                  validator: (value) =>
                      value == null ? 'Choose your bank' : null,
                  onChanged: (value) => setState(() => _bank = value),
                ),
                if (_bank == 'Other bank') ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _bankName,
                    decoration: const InputDecoration(
                      labelText: 'Bank name',
                      hintText: 'As shown in your bank SMS',
                    ),
                    validator: (value) =>
                        value == null ||
                            value.trim().isEmpty ||
                            value.trim().toLowerCase() == 'cash'
                        ? 'Enter your bank name'
                        : null,
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _digits,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Last 4 account digits',
                    hintText: '1234',
                    helperText:
                        'Matches bank SMS to this account. No full account number needed.',
                    helperMaxLines: 4,
                  ),
                  validator: (value) =>
                      !RegExp(r'^\d{4}$').hasMatch(value ?? '')
                      ? 'Enter exactly 4 digits'
                      : null,
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: _cash
                      ? 'Wallet name (optional)'
                      : 'Nickname (optional)',
                  hintText: _cash ? 'My wallet' : 'Everyday spending',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _balance,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: InputDecoration(
                  labelText: widget.existing == null
                      ? 'Opening balance'
                      : 'Current balance',
                  prefixText: '₹ ',
                ),
                validator: (value) {
                  final amount = double.tryParse(value ?? '');
                  return amount == null || !amount.isFinite
                      ? 'Enter a valid balance'
                      : null;
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FormSaveButton(
                  filled: true,
                  onSaved: () => Navigator.pop(context, _submitted),
                  onSave: () async {
                    if (!_form.currentState!.validate()) return null;
                    final bank = _cash
                        ? 'Cash'
                        : _bank == 'Other bank'
                        ? _bankName.text.trim()
                        : _bank!;
                    final account = Account(
                      id: widget.existing?.id,
                      name: _name.text.trim().isEmpty
                          ? (_cash ? 'My wallet' : '$bank account')
                          : _name.text.trim(),
                      bankName: bank,
                      accountNumber: _cash ? 'CASH' : _digits.text,
                      balance: double.parse(_balance.text),
                    );
                    _submitted = account;
                    if (widget.onSubmit != null) {
                      return widget.onSubmit!(account);
                    }
                    widget.onSave?.call(account);
                    return true;
                  },
                  child: Text(
                    widget.existing == null ? 'Add account' : 'Save changes',
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
