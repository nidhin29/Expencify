import '../../widgets/page_loading.dart';
import 'package:expencify/presentation/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../application/services/reports/weekly_recap.dart';
import '../../../application/services/reports/insight_period.dart';
import '../../../application/services/notifications/budget_update_service.dart';
import '../../../domain/repositories/transaction_repository.dart';
import 'category_detail_screen.dart';

class WeeklyRecapScreen extends StatefulWidget {
  const WeeklyRecapScreen({super.key});
  @override
  State<WeeklyRecapScreen> createState() => _WeeklyRecapScreenState();
}

class _WeeklyRecapScreenState extends State<WeeklyRecapScreen> {
  WeeklyRecap? _data;
  bool _failed = false;
  bool _refreshing = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _refreshing = true;
      _failed = false;
    });
    try {
      final d = await WeeklyRecap.load(
        context.read<TransactionRepository>(),
        DateTime.now(),
      );
      if (mounted && request == _request) {
        setState(() {
          _data = d;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted && request == _request) setState(() => _failed = true);
    } finally {
      if (mounted && request == _request) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final money = BudgetUpdateService.amount;
    return Scaffold(
      appBar: AppBar(title: const Text('Weekly recap')),
      body: LoadingFeedback(
        loading: _refreshing && _data != null,
        error: _data != null && _failed
            ? 'Could not refresh. Your previous data is still shown.'
            : null,
        onRetry: _load,
        child: _failed && _data == null
            ? Center(
                child: TextButton(
                  onPressed: _load,
                  child: const Text('Could not load recap. Retry'),
                ),
              )
            : d == null
            ? const PageLoading(label: 'Loading weekly recap')
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      insightRangeLabel(d.from, d.to),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text('All accounts · Recorded expenses'),
                    const SizedBox(height: 20),
                    Card(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: .08),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Last week'),
                            Text(
                              money(d.total),
                              style: Theme.of(context).textTheme.headlineLarge,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              d.priorTotal == 0
                                  ? 'No recorded spending in the previous week.'
                                  : d.difference == 0
                                  ? 'The same recorded spending as the previous week.'
                                  : '${money(d.difference.abs())} ${d.difference > 0 ? 'more' : 'less'} than the previous week.',
                            ),
                            Text(
                              'Compared with ${insightRangeLabel(d.previousFrom, d.from.subtract(const Duration(microseconds: 1)))}',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (d.total == 0 && d.priorTotal == 0)
                      const Text('No expenses recorded in either week.')
                    else
                      Text(
                        'Category changes',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ...d.changes.map(
                      (e) => Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          title: Text(e.key),
                          subtitle: Text(
                            e.value == 0
                                ? 'Unchanged'
                                : '${money(e.value.abs())} ${e.value > 0 ? 'more' : 'less'}',
                          ),
                          trailing: const Icon(AppIcons.chevron),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CategoryDetailScreen(
                                  category: e.key,
                                  type: 'expense',
                                  from: d.from,
                                  to: d.to,
                                ),
                              ),
                            );
                            if (mounted) _load();
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
      ),
    );
  }
}
