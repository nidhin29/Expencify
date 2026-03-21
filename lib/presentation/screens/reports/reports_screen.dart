import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:expencify/domain/repositories/transaction_repository.dart';
import 'package:expencify/presentation/screens/reports/category_detail_screen.dart';
import 'package:expencify/application/blocs/account/account_bloc.dart';
import 'package:expencify/application/blocs/account/account_state.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _rupeeFmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  Map<String, double> _categoryTotals = {};
  String _selectedPeriod = 'This Month';
  DateTimeRange? _customRange;
  bool _loading = true;

  final List<Color> _pieColors = [
    const Color(0xFF6366F1),
    const Color(0xFFEC4899),
    const Color(0xFFF59E0B),
    const Color(0xFF10B981),
    const Color(0xFF3B82F6),
    const Color(0xFFEF4444),
    const Color(0xFF8B5CF6),
    const Color(0xFF06B6D4),
    const Color(0xFF84CC16),
    const Color(0xFFF97316),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final transactionRepo = context.read<TransactionRepository>();

    final now = DateTime.now();
    DateTime? from;
    DateTime? to;

    if (_selectedPeriod == 'This Month') {
      from = DateTime(now.year, now.month, 1);
      to = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    } else if (_selectedPeriod == 'Last Month') {
      from = DateTime(now.year, now.month - 1, 1);
      to = DateTime(now.year, now.month, 0, 23, 59, 59);
    } else if (_selectedPeriod == 'This Year') {
      from = DateTime(now.year, 1, 1);
      to = DateTime(now.year + 1, 1, 0, 23, 59, 59);
    } else if (_selectedPeriod == 'Custom' && _customRange != null) {
      from = _customRange!.start;
      to = _customRange!.end;
    } else if (_selectedPeriod == 'All Time') {
      from = null;
      to = null;
    }

    final accountState = context.read<AccountBloc>().state;
    final selectedId = accountState is AccountLoaded
        ? accountState.selectedAccountId
        : null;

    final categoryTotals = await transactionRepo.getCategoryTotals(
      type: 'expense',
      from: from,
      to: to,
      accountId: selectedId,
    );

    if (mounted) {
      setState(() {
        _categoryTotals = categoryTotals;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocListener<AccountBloc, AccountState>(
      listener: (context, state) {
        if (state is AccountLoaded) {
          _load();
        }
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            _buildSliverAppBar(theme),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: _buildPeriodSelector(theme),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_categoryTotals.isEmpty)
              SliverFillRemaining(
                child: _buildEmpty(theme, 'No expense data for this period'),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                sliver: SliverToBoxAdapter(child: _buildChartSection(theme)),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'Breakdown',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                sliver: _buildCategoryList(theme),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(ThemeData theme) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: theme.scaffoldBackgroundColor,
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: false,
        titlePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        title: Text(
          'Insights',
          style: theme.textTheme.displaySmall?.copyWith(fontSize: 24),
        ),
      ),
    );
  }

  Widget _buildPeriodSelector(ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          ...['This Month', 'Last Month', 'This Year', 'All Time'].map((p) {
            final isSelected = _selectedPeriod == p;
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () {
                  if (!isSelected) {
                    setState(() {
                      _selectedPeriod = p;
                      _customRange = null;
                    });
                    _load();
                  }
                },
                child: _buildPeriodChip(theme, p, isSelected),
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: _showCustomRangePicker,
              child: _buildPeriodChip(
                theme,
                _selectedPeriod == 'Custom' && _customRange != null
                    ? '${DateFormat('MMM d').format(_customRange!.start)} - ${DateFormat('MMM d').format(_customRange!.end)}'
                    : 'Custom...',
                _selectedPeriod == 'Custom',
                icon: Icons.calendar_today_rounded,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodChip(
    ThemeData theme,
    String label,
    bool isSelected, {
    IconData? icon,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: isSelected
                  ? Colors.white
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCustomRangePicker() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Theme.of(context).colorScheme.primary,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (range != null) {
      setState(() {
        _selectedPeriod = 'Custom';
        _customRange = range;
      });
      _load();
    }
  }

  Widget _buildChartSection(ThemeData theme) {
    final entries = _categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold(0.0, (sum, e) => sum + e.value);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TOTAL SPENT',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _rupeeFmt.format(total),
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${entries.length} Cats',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text(
            'DISTRIBUTION',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 48,
              child: Row(
                children: entries.map((e) {
                  final pct = total > 0 ? (e.value / total) : 0.0;
                  final color =
                      _pieColors[entries.indexOf(e) % _pieColors.length];
                  if (pct < 0.01) {
                    return const SizedBox.shrink(); // Hide tiny slices
                  }
                  return Expanded(
                    flex: (pct * 100).round(),
                    child: Container(
                      color: color,
                      child: pct > 0.1
                          ? Center(
                              child: Icon(
                                _getCategoryIcon(e.key),
                                color: Colors.white,
                                size: 16,
                              ),
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Legend (Top 3)
          Row(
            children: entries.take(3).map((e) {
              final color = _pieColors[entries.indexOf(e) % _pieColors.length];
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      e.key,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryList(ThemeData theme) {
    final entries = _categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold(0.0, (sum, e) => sum + e.value);

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, i) {
        final entry = entries[i];
        final pct = total > 0 ? (entry.value / total) : 0.0;
        final color = _pieColors[i % _pieColors.length];

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildCategoryCard(theme, entry.key, entry.value, pct, color),
        );
      }, childCount: entries.length),
    );
  }

  Widget _buildCategoryCard(
    ThemeData theme,
    String name,
    double amount,
    double pct,
    Color color,
  ) {
    return InkWell(
      onTap: () {
        DateTime? from;
        DateTime? to;
        final now = DateTime.now();
        if (_selectedPeriod == 'This Month') {
          from = DateTime(now.year, now.month, 1);
          to = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        } else if (_selectedPeriod == 'Last Month') {
          from = DateTime(now.year, now.month - 1, 1);
          to = DateTime(now.year, now.month, 0, 23, 59, 59);
        } else if (_selectedPeriod == 'This Year') {
          from = DateTime(now.year, 1, 1);
          to = DateTime(now.year + 1, 1, 0, 23, 59, 59);
        } else if (_selectedPeriod == 'Custom' && _customRange != null) {
          from = _customRange!.start;
          to = _customRange!.end;
        }

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CategoryDetailScreen(
              category: name,
              type: 'expense',
              from: from,
              to: to,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: theme.colorScheme.onSurface.withOpacity(0.05),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(_getCategoryIcon(name), color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${(pct * 100).toStringAsFixed(1)}% of total',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  _rupeeFmt.format(amount),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: color.withOpacity(0.08),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    category = category.toLowerCase();
    if (category.contains('food')) {
      return Icons.restaurant_rounded;
    }
    if (category.contains('car') || category.contains('transport')) {
      return Icons.directions_car_rounded;
    }
    if (category.contains('home')) {
      return Icons.home_rounded;
    }
    if (category.contains('shop')) {
      return Icons.shopping_bag_rounded;
    }
    if (category.contains('bill')) {
      return Icons.receipt_rounded;
    }
    if (category.contains('health')) {
      return Icons.medical_services_rounded;
    }
    if (category.contains('entertain')) {
      return Icons.movie_rounded;
    }
    return Icons.category_rounded;
  }

  Widget _buildEmpty(ThemeData theme, String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 80,
              color: theme.colorScheme.primary.withOpacity(0.1),
            ),
            const SizedBox(height: 24),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.4),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
