import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../domain/repositories/account_repository.dart';
import 'account_event.dart';
import 'account_state.dart';

class AccountBloc extends Bloc<AccountEvent, AccountState> {
  AccountLoaded? _lastLoaded;
  int _loadRevision = 0;
  final AccountRepository _repository;

  AccountBloc(this._repository) : super(AccountInitial()) {
    on<LoadAccounts>(_onLoadAccounts);
    on<SelectAccount>(_onSelectAccount);
    on<AddAccount>(_onAddAccount);
    on<UpdateAccount>(_onUpdateAccount);
    on<DeleteAccount>(_onDeleteAccount);
    on<UpdateAccountBalance>(_onUpdateAccountBalance);
  }

  Future<void> _onLoadAccounts(
    LoadAccounts event,
    Emitter<AccountState> emit,
  ) async {
    final request = ++_loadRevision;
    final previous = state is AccountLoaded
        ? state as AccountLoaded
        : _lastLoaded;
    emit(
      previous == null
          ? AccountLoading()
          : AccountLoaded(
              accounts: previous.accounts,
              selectedAccountId: previous.selectedAccountId,
              totalBalance: previous.totalBalance,
              refreshing: true,
            ),
    );
    try {
      final accounts = await _repository.getAll();
      final totalBalance = await _repository.getTotalBalance();

      final prefs = await SharedPreferences.getInstance();
      var selectedId = prefs.getInt('selected_account_id');
      if (selectedId != null && !accounts.any((a) => a.id == selectedId)) {
        selectedId = null;
        await prefs.remove('selected_account_id');
      }

      if (emit.isDone || request != _loadRevision) return;
      emit(
        AccountLoaded(
          accounts: accounts,
          selectedAccountId: selectedId,
          totalBalance: totalBalance,
        ),
      );
      if (state is AccountLoaded) _lastLoaded = state as AccountLoaded;
    } catch (e) {
      if (emit.isDone || request != _loadRevision) return;
      emit(
        previous == null
            ? AccountError('Could not load accounts. Try again.')
            : AccountLoaded(
                accounts: previous.accounts,
                selectedAccountId: previous.selectedAccountId,
                totalBalance: previous.totalBalance,
                refreshError:
                    'Could not refresh. Your previous data is still shown.',
              ),
      );
    }
  }

  Future<void> _onSelectAccount(
    SelectAccount event,
    Emitter<AccountState> emit,
  ) async {
    final currentState = state;
    if (currentState is AccountLoaded) {
      final prefs = await SharedPreferences.getInstance();
      if (event.id != null) {
        await prefs.setInt('selected_account_id', event.id!);
      } else {
        await prefs.remove('selected_account_id');
      }

      emit(
        AccountLoaded(
          accounts: currentState.accounts,
          selectedAccountId: event.id,
          totalBalance: currentState.totalBalance,
        ),
      );
    }
  }

  Future<void> _onAddAccount(
    AddAccount event,
    Emitter<AccountState> emit,
  ) async {
    var persisted = false;
    try {
      await _repository.save(event.account);
      persisted = true;
      add(LoadAccounts());
    } catch (e) {
      emit(AccountError(e.toString()));
    } finally {
      final completion = event.completion;
      if (completion != null && !completion.isCompleted) {
        completion.complete(persisted);
      }
    }
  }

  Future<void> _onUpdateAccount(
    UpdateAccount event,
    Emitter<AccountState> emit,
  ) async {
    var persisted = false;
    try {
      await _repository.save(event.account);
      persisted = true;
      add(LoadAccounts());
    } catch (e) {
      emit(AccountError(e.toString()));
    } finally {
      final completion = event.completion;
      if (completion != null && !completion.isCompleted) {
        completion.complete(persisted);
      }
    }
  }

  Future<void> _onDeleteAccount(
    DeleteAccount event,
    Emitter<AccountState> emit,
  ) async {
    try {
      await _repository.delete(event.id);
      add(LoadAccounts());
    } catch (e) {
      emit(AccountError(e.toString()));
    }
  }

  Future<void> _onUpdateAccountBalance(
    UpdateAccountBalance event,
    Emitter<AccountState> emit,
  ) async {
    try {
      await _repository.updateBalance(event.accountId, event.delta);
      add(LoadAccounts());
    } catch (e) {
      emit(AccountError(e.toString()));
    }
  }
}
