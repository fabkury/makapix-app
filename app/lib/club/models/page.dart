/// A cursor-paginated response: `{ "items": [...], "next_cursor": "..."|null }`.
class Page<T> {
  final List<T> items;
  final String? nextCursor;
  const Page({required this.items, this.nextCursor});

  bool get atEnd => nextCursor == null;

  factory Page.fromJson(Map<String, dynamic> j, T Function(Map<String, dynamic>) item) {
    final raw = (j['items'] as List?) ?? const [];
    return Page(
      items: raw.map((e) => item((e as Map).cast<String, dynamic>())).toList(),
      nextCursor: j['next_cursor'] as String?,
    );
  }
}
