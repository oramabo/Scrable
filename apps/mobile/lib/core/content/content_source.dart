import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Reads text documents by relative path. Bundled assets, the CDN and test
/// maps all implement it.
abstract class ContentSource {
  const ContentSource();

  /// Returns the document or `null` when it does not exist / cannot be read.
  Future<String?> readText(String path);
}

class AssetContentSource extends ContentSource {
  const AssetContentSource([this.bundle]);

  final AssetBundle? bundle;

  @override
  Future<String?> readText(String path) async {
    try {
      return await (bundle ?? rootBundle).loadString(path);
    } on FlutterError {
      return null;
    } catch (_) {
      return null;
    }
  }
}

class HttpContentSource extends ContentSource {
  HttpContentSource(this.baseUrl, {http.Client? client, this.timeout = const Duration(seconds: 15)})
      : client = client ?? http.Client();

  final String baseUrl;
  final http.Client client;
  final Duration timeout;

  Uri resolve(String path) {
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse(base).resolve(path);
  }

  @override
  Future<String?> readText(String path) async {
    try {
      final res = await client.get(resolve(path)).timeout(timeout);
      if (res.statusCode != 200) return null;
      return res.body;
    } catch (_) {
      return null;
    }
  }
}

/// In-memory source for tests.
class MapContentSource extends ContentSource {
  MapContentSource([Map<String, String>? docs]) : docs = docs ?? {};
  final Map<String, String> docs;
  int reads = 0;

  @override
  Future<String?> readText(String path) async {
    reads++;
    return docs[path];
  }
}
