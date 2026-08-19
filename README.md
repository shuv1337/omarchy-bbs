# Omarchy BBS

A small community message board whose normal entrance is an Omarchy machine.
It includes an Omarchy 4 bar widget, an automatic device client, and a PHP/MySQL
web application.

## Requirements and boundaries

- Omarchy Quattro (4.x) with its Quickshell-based plugin runtime
- Python 3 on the Omarchy client
- A graphical browser registered with the desktop
- The hosted BBS at `https://bbs.thoughtlesslabs.com`

The plugin never installs packages, requests elevated privileges, or starts a
background service. Its bar button only runs the bundled client. On first click
the client verifies Omarchy locally, creates a device credential, registers it,
and opens the board. The credential is stored with mode `0600` under
`$XDG_STATE_HOME/omarchy-bbs`. No invite or setup command is required.

## Security model

The server accepts registered devices, and the client refuses to register or
log in unless `/usr/share/omarchy` exists and `omarchy version` succeeds. Each
click creates a signed, single-use login URL that expires after 90 seconds; the
browser receives a Secure, HttpOnly, SameSite session cookie.

Omarchy is open source, so no software-only OS check can be unforgeable. An
attacker can imitate the client. This is a practical community boundary, not
hardware attestation. The production PHP app encrypts message titles, bodies,
and device secrets at rest using authenticated libsodium encryption with a key
stored outside both the database and document root. It also adds registration
throttling, CSRF protection, strict browser security headers, HTTPS-only
cookies, and durable sessions and one-time nonces. Handles are random
pseudonyms and contain no local account name.

Click the installed `BBS` bar widget. Registration and sign-in are automatic.
For development against another server, create `~/.config/omarchy-bbs/config.json`:

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

The production application is in `web/` and requires PHP 8 with PDO MySQL. Its
configuration is intentionally stored outside the public document root at
`~/.config/omarchy-bbs.php`; credentials must never be committed. The app
creates or updates its own tables on startup. Back up the MySQL database and
review registrations periodically before operating it as a public service.
Back up `~/.config/omarchy-bbs.php` separately and securely: losing its
`app_key` makes encrypted messages unrecoverable, while disclosure of both
that file and the database defeats encryption at rest.
