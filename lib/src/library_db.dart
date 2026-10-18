import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import 'api_client.dart';

/// Local mirror of the server-side library, same role as apsw in the desktop
/// client: tracks table + known-fingerprint map for incremental rescans.
class LibraryDb {
  late final Database _db;

  Future<void> open() async {
    _db = await openDatabase(
      join(await getDatabasesPath(), 'foofloo.db'),
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE tracks(
            path TEXT PRIMARY KEY,
            artist TEXT, title TEXT, album TEXT,
            dur REAL, mt REAL, sz INTEGER)''');
        await db.execute('CREATE TABLE dirs(path TEXT PRIMARY KEY)');
      },
    );
  }

  Future<Map<String, List>> knownFingerprints() async {
    final rows = await _db.query('tracks', columns: ['path', 'mt', 'sz']);
    return {
      for (final r in rows) r['path'] as String: [r['mt'], r['sz']]
    };
  }

  /// Ingest one /progress chunk; returns counts for UI feedback.
  Future<void> ingest(List entries) async {
    final batch = _db.batch();
    for (final e in entries) {
      if (e['t'] == 'd') {
        batch.insert('dirs', {'path': e['p']},
            conflictAlgorithm: ConflictAlgorithm.replace);
      } else if (e['u'] != 1) {
        final t = Track.fromJson(e);
        batch.insert('tracks', {
          'path': t.path, 'artist': t.artist, 'title': t.title,
          'album': t.album, 'dur': t.duration, 'mt': t.mtime, 'sz': t.size,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      } else {
        // unchanged: refresh fingerprint only if the server sent one
        batch.update('tracks', {'mt': e['mt'], 'sz': e['sz']},
            where: 'path = ?', whereArgs: [e['p']]);
      }
    }
    await batch.commit(noResult: true);
  }

  /// Purge tracks under roots that were removed from the config, mirroring
  /// the desktop client's "purge removed libraries" behaviour.
  Future<void> purgeMissing(List<String> activeRoots) async {
    final all = await _db.query('tracks', columns: ['path']);
    final gone = (all.map((r) => r['path'] as String))
        .where((p) => !activeRoots.any((root) => p.startsWith('$root/')))
        .toList();
    if (gone.isEmpty) return;
    final batch = _db.batch();
    for (final p in gone) {
      batch.delete('tracks', where: 'path = ?', whereArgs: [p]);
      batch.delete('dirs', where: 'path = ?', whereArgs: [p]);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map>> tracksIn(String dir) async {
    final like = '${dir.replaceAll('%', r'\%')}%';
    return _db.query('tracks',
        where: 'path LIKE ? AND path NOT LIKE ?',
        whereArgs: [like, '$like/%/%'],
        orderBy: 'title COLLATE NOCASE');
  }

  Future<List<String>> subDirs(String dir) async {
    final rows = await _db.query('dirs', columns: ['path']);
    final prefix = dir == '/' ? '/' : '$dir/';
    final out = <String>{};
    for (final r in rows) {
      final p = r['path'] as String;
      if (!p.startsWith(prefix)) continue;
      final rest = p.substring(prefix.length);
      if (rest.isEmpty) continue;
      out.add(prefix + rest.split('/').first);
    }
    final l = out.toList()..sort();
    return l;
  }

  Future<int> trackCount() async {
    final r = await _db.rawQuery('SELECT COUNT(*) c FROM tracks');
    return r.first['c'] as int;
  }
}