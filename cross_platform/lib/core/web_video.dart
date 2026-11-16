import 'protocol.dart';

class WebVideo {
  const WebVideo(this.url, this.title, this.mime);
  final Uri url;
  final String title, mime;
  static WebVideo? parse(dynamic value) {
    if (value is! Map || value['url'] is! String) return null;
    final raw = value['url'] as String;
    if (raw.length > 8192 || raw.contains(RegExp(r'[\x00-\x20]'))) return null;
    final url = Uri.tryParse(raw);
    if (url == null ||
        !['http', 'https'].contains(url.scheme) ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty) {
      return null;
    }
    final supplied = '${value['mime'] ?? ''}'
        .toLowerCase()
        .split(';')
        .first
        .trim();
    const allowed = [
      'video/mp4',
      'video/webm',
      'video/quicktime',
      'application/vnd.apple.mpegurl',
      'application/x-mpegurl',
    ];
    final inferred = {
      'mp4': 'video/mp4',
      'm4v': 'video/mp4',
      'm3u8': 'application/vnd.apple.mpegurl',
      'webm': 'video/webm',
      'mov': 'video/quicktime',
    }[url.path.split('.').last.toLowerCase()];
    final mime = allowed.contains(supplied) ? supplied : inferred;
    if (mime == null) return null;
    final text = '${value['title'] ?? ''}'.trim();
    return WebVideo(
      url,
      text.isEmpty
          ? 'Web videosu'
          : text.substring(0, text.length.clamp(0, 160)),
      mime,
    );
  }

  Json get payload => {
    'target': url.toString(),
    'title': title,
    'mimeType': mime,
    'loop': false,
  };
}
