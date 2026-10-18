import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'api_client.dart';
import 'diagnostics.dart';
import 'library_db.dart';

/// Drill-down browser: tap folders to descend (list updates immediately,
/// like the desktop), tap a track to play. Bottom bar = now playing.
class LibraryScreen extends StatefulWidget {
  final FooFloApiClient client;
  final VoidCallback onLogout;
  const LibraryScreen(
      {super.key, required this.client, required this.onLogout});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _db = LibraryDb();
  final _player = AudioPlayer();
  String _root = '/home/server/hdd/media/Music';
  String _dir = '/home/server/hdd/media/Music';
  List<Map> _tracks = [];
  List<String> _dirs = [];
  String _scanState = 'idle';
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _player.dispose();
    widget.client.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    Diag.instance.log('library boot: opening db');
    await _db.open();
    Diag.instance.log('db opened, rescanning');
    await _rescan();
    await _navigate(_root);
  }

  Future<void> _rescan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _scanState = 'scanning…';
    });
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    try {
      final known = await _db.knownFingerprints();
      Diag.instance.log('scan $id root=$_root known=${known.length}');
      await widget.client.scan(id, _root, known);
      int cursor = 0;
      while (mounted) {
        final p = await widget.client.progress(id, cursor);
        final entries = (p['entries'] as List?) ?? [];
        if (entries.isNotEmpty) await _db.ingest(entries);
        cursor = p['cursor'] as int;
        final state = p['state'] as String? ?? 'running';
        final counts = p['counts'] ?? {};
        setState(() => _scanState =
            '$state · ${counts['dirs'] ?? 0} dirs · ${counts['tracks'] ?? 0} tracks');
        if (state == 'done' || state == 'error') break;
        await Future.delayed(const Duration(milliseconds: 700));
      }
      await widget.client.forget(id);
      await _db.purgeMissing([_root]);
      await _navigate(_dir);
    } catch (e) {
      if (mounted) setState(() => _scanState = 'scan failed: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _navigate(String dir) async {
    final tracks = await _db.tracksIn(dir);
    final dirs = await _db.subDirs(dir);
    if (!mounted) return;
    setState(() {
      _dir = dir;
      _tracks = tracks;
      _dirs = dirs;
    });
  }

  Future<void> _play(Map track) async {
    final uri = widget.client.fileUri(track['path'] as String);
    await _player.setAudioSource(
        AudioSource.uri(uri, headers: widget.client.audioHeaders));
    await _player.play();
  }

  String _label(String path) {
    final name = path.split('/').last;
    return name.length > 40 ? '${name.substring(0, 37)}…' : name;
  }

  void _changeRoot() {
    final ctrl = TextEditingController(text: _root);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Music root on server'),
        content: TextField(controller: ctrl, autocorrect: false),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _root = ctrl.text.trim();
              _dir = _root;
              _rescan();
            },
            child: const Text('Rescan'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_dir == _root ? 'Library' : _label(_dir)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _rescan),
          IconButton(icon: const Icon(Icons.settings), onPressed: _changeRoot),
          IconButton(icon: const Icon(Icons.link_off), onPressed: widget.onLogout),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(_scanState, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: ListView(
              children: [
                if (_dir != _root && _dir.contains('/'))
                  ListTile(
                      leading: const Icon(Icons.arrow_upward),
                      title: const Text('..'),
                      onTap: () =>
                          _navigate(_dir.substring(0, _dir.lastIndexOf('/')))),
                for (final d in _dirs)
                  ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(_label(d)),
                      onTap: () => _navigate(d)),
                for (final t in _tracks)
                  ListTile(
                      leading: const Icon(Icons.music_note_outlined),
                      title: Text(t['title'] ?? _label(t['path'] as String)),
                      subtitle: Text(
                          [t['artist'], t['album']].where((x) => x != null).join(' · ')),
                      onTap: () => _play(t)),
              ],
            ),
          ),
          _NowPlayingBar(player: _player),
        ],
      ),
    );
  }
}

class _NowPlayingBar extends StatelessWidget {
  final AudioPlayer player;
  const _NowPlayingBar({required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, snap) {
        final state = snap.data;
        if (state == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            IconButton(
              icon: Icon(state.playing ? Icons.pause : Icons.play_arrow),
              onPressed: () => state.playing ? player.pause() : player.play(),
            ),
            IconButton(icon: const Icon(Icons.skip_next), onPressed: player.seekToNext),
            Expanded(
              child: StreamBuilder<Duration>(
                stream: player.positionStream,
                builder: (ctx, pos) {
                  final dur = player.duration;
                  return LinearProgressIndicator(
                    value: dur != null && dur.inMilliseconds > 0
                        ? pos.data!.inMilliseconds / dur.inMilliseconds
                        : null,
                  );
                },
              ),
            ),
            IconButton(icon: const Icon(Icons.stop), onPressed: player.stop),
          ]),
        );
      },
    );
  }
}