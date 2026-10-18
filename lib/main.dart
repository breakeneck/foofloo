import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'src/api_client.dart';
import 'src/diagnostics.dart';
import 'src/library_screen.dart';
import 'src/pairing_screen.dart';

void main() {
  Diag.runGuarded(() {
    Diag.instance.log('main() started');
    runApp(const FooFloApp());
  });
}

class FooFloApp extends StatefulWidget {
  const FooFloApp({super.key});

  @override
  State<FooFloApp> createState() => _FooFloAppState();
}

class _FooFloAppState extends State<FooFloApp> {
  static const _store = FlutterSecureStorage();
  Future<FooFloApiClient?> _session = Future.value(null);
  bool _ready = false;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    Diag.instance.log('app init');
    Diag.instance.deviceNameFuture();
    _session = _restore();
    // if nothing became ready in 8s, ship whatever we have to the collector
    _watchdog = Timer(const Duration(seconds: 8), () {
      if (!_ready) Diag.instance.flush(reason: 'startup stalled 8s');
    });
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  Future<FooFloApiClient?> _restore() async {
    Diag.instance.log('secure storage: reading host');
    String? host, token;
    try {
      host = await _store.read(key: 'host').timeout(const Duration(seconds: 5));
      Diag.instance.log('host=${host ?? 'null'}');
      token =
          await _store.read(key: 'client_token').timeout(const Duration(seconds: 5));
      Diag.instance.log('token=${token != null ? 'present' : 'null'}');
    } catch (e) {
      Diag.instance.log('secure storage FAILED: $e');
      host = null;
      token = null;
    }
    if (host == null || token == null) return null;
    return FooFloApiClient(Uri.parse(host), token);
  }

  Future<void> _save(FooFloApiClient c) async {
    Diag.instance.log('paired with ${c.base}');
    try {
      await _store.write(key: 'host', value: c.base.toString());
      await _store.write(key: 'client_token', value: c.clientToken);
    } catch (e) {
      Diag.instance.log('storage write failed: $e');
    }
    setState(() {
      _ready = true;
      _session = Future.value(c);
    });
    Diag.instance.flush(reason: 'paired');
  }

  Future<void> _logout() async {
    Diag.instance.log('logout');
    try {
      await _store.delete(key: 'client_token');
    } catch (_) {}
    setState(() {
      _ready = true;
      _session = Future.value(null);
    });
  }

  @override
  Widget build(BuildContext context) {
    Diag.instance.log('build()');
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
          if (snap.connectionState != ConnectionState.done) {
            Diag.instance.log('builder: waiting (${snap.connectionState})');
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          // snap.data == null means "no saved session" — hasData is false
          // for null, so never gate on hasData here.
          _ready = true;
          final client = snap.data;
          if (client == null) {
            Diag.instance.log('builder: pairing screen');
            return PairingScreen(onPaired: _save);
          }
          Diag.instance.log('builder: library screen');
          Diag.instance.flush(reason: 'library reached');
          return LibraryScreen(client: client, onLogout: _logout);
        },
      ),
    );
  }
}

extension on Diag {
  void deviceNameFuture() {
    deviceName().then((name) {
      device = name;
      log('device=$name');
    });
  }
}