import 'package:flutter/material.dart';

/// Functional icons: outlined by default; filled only for selected destinations.
abstract final class AppIcons {
  static const calculator = Icons.calculate_outlined;
  static const diagnostics = Icons.monitor_heart_outlined;
  static const share = Icons.ios_share_rounded;
  static const accounts = Icons.account_balance_wallet_outlined;
  static const accountsSelected = Icons.account_balance_wallet_rounded;
  static const add = Icons.add_rounded;
  static const appliances = Icons.home_repair_service_outlined;
  static const bank = Icons.account_balance_outlined;
  static const budget = Icons.pie_chart_outline_rounded;
  static const budgetSelected = Icons.pie_chart_rounded;
  static const calendar = Icons.calendar_today_outlined;
  static const camera = Icons.photo_camera_outlined;
  static const categories = Icons.category_outlined;
  static const chat = Icons.chat_bubble_outline_rounded;
  static const check = Icons.check_rounded;
  static const chevron = Icons.chevron_right_rounded;
  static const close = Icons.close_rounded;
  static const copy = Icons.copy_outlined;
  static const csv = Icons.table_chart_outlined;
  static const dateRange = Icons.date_range_outlined;
  static const delete = Icons.delete_outline_rounded;
  static const deleteForever = Icons.delete_forever_outlined;
  static const edit = Icons.edit_outlined;
  static const error = Icons.error_outline_rounded;
  static const expand = Icons.keyboard_arrow_down_rounded;
  static const filter = Icons.filter_list_rounded;
  static const gallery = Icons.photo_library_outlined;
  static const goals = Icons.savings_outlined;
  static const home = Icons.home_outlined;
  static const homeSelected = Icons.home_rounded;
  static const merchant = Icons.storefront_outlined;
  static const more = Icons.more_horiz_rounded;
  static const openExternal = Icons.open_in_new_rounded;
  static const payments = Icons.event_note_outlined;
  static const pdf = Icons.picture_as_pdf_outlined;
  static const recurring = Icons.repeat_rounded;
  static const refresh = Icons.refresh_rounded;
  static const reminder = Icons.notifications_outlined;
  static const remove = Icons.remove_circle_outline_rounded;
  static const reports = Icons.insert_chart_outlined_rounded;
  static const scan = Icons.document_scanner_outlined;
  static const search = Icons.search_rounded;
  static const settings = Icons.settings_outlined;
  static const success = Icons.check_circle_outline_rounded;
  static const tools = Icons.grid_view_outlined;
  static const transactions = Icons.receipt_long_outlined;
  static const transactionsSelected = Icons.receipt_long_rounded;
  static const voice = Icons.mic_none_rounded;

  static const double actionSize = 24;
  static const double detailSize = 20;
  static const double emptySize = 48;

  static Color actionColor(ThemeData theme) =>
      theme.brightness == Brightness.dark
      ? const Color(0xFFC4B5FD)
      : theme.colorScheme.primary;
  static Color dangerColor(ThemeData theme) =>
      theme.brightness == Brightness.dark
      ? const Color(0xFFFDA4AF)
      : theme.colorScheme.error;
}
