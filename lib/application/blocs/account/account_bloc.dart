import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../domain/repositories/account_repository.dart';
import 'account_event.dart';
import 'account_state.dart';

class AccountBloc extends Bloc<AccountEvent, AccountState> {
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
    emit(AccountLoading());
    try {
      final accounts = await _repository.getAll();
      final totalBalance = await _repository.getTotalBalance();

      final prefs = await SharedPreferences.getInstance();
      final selectedId = prefs.getInt('selected_account_id');

      emit(
        AccountLoaded(
          accounts: accounts,
          selectedAccountId: selectedId,
          totalBalance: totalBalance,
        ),
      );
    } catch (e) {
      emit(AccountError(e.toString()));
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
    try {
      await _repository.save(event.account);
      add(LoadAccounts());
    } catch (e) {
      emit(AccountError(e.toString()));
    }
  }

  Future<void> _onUpdateAccount(
    UpdateAccount event,
    Emitter<AccountState> emit,
  ) async {
    try {
      await _repository.save(event.account);
      add(LoadAccounts());
    } catch (e) {
      emit(AccountError(e.toString()));
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
