import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Debug diagnostics: buffers events, catches uncaught errors, and uploads
/// the report to the LAN collector (server/report_collector.py).
class Diag {
  static final Diag instance = Diag._();
  Diag._();

  final List<String> lines = [];
  final DateTime started = DateTime.now();
  String device = 'unknown';
  Uri? collector; // set from UI once known; auto-discovered default below

  void log(String msg) {
    final t = DateTime.now().difference(started).inMilliseconds / 1000.0;
    lines.add('[${t.toStringAsFixed(2)}s] $msg');
    debugPrint('FOOFLOO: ${lines.last}');
  }

  Future<void> flush({String? reason}) async {
    final url = collector ?? Uri.parse('http://192.168.88.29:45699/report');
    if (reason != null) log('flush: $reason');
    try {
      final res = await http
          .post(url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'device': device,
                'lines': lines,
              }))
          .timeout(const Duration(seconds: 5));
      log('report sent -> ${res.statusCode}');
    } catch (e) {
      log('report upload failed: $e');
      // last resort: write locally so `adb logcat`/file pull still works
      try {
        final f = File('/tmp/foofloo-report.txt');
        await f.writeAsString(lines.join('\n'));
        log('report saved to ${f.path}');
      } catch (_) {}
    }
  }

  /// Wrap runApp: every uncaught async error gets logged + uploaded.
  static void runGuarded(void Function() body) {
    runZonedGuarded(() {
      body();
    }, (e, st) {
      instance.log('UNCAUGHT: $e');
      instance.log('STACK: ${st.toString().split('\n').take(6).join(' | ')}');
      instance.flush(reason: 'uncaught error');
    });
  }
}

/// Hostname of this device (best effort).
Future<String> deviceName() async {
  try {
    final out = await Process.run('getprop', ['ro.product.model']);
    final m = (out.stdout as String).trim();
    if (m.isNotEmpty) return m;
  } catch (_) {}
  return Platform.localHostname;
}