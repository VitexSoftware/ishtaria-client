# ishtaria-client

The Godot 4.5 game client: rendering, input, windows, local preferences. Licence: MIT. Part of the Ishtaria workspace of several repositories side by side
(`ishtaria-server`, `ishtaria-client`, `ishtaria-worldgen`, `ishtaria-core`, `ishtaria-content`, `ishtaria-protocol`,
`ishtaria-docs`): run Git, Cargo and `make` inside the repository you change. Work on `main`; do not commit,
push or deploy unless asked. Debian/Ubuntu x86-64 is the only supported platform.

Developer guide: https://github.com/VitexSoftware/ishtaria-docs/tree/main/source/development (`contributing`, `local-setup`, `invariants`, `cookbook`, the code tours).

## Checks before you say you are done

```sh
godot4 --headless --path . --editor --import   # after adding assets
make test-social test-trading test-placed test-magic   # and the other make test-* targets
make run                                               # play it; look at what you changed
```

## Where things are

* `scripts/main.gd` builds everything and handles input; `scripts/*_client.gd` are thin HTTP layers.
* `tests/*.gd` headless scripts with `make test-*` targets; `locales/client.csv` English + Czech.
* Client code map: `docs: client-tour`; adding a window or a key: `docs: cookbook`.

## Working notes

* The client never decides: it sends intentions and validates every answer (`valid_*`), maps refusals to fixed
  message keys, and guards requests with a generation counter.
* Headless tests do not prove that something looks right: run the client, look, and say what you saw.
* New assets: original licence under `assets/`, README credits and `debian/copyright`.

## Rules that never change (full text: docs `development/invariants`)

* The server decides; clients send intentions. Never trust a client value; validate every request and every answer.
* Related writes in one transaction; economy changes are atomic, bounded and repeat-safe.
* Migrations are append-only. Terrain is generated; only changes are stored. Never touch a live database in tests.
* A new character gets 100 gold exactly once. Death is permanent. Money buys space and appearance, not power.
* Language is a client preference: the server may receive it per request but never stores it.
* Content is data, not code. Federation is bilateral and signed.
* Never log or commit secrets. Argon2id passwords, hashed expiring tokens.
* Approved assets (Kenney, Quaternius, generated with the origin recorded); keep licence notices.
* Report honestly: what is implemented and tested, what is planned, what is blocked. Do not weaken a failing check.
