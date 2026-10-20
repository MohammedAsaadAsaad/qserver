import 'quds_request.dart';

/// Offset pagination parsed from `page` / `per_page` (or `perPage`) query params.
///
/// Helpers only — existing handlers that return a raw map are unchanged.
class Paginator {
  final int page;
  final int perPage;
  final int total;

  const Paginator({
    required this.page,
    required this.perPage,
    this.total = 0,
  });

  int get offset => (page - 1) * perPage;

  int get lastPage {
    if (perPage <= 0) return 1;
    if (total <= 0) return 1;
    return ((total + perPage - 1) ~/ perPage).clamp(1, 1 << 30);
  }

  Map<String, dynamic> get meta => {
        'page': page,
        'perPage': perPage,
        'total': total,
        'lastPage': lastPage,
      };

  factory Paginator.fromRequest(
    QudsRequest request, {
    int total = 0,
    int defaultPerPage = 15,
    int maxPerPage = 100,
  }) {
    var page = int.tryParse(request.query('page') ?? '') ?? 1;
    if (page < 1) page = 1;
    var per = int.tryParse(
          request.query('per_page') ?? request.query('perPage') ?? '',
        ) ??
        defaultPerPage;
    if (per < 1) per = defaultPerPage;
    if (per > maxPerPage) per = maxPerPage;
    return Paginator(page: page, perPage: per, total: total);
  }
}
