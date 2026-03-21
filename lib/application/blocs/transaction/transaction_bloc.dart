import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/repositories/transaction_repository.dart';
import '../../../domain/repositories/account_repository.dart';
import '../account/account_bloc.dart';
import '../account/account_event.dart';
import 'transaction_event.dart';
import 'transaction_state.dart';
import '../../../domain/entities/transaction.dart';

class TransactionBloc extends Bloc<TransactionEvent, TransactionState> {
  final TransactionRepository _repository;
  final AccountRepository _accountRepo;
  final AccountBloc _accountBloc;

  LoadTransactions? _lastFilter;

  TransactionBloc(this._repository, this._accountRepo, this._accountBloc)
    : super(TransactionInitial()) {
    on<LoadTransactions>(_onLoadTransactions);
    on<AddTransaction>(_onAddTransaction);
    on<UpdateTransaction>(_onUpdateTransaction);
    on<DeleteTransaction>(_onDeleteTransaction);
    on<SplitTransactions>(_onSplitTransactions);
  }

  Future<void> _onSplitTransactions(
    SplitTransactions event,
    Emitter<TransactionState> emit,
  ) async {
    try {
      // Keep original transaction as-is. Split state is shown via child rows with parentId.
      final original = event.original;

      // 2. Save parts linked to original
      for (final part in event.parts) {
        await _repository.save(part.copyWith(parentId: original.id));
      }

      if (_lastFilter != null) {
        add(_lastFilter!);
      } else {
        add(const LoadTransactions());
      }
    } catch (e) {
      emit(TransactionError(e.toString()));
    }
  }

  Future<void> _onLoadTransactions(
    LoadTransactions event,
    Emitter<TransactionState> emit,
  ) async {
    _lastFilter = event;
    if (!event.silent) {
      emit(TransactionLoading());
    }
    try {
      final transactions = await _repository.getTransactions(
        accountId: event.accountId,
        type: event.type,
        category: event.category,
        from: event.from,
        to: event.to,
        search: event.search,
      );
      emit(TransactionLoaded(transactions));
    } catch (e) {
      emit(TransactionError(e.toString()));
    }
  }

  Future<void> _onAddTransaction(
    AddTransaction event,
    Emitter<TransactionState> emit,
  ) async {
    try {
      final parentId = await _repository.save(event.transaction);

      if (event.splitChildren != null && event.splitChildren!.isNotEmpty) {
        for (final child in event.splitChildren!) {
          await _repository.save(child.copyWith(parentId: parentId));
        }
      }

      // Apply balance effect
      final delta = event.transaction.type == 'income'
          ? event.transaction.amount
          : -event.transaction.amount;
      await _accountRepo.updateBalance(event.transaction.accountId, delta);
      _accountBloc.add(LoadAccounts()); // ← refresh Net Balance card

      if (_lastFilter != null) {
        add(
          LoadTransactions(
            accountId: _lastFilter!.accountId,
            type: _lastFilter!.type,
            category: _lastFilter!.category,
            from: _lastFilter!.from,
            to: _lastFilter!.to,
            search: _lastFilter!.search,
            silent: true,
          ),
        );
      } else {
        add(const LoadTransactions(silent: true));
      }
    } catch (e) {
      emit(TransactionError(e.toString()));
    }
  }

  Future<void> _onUpdateTransaction(
    UpdateTransaction event,
    Emitter<TransactionState> emit,
  ) async {
    try {
      final old = event.oldTransaction;
      final newT = event.transaction;

      // 1. If this is a split child, we must update the parent's amount by the difference
      if (old.parentId != null && newT.parentId != null) {
        final parent = await _repository.getById(old.parentId!);
        if (parent != null) {
          final diff = newT.amount - old.amount;
          final newParentAmount = parent.amount + diff;
          await _repository.save(parent.copyWith(amount: newParentAmount));
        }
      }

      // 1.5 If this is a split PARENT, and its amount changed, we must adjust a child to balance it!
      if (old.parentId == null &&
          newT.parentId == null &&
          old.amount != newT.amount &&
          old.id != null) {
        final children = await _repository.getChildTransactions(old.id!);
        if (children.isNotEmpty) {
          double childSum = children.fold(0, (sum, c) => sum + c.amount);
          double diff = newT.amount - childSum;

          if (diff != 0) {
            TransactionModel? targetChild;
            for (var c in children) {
              if (c.category == 'Other' || c.merchant.contains('(Other)')) {
                targetChild = c;
                break;
              }
            }

            if (targetChild != null) {
              double newAmt = targetChild.amount + diff;
              if (newAmt <= 0) {
                await _repository.delete(targetChild.id!);
              } else {
                await _repository.save(targetChild.copyWith(amount: newAmt));
              }
            } else if (diff > 0) {
              await _repository.save(
                TransactionModel(
                  accountId: newT.accountId,
                  amount: diff,
                  category: 'Other',
                  merchant: newT.merchant.isNotEmpty
                      ? '${newT.merchant} (Other)'
                      : 'Other Items',
                  date: newT.date,
                  type: newT.type,
                  parentId: newT.id,
                ),
              );
            } else {
              // diff is negative, no 'Other' child to dock from. Dock from the largest child.
              targetChild = children.reduce(
                (a, b) => a.amount > b.amount ? a : b,
              );
              double newAmt = targetChild.amount + diff;
              if (newAmt <= 0) {
                await _repository.delete(targetChild.id!);
              } else {
                await _repository.save(targetChild.copyWith(amount: newAmt));
              }
            }
          }
        }
      }

      // 2. Reverse old effect
      final oldDelta = old.type == 'income' ? -old.amount : old.amount;
      await _accountRepo.updateBalance(old.accountId, oldDelta);

      // 3. Update record
      await _repository.save(newT);

      // 4. Apply new effect
      final newDelta = newT.type == 'income' ? newT.amount : -newT.amount;
      await _accountRepo.updateBalance(newT.accountId, newDelta);
      _accountBloc.add(LoadAccounts()); // ← refresh Net Balance card

      if (_lastFilter != null) {
        add(
          LoadTransactions(
            accountId: _lastFilter!.accountId,
            type: _lastFilter!.type,
            category: _lastFilter!.category,
            from: _lastFilter!.from,
            to: _lastFilter!.to,
            search: _lastFilter!.search,
            silent: true,
          ),
        );
      } else {
        add(const LoadTransactions(silent: true));
      }
    } catch (e) {
      emit(TransactionError(e.toString()));
    }
  }

  Future<void> _onDeleteTransaction(
    DeleteTransaction event,
    Emitter<TransactionState> emit,
  ) async {
    try {
      // Reverse effect
      final t = event.transaction;
      final delta = t.type == 'income' ? -t.amount : t.amount;
      await _accountRepo.updateBalance(t.accountId, delta);
      await _repository.delete(t.id!);
      _accountBloc.add(LoadAccounts()); // ← refresh Net Balance card

      if (_lastFilter != null) {
        add(
          LoadTransactions(
            accountId: _lastFilter!.accountId,
            type: _lastFilter!.type,
            category: _lastFilter!.category,
            from: _lastFilter!.from,
            to: _lastFilter!.to,
            search: _lastFilter!.search,
            silent: true,
          ),
        );
      } else {
        add(const LoadTransactions(silent: true));
      }
    } catch (e) {
      emit(TransactionError(e.toString()));
    }
  }
}
