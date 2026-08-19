# Omarchy BBS

A small, dependency-free message board whose normal entrance is an enrolled
Omarchy machine. It includes an Omarchy 4 bar widget, a device client, and a
SQLite-backed web server.

## Requirements and boundaries

- Omarchy Quattro (4.x) with its Quickshell-based plugin runtime
- Python 3, including the standard-library `sqlite3` module
- A graphical browser registered with the desktop
- A separately operated BBS server reachable from each client

The plugin never installs packages, requests elevated privileges, or starts a
background service. Its bar button only runs the bundled client. The operator
starts and secures `server.py` separately; the server writes only to
`OMARCHY_BBS_DB` (or `bbs.db` in the repository by default). The client writes
its device credential under `$XDG_STATE_HOME/omarchy-bbs` and reads an optional
server URL from `$XDG_CONFIG_HOME/omarchy-bbs/config.json`.

## Security model

The server accepts only enrolled devices. Enrollment requires an invite code,
and the client refuses to enroll or log in unless `/usr/share/omarchy` exists
and `omarchy version` succeeds. Each click creates a signed, single-use login
URL that expires after 60 seconds; the browser receives an HttpOnly session
cookie.

Omarchy is open source, so no software-only OS check can be unforgeable. An
attacker with a valid invite can imitate the client. The invite is therefore
the real community boundary; the local Omarchy check makes the intended path
pleasant and prevents accidental non-Omarchy access. For a public production
service, put the server behind HTTPS and add rate limiting, backups, moderation,
and durable shared session/nonce storage.

## Run a local board

```bash
python3 server.py invite
python3 server.py serve
```

Copy the printed invite, then enroll from an Omarchy machine:

```bash
python3 client.py enroll your_handle PASTE_INVITE_HERE
python3 client.py open
```

The default URL is `http://127.0.0.1:8787`. For a hosted board, create
`~/.config/omarchy-bbs/config.json`:

```json
{"server_url": "https://bbs.example.com"}
```

You may also set `OMARCHY_BBS_URL`.

## Install the bar plugin

Publish this directory as a Git repository, then install it with:

```bash
omarchy plugin add https://github.com/thoughtlesslabs/omarchy-bbs.git --enable
```

For local development, validate it and add it from the local Git checkout.
The `BBS` bar button runs `client.py open`.

Move the widget if desired:

```bash
omarchy bar move io.github.thoughtlesslabs.omarchy-bbs --section right
```

## Remove

```bash
omarchy plugin remove io.github.thoughtlesslabs.omarchy-bbs
```

Removing the plugin does not delete the device credential stored at
`~/.local/state/omarchy-bbs/device.json`. Delete that file separately if you
also want to revoke the local login material, and revoke the device in the
server database before reusing its handle.

## Server operations

`OMARCHY_BBS_DB` changes the SQLite database path. Bind to a public interface
with `python3 server.py serve --host 0.0.0.0`, but never expose the built-in
HTTP server directly to the internet; terminate HTTPS and apply request limits
in a production reverse proxy.
