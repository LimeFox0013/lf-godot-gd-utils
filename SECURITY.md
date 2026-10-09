# Security policy

## Reporting a vulnerability

Report it privately through GitHub's security advisories: on the repository page, open
the **Security** tab and choose **Report a vulnerability**
([direct link](https://github.com/LimeFox0013/lf-godot-gd-utils/security/advisories/new)).
Please do not open a public issue or pull request for it.

Include the lf-godot-gd-utils version, your Godot version, the module, and a few lines of GDScript (or a
request, or an archive) that reproduce the problem. The maintainers intend to reply,
but no response time is promised: lf-godot-gd-utils is maintained by a small team.

A confirmed vulnerability is meant to be fixed in a patch release and described in
[`CHANGELOG.md`](CHANGELOG.md) under *Security*; the advisory credits the reporter unless
they ask not to be named.

## Supported versions

Only the newest release of the newest major version receives security fixes. There are
no backports to older releases. See [`STABILITY.md`](STABILITY.md) for how versions are
numbered.

## What is in scope

Flaws in the code of a module that make it do something its README says it does not,
especially in the modules that handle input from outside the game:

- `lf_http`, `lf_url`: requests, redirects, size limits, header handling.
- `lf_socket`, `lf_socket_server`: WebSocket client and server, handshake and
  connection limits, message parsing.
- `lf_accounts`, `lf_strike_guard`: password hashing, session tokens, sign-in lockouts.
- `lf_llm`: handling of API keys and of provider responses.
- `lf_replication`: applying snapshots and deltas received from a peer.
- `lf_zip`, `lf_file`: path containment when extracting archives or joining
  user-supplied names; deleting files.
- `lf_os`, `lf_process`: starting programs from arguments.
- `lf_uuid`: the randomness of ids and tokens.

## What is not promised

- lf-godot-gd-utils has not had an independent security audit.
- The networking and account modules are meant for a small game server you run yourself.
  Their pages state the limits the maintainers know of (for example scale, platforms, and
  for `lf_accounts` the strength of its password hash against what current guidance
  recommends); not every page covers all of these. They are not a substitute for a
  hardened authentication service, a web application firewall, or TLS configured by you.
- Keeping `LFSocketServer` or any other server safe on the public internet (firewall,
  certificates, rate limits in front of it, keeping secrets out of the repository) is
  your responsibility.
- Bugs in Godot itself, in GUT, or in your game are out of scope; report those to their
  own projects.
- Modules marked *experimental* in [`STABILITY.md`](STABILITY.md) can change their API in
  a minor release, including to fix a security problem.
- A report about a limit the README already documents, with no way to exceed it, is a
  feature request rather than a vulnerability, and is welcome as an issue.
