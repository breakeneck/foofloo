import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'api_client.dart';
import 'diagnostics.dart';
import 'library_db.dart';

/// Desktop-like layout: left folder tree (hidden behind a slide-in drawer),
/// main list shows ALL tracks under the selected dir recursively, grouped by
/// last folder — same as FooQt's playlist with dir header rows.
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
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String _root = '/home/server/hdd/media/Music';
  String _dir = '/home/server/hdd/media/Music';
  List<Map> _tracks = [];
  String _scanState = 'idle';
  bool _scanning = false;
  String _query = '';

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
      Diag.instance.log('scan failed: $e');
      if (mounted) setState(() => _scanState = 'scan failed: $e');
      Diag.instance.flush(reason: 'scan error');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _navigate(String dir) async {
    var tracks = await _db.tracksUnder(dir);
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      tracks = tracks
          .where((t) =>
              (t['title'] ?? '').toString().toLowerCase().contains(q) ||
              (t['artist'] ?? '').toString().toLowerCase().contains(q))
          .toList();
    }
    if (!mounted) return;
    setState(() {
      _dir = dir;
      _tracks = tracks;
    });
    // close the drawer after picking a folder
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.pop(context);
    }
  }

  Future<void> _play(Map track) async {
    final uri = widget.client.fileUri(track['path'] as String);
    Diag.instance.log('play: ${track['path']}');
    try {
      await _player.setAudioSource(
          AudioSource.uri(uri, headers: widget.client.audioHeaders));
      await _player.play();
      Diag.instance.log('play: started ok');
    } catch (e) {
      Diag.instance.log('play FAILED: $e');
      Diag.instance.flush(reason: 'play error');
    }
  }

  /// Group label relative to root, like desktop get_short_dir_name.
  String _shortDir(String path) {
    final idx = path.lastIndexOf('/');
    final dir = idx <= 0 ? '/' : path.substring(0, idx);
    if (dir == _root) return _root.split('/').last;
    if (dir.startsWith('$_root/')) return dir.substring(_root.length + 1);
    return dir.split('/').last;
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
      key: _scaffoldKey,
      drawer: _FolderTree(
        db: _db,
        root: _root,
        selected: _dir,
        onSelect: _navigate,
      ),
      appBar: AppBar(
        title: Text(_dir == _root ? 'Library' : _shortDir('$_dir/x')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _rescan),
          IconButton(icon: const Icon(Icons.settings), onPressed: _changeRoot),
          IconButton(
            icon: const Icon(Icons.link_off),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Від\'єднати пристрій?'),
                  content: Text('Токен збережено у Keystore, сервер ${widget.client.base}.\n'
                      'Щоб знову слухати, знадобиться новий pairing-код.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Скасувати')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Від\'єднати')),
                  ],
                ),
              );
              if (ok == true) widget.onLogout();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              Expanded(
                child: TextField(
                  onChanged: (v) {
                    _query = v.trim();
                    _navigate(_dir);
                  },
                  decoration: const InputDecoration(
                      hintText: 'Пошук…', isDense: true),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(_scanState,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _tracks.length + _headerCount(),
              itemBuilder: (context, i) {
                final headers = _headerIndices();
                // shift index past header rows
                int t = i;
                for (final h in headers) {
                  if (t == h) return _dirHeader(_shortDir(_tracks[t]['path'] as String));
                  if (t > h) t--;
                }
                final track = _tracks[t];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.music_note_outlined, size: 20),
                  title: Text(track['title'] ??
                      track['path'].toString().split('/').last),
                  subtitle: Text([track['artist'], track['album']]
                      .where((x) => x != null)
                      .join(' · ')),
                  trailing: Text(_fmtDur(track['dur'])),
                  onTap: () => _play(track),
                );
              },
            ),
          ),
          _NowPlayingBar(player: _player),
        ],
      ),
    );
  }

  /// Indices (in shifted coords) where a new folder group starts.
  List<int> _headerIndices() {
    final out = <int>[];
    String cur = '';
    int pos = 0;
    for (final t in _tracks) {
      final d = _shortDir(t['path'] as String);
      if (d != cur) {
        cur = d;
        out.add(pos);
      }
      pos++;
    }
    return out;
  }

  int _headerCount() => _headerIndices().length;

  Widget _dirHeader(String dir) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
        child: Text(dir,
            style: const TextStyle(fontWeight: FontWeight.bold)),
      );

  String _fmtDur(dynamic d) {
    if (d == null) return '';
    final s = (d as num).toInt();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

/// Slide-in folder tree, desktop-style: full hierarchy under the root,
/// folders with no tracks in their subtree are hidden.
class _FolderTree extends StatefulWidget {
  final LibraryDb db;
  final String root;
  final String selected;
  final ValueChanged<String> onSelect;
  const _FolderTree(
      {required this.db,
      required this.root,
      required this.selected,
      required this.onSelect});

  @override
  State<_FolderTree> createState() => _FolderTreeState();
}

class _FolderTreeState extends State<_FolderTree> {
  late final Future<List<String>> _rootsFuture = _loadRoots();

  Future<List<String>> _loadRoots() async {
    final subs = await widget.db.subDirs(widget.root);
    final visible = <String>[];
    for (final d in subs) {
      if (await widget.db.countUnder(d) > 0) visible.add(d);
    }
    return visible;
  }

  Widget _node(String path) {
    final name = path.split('/').last;
    return FutureBuilder<List<String>>(
      future: widget.db.subDirs(path).then((subs) async {
        final vis = <String>[];
        for (final d in subs) {
          if (await widget.db.countUnder(d) > 0) vis.add(d);
        }
        return vis;
      }),
      builder: (context, snap) {
        final kids = snap.data ?? <String>[];
        return ExpansionTile(
          key: PageStorageKey(path),
          leading: const Icon(Icons.folder_outlined, size: 20),
          title: Text(name, overflow: TextOverflow.ellipsis),
          backgroundColor:
              widget.selected == path ? Colors.white12 : null,
          onExpansionChanged: (_) {},
          children: kids.map(_node).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: Text(widget.root.split('/').last,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              selected: widget.selected == widget.root,
              onTap: () => widget.onSelect(widget.root),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<String>>(
                future: _rootsFuture,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return ListView(
                      children: snap.data!.map(_node).toList());
                },
              ),
            ),
          ],
        ),
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