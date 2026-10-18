# FooFlo

Android client for the fooqt remote music setup: the music library lives on
a server, `server/remote_agent.py` scans it locally and streams audio over
HTTP; FooFlo is a thin client — pairing, library mirror (sqflite), drill-down
browser, playback via `just_audio` (Range requests handled by the agent).

## Architecture

```
Android (Flutter)                    music server (ha)
┌────────────────┐   HTTP token   ┌──────────────────────┐
│ pairing screen │ ─────────────► │ remote_agent.py      │
│ sqflite mirror │ ◄─ /scan       │  readdir + tag parse │
│ just_audio     │ ◄─ /progress   │  /file (Range)       │
└────────────────┘ ◄─ /file        └──────────────────────┘
        ▲ probe/register
        │
   desktop FooQt (master token, /pair button)
```

- `server/remote_agent.py` — fork of foobar-qt's agent, v1.4.0. Adds pairing:
  `POST /pair` (master token) → one-time 6-digit code (60 s, 5 attempts);
  `POST /register` (no token) → per-device client token stored in
  `devices.json` (0600). `--pair` CLI flag mints a code via `.pair` state
  file for the running agent. Refuses to start without a master token.
- `lib/src/api_client.dart` — protocol client
- `lib/src/library_db.dart` — local mirror: tracks/dirs + known-fingerprint
  map for incremental rescans, purge of removed roots
- `lib/src/pairing_screen.dart` / `library_screen.dart` — UI

## Pairing flow

1. Desktop FooQt menu → "Pair device" (or on the server:
   `python3 ~/.local/lib/fooqt/remote_agent.py --pair`) → 6-digit code.
2. FooFlo: enter agent URL + code → client token saved in Keystore.
3. Revoke: `GET /devices` + `POST /revoke {"token": ...}` with master token,
   or edit `devices.json`.

## Access paths

- LAN: run the agent with `--bind 0.0.0.0` inside the 192.168.88.x subnet.
- Remote: WireGuard to the LAN, or SSH tunnel (`ssh -L 45601:127.0.0.1:45601 ha`).
- Never expose the port to WAN.

## Build

```bash
JAVA_HOME=~/dev/android-tools/jdk17 ANDROID_HOME=~/dev/android-tools/android-sdk \
  flutter build apk --debug
```

## Roadmap

- playlist queue + "stop after current"
- lyrics / lastfm scrobbling (via the thin bridge or direct APIs)
- hotkeys for tablets with keyboards (RawKeyboard)
- desktop FooQt: "Pair device" dialog calling POST /pair