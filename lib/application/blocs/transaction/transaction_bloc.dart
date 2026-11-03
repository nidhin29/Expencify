import '../../services/search/semantic_search_service.dart';
import '../../../domain/entities/transaction.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/repositories/transaction_repository.dart';
import '../../../domain/repositories/account_repository.dart';
import '../account/account_bloc.dart';
import '../account/account_event.dart';
import 'transaction_event.dart';
import 'transaction_state.dart';

import '../../services/notifications/budget_alert_service.dart';

class TransactionBloc extends Bloc<TransactionEvent, TransactionState> {
  final TransactionRepository _repository;
  final AccountBloc _accountBloc;
  final BudgetAlertService? _budgetAlerts;

  LoadTransactions? _lastFilter;

  TransactionBloc(
    this._repository,
    AccountRepository accountRepo,
    this._accountBloc, {
    BudgetAlertService? budgetAlerts,
  }) : _budgetAlerts = budgetAlerts,
       super(TransactionInitial()) {
    on<TransactionEvent>((event, emit) async {
      if (event is LoadTransactions) await _onLoadTransactions(event, emit);
      if (event is RefreshTransactions) {
        final f = _lastFilter ?? const LoadTransactions();
        await _onLoadTransactions(
          LoadTransactions(
            accountId: f.accountId,
            type: f.type,
            category: f.category,
            from: f.from,
            to: f.to,
            search: f.search,
            semantic: f.semantic,
            silent: true,
          ),
          emit,
        );
      }
      if (event is AddTransaction) await _onAddTransaction(event, emit);
      if (event is UpdateTransaction) await _onUpdateTransaction(event, emit);
      if (event is DeleteTransaction) await _onDeleteTransaction(event, emit);
      if (event is SplitTransactions) await _onSplitTransactions(event, emit);
    }, transformer: (events, mapper) => events.asyncExpand(mapper));
  }

  Future<void> _onSplitTransactions(
    SplitTransactions event,
    Emitter<TransactionState> emit,
  ) async {
    try {
      await _repository.replaceSplits(event.original.id!, event.parts);
      SemanticSearchService().schedule();

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
    final previousFilter = _lastFilter;
    _lastFilter = event;
    final sameFilter =
        previousFilter != null &&
        previousFilter.accountId == event.accountId &&
        previousFilter.type == event.type &&
        previousFilter.category == event.category &&
        previousFilter.from == event.from &&
        previousFilter.to == event.to &&
        previousFilter.search == event.search &&
        previousFilter.semantic == event.semantic;
    final previous = sameFilter && state is TransactionLoaded
        ? state as TransactionLoaded
        : null;
    if (!event.silent && previous != null) {
      emit(TransactionLoaded(previous.transactions, refreshing: true));
    }
    if (previous == null) {
      emit(TransactionLoading());
    }
    try {
      var transactions = await _repository.getTransactions(
        accountId: event.accountId,
        type: event.type,
        category: event.category,
        from: event.from,
        to: event.to,
        search: event.semantic ? null : event.search,
      );
      if (event.semantic && (event.search?.trim().isNotEmpty ?? false)) {
        final rows = await SemanticSearchService().search(
          transactions.map((t) => t.toMap()).toList(),
          event.search!,
        );
        transactions = rows.map(TransactionModel.fromMap).toList();
      }
      emit(TransactionLoaded(transactions));
    } catch (e) {
      emit(
        previous == null
            ? const TransactionError(
                'Could not load transactions. Please retry.',
              )
            : TransactionLoaded(
                previous.transactions,
                refreshError:
                    'Could not refresh. Your previous data is still shown.',
              ),
      );
    }
  }

  Future<void> _onAddTransaction(
    AddTransaction event,
    Emitter<TransactionState> emit,
  ) async {
    try {
      await _repository.saveWithChildren(
        event.transaction,
        event.splitChildren ?? [],
      );
      event.completion?.complete(true);
      SemanticSearchService().schedule();
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
            semantic: _lastFilter!.semantic,
            silent: true,
          ),
        );
      } else {
        add(const LoadTransactions(silent: true));
      }

      // Check for budget alerts
      try {
        await _budgetAlerts?.checkBudgets();
      } catch (_) {
        /* Financial commit succeeded; alerts are best effort. */
      }
    } catch (e) {
      if (event.completion?.isCompleted == false) {
        event.completion!.complete(false);
      }
      emit(TransactionError(e.toString()));
    }
  }

  Future<void> _onUpdateTransaction(
    UpdateTransaction event,
    Emitter<TransactionState> emit,
  ) async {
    try {
      await _repository.saveWithMerchantRename(event.transaction);
      event.completion?.complete(true);
      SemanticSearchService().schedule();
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
            semantic: _lastFilter!.semantic,
            silent: true,
          ),
        );
      } else {
        add(const LoadTransactions(silent: true));
      }

      // Check for budget alerts
      try {
        await _budgetAlerts?.checkBudgets();
      } catch (_) {
        /* Financial commit succeeded; alerts are best effort. */
      }
    } catch (e) {
      if (event.completion?.isCompleted == false) {
        event.completion!.complete(false);
      }
      emit(TransactionError(e.toString()));
    }
  }

  Future<void> _onDeleteTransaction(
    DeleteTransaction event,
    Emitter<TransactionState> emit,
  ) async {
    try {
      await _repository.delete(event.transaction.id!);
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
            semantic: _lastFilter!.semantic,
            silent: true,
          ),
        );
      } else {
        add(const LoadTransactions(silent: true));
      }

      // Check for budget alerts
      try {
        await _budgetAlerts?.checkBudgets();
      } catch (_) {
        /* Financial commit succeeded; alerts are best effort. */
      }
    } catch (e) {
      emit(TransactionError(e.toString()));
    }
  }
}
