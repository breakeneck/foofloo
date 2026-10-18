import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'diagnostics.dart';
import 'library_db.dart';
import 'settings_screen.dart';

/// Desktop-like layout: folder tree in a slide-in drawer, main list shows ALL
/// tracks under the selected dir recursively, grouped by folder (like FooQt's
/// dir header rows). Header shows the selected folder.
class LibraryScreen extends StatefulWidget {
  final FooFloApiClient client;
  final VoidCallback onLogout;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final bool compact;
  const LibraryScreen(
      {super.key,
      required this.client,
      required this.onLogout,
      required this.themeMode,
      required this.onThemeChanged,
      this.compact = false});

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
  bool _searchVisible = false;
  bool _compact = false;
  String _query = '';
  final _searchCtrl = TextEditingController();
  int _treeRev = 0; // bump to refresh the drawer tree after a rescan

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _player.dispose();
    _searchCtrl.dispose();
    widget.client.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    Diag.instance.log('library boot: opening db');
    await _db.open();
    final prefs = await SharedPreferences.getInstance();
    final savedRoot = prefs.getString('root');
    if (savedRoot != null && savedRoot.isNotEmpty) _root = savedRoot;
    _compact = prefs.getBool('compact') ?? false;
    _dir = _root;
    Diag.instance.log('db opened, rescanning');
    await _rescan();
    await _navigate(_dir);
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
      if (mounted) {
        setState(() {
          _scanning = false;
          _treeRev++;
        });
      }
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
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.pop(context);
    }
  }

  Future<void> _play(Map track) async {
    final uri = widget.client.fileUri(track['path'] as String);
    final title = track['title'] ?? track['path'].toString().split('/').last;
    Diag.instance.log('play: ${track['path']}');
    try {
      await _player.setAudioSource(AudioSource.uri(
        uri,
        headers: widget.client.audioHeaders,
        tag: MediaItem(
          id: track['path'] as String,
          title: title.toString(),
          artist: (track['artist'] ?? '').toString(),
          album: (track['album'] ?? '').toString(),
        ),
      ));
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

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => SettingsScreen(
          client: widget.client,
          root: _root,
          scanState: _scanState,
          themeMode: widget.themeMode,
          onThemeChanged: widget.onThemeChanged,
          compact: _compact,
          onCompactChanged: (v) {
            setState(() => _compact = v);
            SharedPreferences.getInstance()
                .then((p) => p.setBool('compact', v));
          },
          onRescan: () {
            Navigator.pop(context);
            _rescan();
          },
          onRootChanged: (r) {
            Navigator.pop(context);
            _root = r;
            _dir = r;
            _rescan();
          },
          onLogout: widget.onLogout,
        ),
      ),
    );
  }

  void _toggleSearch() {
    setState(() => _searchVisible = !_searchVisible);
    if (!_searchVisible) {
      _searchCtrl.clear();
      _query = '';
      _navigate(_dir);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _FolderTree(
        db: _db,
        root: _root,
        selected: _dir,
        rev: _treeRev,
        onSelect: _navigate,
      ),
      appBar: AppBar(
        title: Text(_dir == _root ? _root.split('/').last : _shortDir('$_dir/x'),
            overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
              icon: Icon(_searchVisible ? Icons.search_off : Icons.search),
              onPressed: _toggleSearch),
          IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: _openSettings),
        ],
      ),
      body: Column(
        children: [
          if (_searchVisible)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (v) {
                  _query = v.trim();
                  _navigate(_dir);
                },
                decoration: const InputDecoration(
                    hintText: 'Пошук у папці…', isDense: true),
              ),
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
                int t = i;
                for (final h in headers) {
                  if (t == h) {
                    return _dirHeader(
                        _shortDir(_tracks[t]['path'] as String));
                  }
                  if (t > h) t--;
                }
                final track = _tracks[t];
                final title = track['title'] ??
                    track['path'].toString().split('/').last;
                final meta = [track['artist'], track['album']]
                    .where((x) => x != null)
                    .join(' · ');
                return ListTile(
                  dense: true,
                  visualDensity: _compact
                      ? VisualDensity.compact
                      : null,
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: _compact ? 8 : 16),
                  minLeadingWidth: _compact ? 12 : 24,
                  leading: Icon(Icons.music_note_outlined,
                      size: _compact ? 16 : 20),
                  title: Text(
                    _compact && meta.isNotEmpty
                        ? '$title — $meta'
                        : '$title',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: _compact ? 13 : null),
                  ),
                  subtitle: _compact
                      ? null
                      : Text(meta, maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                  trailing: Text(_fmtDur(track['dur']),
                      style: TextStyle(
                          fontSize: _compact ? 12 : null)),
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
        padding: EdgeInsets.fromLTRB(16, _compact ? 6 : 10, 16, 2),
        child: Text(dir,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: _compact ? 12 : null)),
      );

  String _fmtDur(dynamic d) {
    if (d == null) return '';
    final s = (d as num).toInt();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

/// Slide-in folder tree: tap folder name = select it (main list shows all
/// tracks under it); tap the arrow = expand/collapse subtree. Folders without
/// tracks in their subtree are hidden, like the desktop client.
class _FolderTree extends StatefulWidget {
  final LibraryDb db;
  final String root;
  final String selected;
  final int rev;
  final ValueChanged<String> onSelect;
  const _FolderTree(
      {required this.db,
      required this.root,
      required this.selected,
      required this.rev,
      required this.onSelect});

  @override
  State<_FolderTree> createState() => _FolderTreeState();
}

class _FolderTreeState extends State<_FolderTree> {
  late Future<List<String>> _rootsFuture = _loadVisible(widget.root);

  @override
  void didUpdateWidget(covariant _FolderTree old) {
    super.didUpdateWidget(old);
    if (widget.rev != old.rev) {
      _rootsFuture = _loadVisible(widget.root);
    }
  }

  Future<List<String>> _loadVisible(String dir) async {
    final subs = await widget.db.subDirs(dir);
    final vis = <String>[];
    for (final d in subs) {
      if (await widget.db.countUnder(d) > 0) vis.add(d);
    }
    return vis;
  }

  Widget _node(String path) => _TreeNode(
        key: PageStorageKey(path),
        db: widget.db,
        path: path,
        selected: widget.selected,
        onSelect: widget.onSelect,
        loadVisible: _loadVisible,
      );

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
              selectedTileColor: Colors.white12,
              onTap: () => widget.onSelect(widget.root),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<String>>(
                future: _rootsFuture,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(
                        child: CircularProgressIndicator());
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

class _TreeNode extends StatefulWidget {
  final LibraryDb db;
  final String path;
  final String selected;
  final ValueChanged<String> onSelect;
  final Future<List<String>> Function(String) loadVisible;
  const _TreeNode(
      {super.key,
      required this.db,
      required this.path,
      required this.selected,
      required this.onSelect,
      required this.loadVisible});

  @override
  State<_TreeNode> createState() => _TreeNodeState();
}

class _TreeNodeState extends State<_TreeNode> {
  bool _expanded = false;
  List<String>? _kids;

  Future<void> _toggle() async {
    if (!_expanded && _kids == null) {
      _kids = await widget.loadVisible(widget.path);
    }
    if (!mounted) return;
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.path.split('/').last;
    return Column(
      children: [
        ListTile(
          dense: true,
          leading: const Icon(Icons.folder_outlined, size: 20),
          title: Text(name, overflow: TextOverflow.ellipsis),
          selected: widget.selected == widget.path,
          selectedTileColor: Colors.white12,
          onTap: () => widget.onSelect(widget.path),
          trailing: IconButton(
            icon: Icon(_expanded
                ? Icons.expand_less
                : Icons.expand_more, size: 22),
            onPressed: _toggle,
          ),
        ),
        if (_expanded && _kids != null)
          for (final k in _kids!)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: _TreeNode(
                key: PageStorageKey(k),
                db: widget.db,
                path: k,
                selected: widget.selected,
                onSelect: widget.onSelect,
                loadVisible: widget.loadVisible,
              ),
            ),
      ],
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
            IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: player.seekToNext),
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