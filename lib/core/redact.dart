/// URL redaction for screenshots and diagnostics.
///
/// Playlist URLs routinely carry credentials (`user:pass@host`), access tokens
/// or signed query strings. The playback info sheet is meant to be copied into
/// bug reports, so it shows the host and the last path segment (usually a
/// file name) but never the secret parts.
String redactUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
    // A local path or something unparsable: keep only the file name.
    final parts = trimmed.split(RegExp(r'[/\\]'));
    final name = parts.isEmpty ? trimmed : parts.last;
    return name.length <= 64 ? name : '…';
  }
  final port = uri.hasPort ? ':${uri.port}' : '';
  final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  final tail = segments.isEmpty ? '' : '/…/${_shorten(segments.last)}';
  return '${uri.scheme}://${uri.host}$port$tail';
}

String _shorten(String value) {
  if (value.length <= 40) {
    return value;
  }
  return '${value.substring(0, 16)}…${value.substring(value.length - 12)}';
}
