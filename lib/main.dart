import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'src/api_client.dart';
import 'src/library_screen.dart';
import 'src/pairing_screen.dart';

void main() => runApp(const FooFloApp());

class FooFloApp extends StatefulWidget {
  const FooFloApp({super.key});

  @override
  State<FooFloApp> createState() => _FooFloAppState();
}

class _FooFloAppState extends State<FooFloApp> {
  static const _store = FlutterSecureStorage();
  Future<FooFloApiClient?> _session = Future.value(null);

  @override
  void initState() {
    super.initState();
    _session = _restore();
  }

  Future<FooFloApiClient?> _restore() async {
    String? host, token;
    try {
      host = await _store.read(key: 'host');
      token = await _store.read(key: 'client_token');
    } catch (e) {
      // flutter_secure_storage can throw on some devices; a failed read
      // must not hang the splash forever.
      debugPrint('secure storage read failed: $e');
      host = null;
      token = null;
    }
    if (host == null || token == null) return null;
    return FooFloApiClient(Uri.parse(host), token);
  }

  Future<void> _save(FooFloApiClient c) async {
    try {
      await _store.write(key: 'host', value: c.base.toString());
      await _store.write(key: 'client_token', value: c.clientToken);
    } catch (e) {
      debugPrint('secure storage write failed: $e');
    }
    setState(() => _session = Future.value(c));
  }

  Future<void> _logout() async {
    try {
      await _store.delete(key: 'client_token');
    } catch (_) {}
    setState(() => _session = Future.value(null));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FooFlo',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF7C4DFF),
        useMaterial3: true,
      ),
      home: FutureBuilder<FooFloApiClient?>(
        future: _session,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          final client = snap.data;
          if (client == null) {
            return PairingScreen(onPaired: _save);
          }
          return LibraryScreen(client: client, onLogout: _logout);
        },
      ),
    );
  }
}