# Omarchy BBS

A native community message board whose normal entrance is an Omarchy machine.
It includes an Omarchy 4 bar widget, a signed device client, and a PHP/MySQL
service. Reading, writing, and joining all happen in the themed shell panel—no
browser tab is opened.

## Requirements and boundaries

- Omarchy Quattro (4.x) with its Quickshell-based plugin runtime
- Python 3 on the Omarchy client
- The hosted BBS at `https://bbs.thoughtlesslabs.com`

The plugin never installs packages, requests elevated privileges, or starts a
background service. On first open, it verifies Omarchy locally and suggests the
machine hostname as an editable public call sign. Registration happens only
after the user confirms that name. The generated device credential is stored
with mode `0600` under `$XDG_STATE_HOME/omarchy-bbs`. After joining, the widget
checks for new activity every five minutes. Notifications never include message
content; clicking one opens the native panel.

## Security model

The server accepts registered devices, and the client refuses to register or
make signed requests unless `/usr/share/omarchy` exists and `omarchy version`
succeeds. Every API request is authenticated with a short-lived, single-use
HMAC proof; write signatures are bound to the exact message contents.

Omarchy is open source, so no software-only OS check can be unforgeable. An
attacker can imitate the client. This is a practical community boundary, not
hardware attestation. The production PHP app encrypts message titles, bodies,
and device secrets at rest using authenticated libsodium encryption with a key
stored outside both the database and document root. It also adds registration
throttling, CSRF protection, strict browser security headers, HTTPS-only
headers, rate limits, strict size limits, and durable one-time nonces. Handles
are public and default to the hostname only after the user sees and confirms it.

Click the installed terminal-signal bar icon. Pick or confirm the suggested
call sign, then select **Join frequency**. No terminal commands are required.
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
The widget talks to `client.py` directly and passes message bodies over stdin so
they do not appear in process arguments.

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
