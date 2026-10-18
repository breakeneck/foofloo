import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';

/// First-run screen: point at the agent, enter the one-time pairing code
/// shown by the desktop client (or printed by `remote_agent.py --pair`),
/// exchange it for a client token.
class PairingScreen extends StatefulWidget {
  final void Function(FooFloApiClient client) onPaired;
  const PairingScreen({super.key, required this.onPaired});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _host = TextEditingController(text: 'http://192.168.88.29:45601');
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _agentOk = false;

  Uri get _base => Uri.parse(_host.text.trim());

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _error = null;
      _agentOk = false;
    });
    try {
      final info = await FooFloApiClient.ping(_base);
      setState(() {
        _agentOk = info['ok'] == true;
        _error = _agentOk ? null : 'agent refused ping';
      });
    } catch (e) {
      setState(() => _error = 'cannot reach agent: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _pair() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'code must be 6 digits');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await FooFloApiClient.register(
          _base, code, 'android-${DateTime.now().millisecondsSinceEpoch % 10000}');
      widget.onPaired(FooFloApiClient(_base, token));
    } on AgentError catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.music_note, size: 64),
                const SizedBox(height: 8),
                const Text('FooFlo',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28)),
                const SizedBox(height: 24),
                TextField(
                  controller: _host,
                  decoration: const InputDecoration(
                      labelText: 'Music server', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                        onPressed: _busy ? null : _check,
                        child: const Text('Check agent')),
                  ),
                  if (_agentOk)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.check_circle, color: Colors.green),
                    ),
                ]),
                const SizedBox(height: 16),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                      labelText: 'Pairing code (6 digits)',
                      hintText: 'from desktop menu or `--pair`',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                FilledButton(
                    onPressed: _busy ? null : _pair,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Pair')),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}