/// HTTP client for the fooqt remote agent protocol (server/remote_agent.py).
///
/// Two token levels:
///   * master token  - desktop only, never stored here
///   * client token  - obtained via POST /register with a one-time pairing
///     code, persisted in secure storage (flutter_secure_storage)
///
/// All library endpoints use the client token; the agent validates it
/// against its devices.json.

library;

import 'dart:convert';

import 'package:http/http.dart' as http;

class AgentError implements Exception {
  final int status;
  final String message;
  AgentError(this.status, this.message);
  @override
  String toString() => 'AgentError($status): $message';
}

class Track {
  final String path;
  final String? artist;
  final String? title;
  final String? album;
  final double? duration;
  final double mtime;
  final int size;
  Track.fromJson(Map j)
      : path = j['p'] as String,
        artist = j['artist'] as String?,
        title = j['title'] as String?,
        album = j['album'] as String?,
        duration = (j['dur'] as num?)?.toDouble(),
        mtime = (j['mt'] as num?)?.toDouble() ?? 0,
        size = (j['sz'] as num?)?.toInt() ?? 0;
}

class FooFloApiClient {
  final Uri base; // http://host:port
  final String clientToken;
  final http.Client _http = http.Client();

  FooFloApiClient(this.base, this.clientToken);

  Future<dynamic> _req(String method, String path,
      {Map<String, dynamic>? body, Map<String, String>? query}) async {
    var uri = base.replace(path: path, queryParameters: query);
    http.Response res;
    if (method == 'GET') {
      res = await _http.get(uri, headers: {'X-Fooqt-Token': clientToken});
    } else {
      res = await _http.post(uri,
          headers: {
            'X-Fooqt-Token': clientToken,
            'Content-Type': 'application/json'
          },
          body: jsonEncode(body ?? {}));
    }
    final data = jsonDecode(res.body);
    if (res.statusCode != 200 || data['ok'] != true) {
      throw AgentError(res.statusCode, data['error'] ?? 'request failed');
    }
    return data;
  }

  /// Unauthenticated endpoints -------------------------------------------------

  static Future<Map> ping(Uri base) async {
    final res = await http.get(base.replace(path: '/ping'));
    return jsonDecode(res.body);
  }

  /// Exchange a one-time pairing code for a long-lived client token.
  static Future<String> register(Uri base, String code, String deviceName) async {
    final res = await http.post(base.replace(path: '/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': code, 'name': deviceName}));
    final data = jsonDecode(res.body);
    if (res.statusCode != 200 || data['ok'] != true) {
      throw AgentError(res.statusCode, data['error'] ?? 'pairing failed');
    }
    return data['client_token'] as String;
  }

  /// Library endpoints --------------------------------------------------------

  /// Start (or reuse) an incremental scan of `root`. `known` maps remote
  /// path -> [mtime, size] fingerprints. Returns the scan id to poll.
  Future<String> scan(String id, String root, Map<String, List> known) async {
    await _req('POST', '/scan', body: {'id': id, 'root': root, 'known': known});
    return id;
  }

  Future<Map> progress(String scanId, int cursor) async {
    return await _req('GET', '/progress',
        query: {'id': scanId, 'cursor': '$cursor'}) as Map;
  }

  Future<void> forget(String scanId) async {
    await _req('POST', '/forget', body: {'id': scanId});
  }

  /// Stream URL for playback (just_audio handles Range requests itself).
  Uri fileUri(String path) =>
      base.replace(path: '/file', queryParameters: {'path': path});

  Map<String, String> get audioHeaders => {'X-Fooqt-Token': clientToken};

  void dispose() => _http.close();
}