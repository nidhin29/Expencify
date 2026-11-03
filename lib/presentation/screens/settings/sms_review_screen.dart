import '../../widgets/page_loading.dart';
import '../../widgets/sms_correction_sheet.dart';
import 'package:flutter/material.dart';
import '../../../application/services/sms/sms_review_store.dart';
import '../../../application/services/sms/sms_parser_service.dart';
import '../../../domain/entities/transaction.dart';

class SmsReviewScreen extends StatefulWidget {
  const SmsReviewScreen({super.key});
  @override
  State<SmsReviewScreen> createState() => _SmsReviewScreenState();
}

class _SmsReviewScreenState extends State<SmsReviewScreen> {
  final store = SmsReviewStore();
  List<Map<String, Object?>>? rows;
  String? error;
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
      error = null;
    });
    try {
      final result = await store.pending();
      if (mounted && request == _request) {
        setState(() {
          rows = result;
          error = null;
        });
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => error = 'Could not load SMS. Try again.');
      }
    } finally {
      if (mounted && request == _request) setState(() => _refreshing = false);
    }
  }

  Future<void> _review(Map<String, Object?> row) async {
    final body = row['body'] as String;
    final parsed = await SmsParserService.parseSms(body);
    if (!mounted) return;
    await showSmsCorrection(
      context,
      TransactionModel(
        accountId: -1,
        amount: (parsed?['amount'] as num?)?.toDouble() ?? 0,
        type: parsed?['type'] as String? ?? '',
        category: '',
        merchant: parsed?['merchant'] as String? ?? '',
        note: 'Reviewed bank SMS',
        isSms: true,
        date: DateTime.parse(row['date'] as String),
      ),
      reviewIdentity: row['identity'] as String,
    );
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SMS to review')),
    body: LoadingFeedback(
      loading: _refreshing && rows != null,
      error: rows != null && error != null
          ? 'Could not refresh. Your previous data is still shown.'
          : null,
      onRetry: _load,
      child: error != null && rows == null
          ? Center(
              child: TextButton(onPressed: _load, child: Text(error!)),
            )
          : rows == null
          ? const PageLoading(label: 'Loading SMS to review')
          : rows!.isEmpty
          ? const Center(child: Text('All caught up'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: rows!.length,
                itemBuilder: (_, i) {
                  final row = rows![i];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row['sender'] as String,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(row['body'] as String),
                          const SizedBox(height: 8),
                          Text(row['reason'] as String),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            children: [
                              FilledButton(
                                onPressed: () => _review(row),
                                child: const Text('Review transaction'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  try {
                                    await store.dismiss(
                                      row['identity'] as String,
                                    );
                                    await _load();
                                  } catch (_) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        this.context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Could not dismiss. Try again.',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                                child: const Text('Ignore'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    ),
  );
}
