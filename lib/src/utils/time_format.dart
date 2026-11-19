/// Compact update times for lists. Older values use a local calendar date.
/// Future update timestamps are treated as "just now" to tolerate clock skew.
String formatRelativeTime(
  DateTime value, {
  DateTime? now,
  String languageCode = 'en',
  Duration relativeWindow = const Duration(days: 7),
}) {
  final elapsed = (now ?? DateTime.now()).difference(value);
  final zh = languageCode.startsWith('zh');
  if (elapsed < const Duration(minutes: 1)) return zh ? '刚刚' : 'just now';
  if (elapsed < relativeWindow) {
    if (elapsed.inHours < 1) {
      final minutes = elapsed.inMinutes;
      return zh ? '$minutes分钟前' : '$minutes min ago';
    }
    if (elapsed.inDays < 1) {
      final hours = elapsed.inHours;
      return zh ? '$hours小时前' : '$hours hr ago';
    }
    final days = elapsed.inDays;
    return zh ? '$days天前' : '$days ${days == 1 ? 'day' : 'days'} ago';
  }
  final local = value.toLocal();
  if (zh) return '${local.year}年${local.month}月${local.day}日';
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${pad(local.month)}-${pad(local.day)}';
}

/// Wall-clock age, including waits; never represents active execution time.
/// Uses at most two units so it fits task metadata rows.
String formatElapsedDuration(Duration value, {String languageCode = 'en'}) {
  final zh = languageCode.startsWith('zh');
  if (value < const Duration(minutes: 1)) return zh ? '不足1分钟' : '<1 min';
  if (value.inDays > 0) {
    final days = value.inDays;
    final hours = value.inHours.remainder(24);
    return zh
        ? '$days天${hours > 0 ? '$hours小时' : ''}'
        : '$days d${hours > 0 ? ' $hours hr' : ''}';
  }
  if (value.inHours > 0) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    return zh
        ? '$hours小时${minutes > 0 ? '$minutes分钟' : ''}'
        : '$hours hr${minutes > 0 ? ' $minutes min' : ''}';
  }
  return zh ? '${value.inMinutes}分钟' : '${value.inMinutes} min';
}
