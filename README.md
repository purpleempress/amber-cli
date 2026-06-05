# amber

A small, warm personal CLI toolkit for the terminal.

`amber` is a git-style dispatcher with a few tools under it, a shared bash
library, and matching shell prompts for **bash** and **fish**. It's pure
**bash + curl + jq**, so there's nothing to compile and no runtime to install.
Drop an executable in `tools/` and it shows up as a subcommand. Releases are
GPG-verified before anything lands on your `PATH`, and everything it touches
(symlinks, rc edits, the motd) can be undone.

What's in the box:

- **`amber`** -- a git-style dispatcher: management verbs (`update`, `doctor`,
  `link`, `config`, …) plus dynamically-discovered tools.
- **`ask`** -- a terminal assistant backed by Gemini, optionally
  Google-grounded; reads stdin as context.
- **`qq`** -- captures your terminal screen and asks Gemini to diagnose what
  went wrong.
- **`dcls`** -- a prettier, cross-project `docker compose ps`.
- **`ipl`** -- resolve a hostname/IP and geolocate every address.
- **`ports`** -- what's listening, by port, with exposed sockets flagged.
- **`wx`** -- terminal weather, by place name or your IP.
- **`prs`** -- your open GitHub PRs and review requests.
- **`define`** -- look up a word (definitions + synonyms).
- **`disk`** -- disk usage by mount, colour-coded by how full.
- **`svc`** -- systemd services at a glance; failures in red.
- **`cert`** -- TLS certificate expiry for a host.
- **`lib`** -- the shared library every tool sources (Gemini client,
  rendering, secret scrubbing, signature verification, config, glyphs).
- **shell prompts** -- a context-aware, per-host-coloured prompt for both bash
  (`prompts/prompt.bash`) and fish (`prompts/prompt.fish`).

> **Linux-first.** The toolkit relies on `readlink -f` (GNU/coreutils) and
> other GNU behaviours. It is developed and tested on Linux.

---

## Install

### Quick one-liner

```bash
curl -fsSL https://raw.githubusercontent.com/purpleempress/amber-cli/main/install | bash
```

### Recommended: download, read, then run

Piping a remote script straight into a shell means trusting it sight unseen.
The safer two-step -- **and the one we recommend** -- is to download
`install`, **read it first** (in particular, check the pinned
`INSTALL_SIGNING_FPR` near the top -- this is the trust anchor for every
release; see [Security model](#security-model--verifying-releases)), and only
then run it:

```bash
curl -fsSLO https://raw.githubusercontent.com/purpleempress/amber-cli/main/install
less install          # read it -- confirm the pinned fingerprint
bash install
```

### Install location & flags

| Mode | Library (`LIB_DIR`) | Symlinks (`BIN_DIR`) |
| --- | --- | --- |
| per-user (default) | `~/.local/share/amber` | `~/.local/bin` |
| `--system` (sudo) | `/usr/local/lib/amber` | `/usr/local/bin` |
| `$AMBERCLI_PREFIX` set | `$AMBERCLI_PREFIX/lib/amber` | `$AMBERCLI_PREFIX/bin` |

```bash
bash install                    # per-user (default)
bash install --system           # system-wide (needs sudo)
AMBERCLI_PREFIX=/tmp/amber bash install   # install into a custom prefix
```

`$AMBERCLI_PREFIX` takes precedence over `--system` and is the primary testing
hook (install into a throwaway dir). By default the installer clones the repo
into `~/.local/share/amber` and symlinks `amber` plus every executable tool
into `~/.local/bin`.

The installer **does not edit your shell config**. If `BIN_DIR` is not already
on your `PATH`, it prints the exact line to add, e.g.:

```bash
export PATH="$HOME/.local/bin:$PATH"        # bash/zsh
fish_add_path ~/.local/bin                  # fish
```

The install is re-runnable: an existing checkout is **fetched (not merged)**,
verified, then fast-forwarded. After it finishes, run `amber doctor` to
confirm everything resolved.

---

## Commands

`amber <verb>` runs a management command; `amber <tool>` runs a tool from
`tools/`; bare `amber` prints help and the discovered tool list.

| Command | What it does |
| --- | --- |
| `amber list` | List management commands and discovered tools. |
| `amber version` | Print the version (`git describe --tags`, else the short commit SHA). |
| `amber doctor` | Health check: paths, `PATH`, deps, signing pin, verified ref, key/config state, glyphs, prompt + motd status. |
| `amber link [--system]` | Symlink `amber` + all tools into `BIN_DIR` (idempotent). |
| `amber unlink [--system]` | Remove only the symlinks in `BIN_DIR` that resolve into `LIB_DIR`. |
| `amber update [--stable\|--edge] [--no-verify]` | Fetch, **verify the signature**, then fast-forward + relink. |
| `amber uninstall` | Unlink, then optionally remove the library (config is preserved). |
| `amber config get <key>` | Print a config value (`geminikey`, `githubtoken`, `model`, `glyphs`). |
| `amber config set <key> [value]` | Set a config value (no-echo prompt when value omitted). |
| `amber config glyphs <unicode\|ascii>` | Switch glyph mode. |
| `amber set <geminikey\|githubtoken\|model> [value]` | Convenience setter with a secure no-echo prompt. |
| `amber install-prompt [--shell bash\|fish\|both]` | Wire the prompt into your shell (backed up, reversible). |
| `amber uninstall-prompt [--shell bash\|fish\|both]` | Reverse `install-prompt`. |
| `amber install-motd` | Install a login banner for **all users** (sudo). |
| `amber uninstall-motd` | Remove the installed motd (sudo). |

**`amber update` channels:**

- *(default)* -- track the current branch's upstream (fast-forward only).
- `--stable` -- check out the latest `vX.Y.Z` release tag.
- `--edge` -- fast-forward `main`.
- `--no-verify` -- skip signature verification (**discouraged**; see below).

In every channel the order is **fetch → resolve target → verify → apply**, so
unverified code never lands in the working tree. A failed verification aborts
and leaves you on the current, already-trusted ref.

---

## Tools

### `ask` -- terminal assistant

Asks Gemini (optionally Google-grounded), renders the answer to your terminal,
and lists citations. Reads **stdin as extra context** when stdin is not a TTY.
`ask` is fully portable -- it needs nothing but `curl` and `jq`.

```
ask [options] <question>
<command> | ask [options] <question>
```

| Flag | Meaning |
| --- | --- |
| `-m`, `--model <id>` | Gemini model id (default `$AMBERCLI_MODEL`, else built-in). |
| `--no-search` | Disable Google Search grounding. |
| `--raw` | Raw output: no ANSI rendering, no citations. |
| `--yes` | Assume yes to prompts (e.g. the jq install prompt). |
| `--version` | Print the amber version and exit. |
| `-h`, `--help` | Show help. |

Override the system prompt with `$AMBERCLI_SYSTEM`, or by placing a file at
`~/.config/amber/system`.

```bash
ask how do I find files larger than 1G
journalctl -u nginx -n50 | ask 'why is nginx failing to start?'
ask --no-search 'rewrite this regex to be POSIX-safe: \d+'
```

### `qq` -- diagnose your screen

Captures the current terminal screen, strips `qq`'s own invocation line,
scrubs secrets, and asks Gemini to diagnose it. With no question it defaults to
*"explain what's happening here, especially any errors."*

```
qq [options] [question]
```

It accepts the same flags as `ask` (`-m/--model`, `--no-search`, `--raw`,
`--yes`, `--version`, `-h`). Override the system prompt with `$AMBERCLI_QQ_SYSTEM` or
`~/.config/amber/qq-system`.

> **`qq` needs a capture-capable terminal.** By default it uses
> **kitty** via `kitty @ get-text --extent=screen`, which requires kitty's
> remote control to be enabled. In `kitty.conf`:
>
> ```conf
> allow_remote_control yes        # or: allow_remote_control socket-only
> ```
>
> then restart kitty. For any other terminal/multiplexer, set
> `$AMBERCLI_QQ_CAPTURE_CMD` to a command that prints the screen.

```bash
qq
qq 'why did the build fail?'
AMBERCLI_QQ_CAPTURE_CMD='tmux capture-pane -p' qq          # tmux
AMBERCLI_QQ_CAPTURE_CMD='wezterm cli get-text' qq          # wezterm
```

`qq` strips its own command from the bottom of the capture using a prompt
marker, defaulting to `$(whoami)@$(hostname -s)`. If your prompt doesn't
contain that string, set `$AMBERCLI_QQ_PROMPT_MARKER` to a substring of your prompt
line so `qq` knows where its own invocation begins. (If the marker never
appears, `qq` fails open and keeps the whole capture.)

### `dcls` -- global docker overview

A prettier, cross-project `docker compose ps`: every compose **project** and the
containers under each, grouped and colour-coded by state. A clean exit (0) of a
stopped container stays calm grey; a non-zero exit goes red, so a crash jumps out
and a deliberately-stopped one-shot container doesn't cry wolf.

```
dcls
```

Needs `docker`. Run it from anywhere -- it ignores the current directory.

### `ipl` -- ip/host geolocation

Resolves a hostname's IPs (or takes an IP directly) and geolocates each via
ipwho.is.

```
ipl <hostname-or-ip>
```

Needs `curl` + `jq` and network access. Hostnames resolve through `getent`, so
`/etc/hosts` and DNS both apply.

### `ports` -- what's listening

A tidy view of every listening TCP/UDP socket: protocol, bind address:port, and
the process behind it. Sockets bound to all interfaces (`0.0.0.0` / `::`) are
flagged amber as exposed; loopback-only sockets stay grey.

```
ports
```

Needs `ss` (iproute2). Run with `sudo` to see process names you don't own.

### `wx` -- terminal weather

Current conditions plus a short forecast, from open-meteo (no API key). Pass a
place name, or nothing to locate yourself by public IP.

```
wx                       # weather where you are
wx kyoto                 # a named place
wx --fahrenheit london   # imperial units
```

Needs `curl` + `jq` and network access.

### `prs` -- your GitHub pull requests

Lists the PRs you've opened and the ones waiting on your review.

```
prs
```

Needs a GitHub token (first found wins): `$GITHUB_TOKEN`, `amber set githubtoken`,
or a logged-in `gh` CLI.

### `define` -- look up a word

Definitions, part of speech, and synonyms from the free Dictionary API.

```
define ephemeral
```

Needs `curl` + `jq` and network access.

### `disk` -- disk usage

Usage per real filesystem (pseudo mounts like tmpfs/overlay are skipped), with a
bar that goes green under 70%, amber 70-90%, and red at 90%+.

```
disk
```

### `svc` -- systemd services

Failed units in red, then a dim running/total summary. A healthy system is quiet.

```
svc
```

Needs `systemctl`.

### `cert` -- TLS certificate expiry

Days until a host's certificate expires: green with runway, amber as it nears,
red when it's close or already past.

```
cert example.com          # port defaults to 443
cert example.com:8443
```

Needs `openssl`.

---

## Environment variables

| Var | Meaning | Default |
| --- | --- | --- |
| `AMBERCLI_PREFIX` | Install prefix override (`LIB=$_/lib/amber`, `BIN=$_/bin`). | unset |
| `AMBERCLI_MODEL` | Gemini model id. | `gemini-3.5-flash` |
| `AMBERCLI_AUTOINSTALL` | `1` ⇒ skip the jq-install y/N prompt. | unset |
| `AMBERCLI_AUTO_UPDATE` | `1` ⇒ the update check may auto-run `amber update`. | unset (notify-only) |
| `AMBERCLI_NO_UPDATE_CHECK` | `1` ⇒ never check for updates. | unset |
| `AMBERCLI_GLYPHS` | `unicode` or `ascii`. | `unicode` (ascii if unset & non-UTF-8 locale) |
| `AMBERCLI_QQ_CAPTURE_CMD` | Screen-capture command for `qq`. | kitty remote control |
| `AMBERCLI_QQ_PROMPT_MARKER` | Marker used to strip `qq`'s own invocation. | `$(whoami)@$(hostname -s)` |
| `AMBERCLI_SYSTEM` | Override `ask`'s system prompt. | built-in |
| `AMBERCLI_QQ_SYSTEM` | Override `qq`'s system prompt. | built-in |
| `AMBERCLI_BASH_RIGHT_PROMPT` | `1` ⇒ enable the experimental bash right-prompt. | unset (off) |
| `AMBERCLI_NO_VERIFY` | `1` ⇒ bypass release signature verification (**discouraged**). | unset |

`GEMINI_API_KEY` is read from your config env file (see below) or the
environment.

---

## Config

Config lives in `~/.config/amber/` (honouring `$XDG_CONFIG_HOME`). Secrets and
overrides go in `~/.config/amber/env`, a shell-sourceable `KEY=value` file kept
**`chmod 600`**. `lib` sources it at load. Logical config keys map to env
vars: `geminikey → GEMINI_API_KEY`, `githubtoken → GITHUB_TOKEN`, `model → AMBERCLI_MODEL`,
`glyphs → AMBERCLI_GLYPHS`.

The safe way to set your key is the secure no-echo prompt:

```bash
amber set geminikey          # prompts; nothing echoed to the terminal
amber set model gemini-2.5-flash
```

> **Shell-history leak caveat.** You *can* pass the value inline
> (`amber set geminikey AIza...`), but that **writes your secret into your
> shell history**. `amber` warns you when you do this. **Prefer the no-echo
> prompt** (`amber set geminikey` with no value).

System-prompt override files: `~/.config/amber/system` (for `ask`) and
`~/.config/amber/qq-system` (for `qq`).

---

## Glyph modes

Prompts and tools draw a couple of status glyphs (a "cross" for nonzero exit,
a "hex" for docker compose):

| Glyph | unicode | ascii |
| --- | --- | --- |
| cross (nonzero exit) | `✘` | `x` |
| hex (docker compose) | `⬢` | `#` |

The mode is **unicode by default**, with an automatic fallback to **ascii**
when `$AMBERCLI_GLYPHS` is unset *and* your locale (`$LC_ALL`/`$LC_CTYPE`/`$LANG`)
isn't UTF-8. Switch explicitly with:

```bash
amber config glyphs ascii      # or: unicode
export AMBERCLI_GLYPHS=ascii       # per-session override
```

`ambercli_glyph`, `prompts/prompt.bash`, and `prompts/prompt.fish` all resolve glyphs from the
same rules, so bash and fish stay identical.

---

## Shell prompts

The prompt shows `[user@host] /path<segments>` then a newline and the `$`/`#`
indicator. The host's name is hashed to a stable, per-host colour, and
space-prefixed segments are appended for: nonzero exit code, docker compose
status (only when a compose file is in the cwd), git branch + dirty marker
(untracked files do **not** count as dirty), python venv, ssh, and root.

Install the prompt into one or both shells:

```bash
amber install-prompt                 # both shells present (default)
amber install-prompt --shell bash    # just bash
amber install-prompt --shell fish    # just fish
```

**fish** has a native right prompt: a dim `HH:MM` clock (plus the venv name
when a virtualenv is active). **bash** has no native right prompt; an
experimental, opt-in faked right-prompt is available:

```bash
AMBERCLI_BASH_RIGHT_PROMPT=1 amber install-prompt --shell bash
```

> **The bash right-prompt is experimental and fragile.** It uses
> save/restore-cursor tricks and `$COLUMNS`; on resize or line-wrap it can put
> the clock in the wrong place. It's off by default and degrades gracefully
> (it prints nothing rather than garbage when it can't place cleanly).

> ⚠️ **`install-prompt` edits your shell rc files** -- but it's backed up and
> reversible:
>
> - **bash:** a clearly-delimited managed block (`# >>> amber prompt >>>` …
>   `# <<< amber prompt <<<`) is written into `~/.bashrc`. A timestamped backup
>   (`~/.bashrc.amber-backup.<ts>`) is made first.
> - **fish:** a symlink is created at `~/.config/fish/conf.d/amber-prompt.fish`
>   pointing at the repo's `prompts/prompt.fish`. Any pre-existing real file there is
>   backed up first.
>
> Reverse it with `amber uninstall-prompt [--shell …]`: it removes the bash
> managed block (with another backup) and deletes the fish symlink.

---

## MOTD

`amber install-motd` installs a **dynamic** login banner -- it shows the host
(with the same per-host accent colour as the prompt), date, OS, kernel, uptime,
load, memory, disk, docker container counts, and IPs.

> ⚠️ **`install-motd` needs `sudo` and edits the SYSTEM motd for ALL users.**
> It prompts for confirmation, and the change is backed up and reversible:
>
> - On Debian-style systems with `/etc/update-motd.d/`, it installs the banner
>   **script** as executable `/etc/update-motd.d/00-amber` (root, via sudo);
>   `pam_motd` runs it fresh at every login.
> - Otherwise it writes a **static snapshot** of the banner to `/etc/motd`,
>   backing up the existing file first to `/etc/motd.amber-backup.<ts>`
>   (re-run `install-motd`, or `amber update`, to refresh the snapshot).
>
> Reverse it with `amber uninstall-motd`: it removes the Debian script, or
> restores `/etc/motd` from the recorded backup.

---

## Security model -- verifying releases

`amber` treats the code it's about to run as untrusted until a **GPG signature
from a pinned key** says otherwise. Both `install` and `amber update` verify
**before** anything lands on your `PATH`.

- **Pinned trust anchor.** A full **40-hex primary key fingerprint**,
  `AMBERCLI_SIGNING_FPR`, appears as a literal constant in **both** `install`
  (what you, the human, read over https) and `lib` (what the verifier
  enforces). `install` asserts the two copies match and aborts on drift.
- **Releases must be signed.** Tags are signed with `git tag -s`, and
  `ambercli_verify_ref` requires git's `--raw` output to emit an explicit
  `VALIDSIG` naming the pinned fingerprint -- **exit code alone is not trusted**,
  so a good signature from an *unknown* key does not pass.
- **The embedded key is never trusted blindly.** The public key is embedded
  directly in `lib` (`_ambercli_signing_key`), but the verifier imports it into an
  **ephemeral keyring** and checks that its primary fingerprint equals
  `AMBERCLI_SIGNING_FPR` before using it. `gpg` and `git` are required for
  verification (reported by `amber doctor`).
- **Fetch → verify → apply.** Both install and update fetch without merging,
  resolve the target ref, verify it, and only then check out / fast-forward and
  relink. A failed verify refuses and leaves you on the current verified ref.
- **The curl|bash trust anchor** is exactly the pinned fingerprint you inspect
  in `install` (fetched over https). The intended canonical host for the
  one-liner is **amber.sh** once that's set up.

**How Amber pins the key and signs releases:**

```bash
gpg --fingerprint                                       # read the 40-hex primary fpr
# put that fingerprint into AMBERCLI_SIGNING_FPR in BOTH install and lib
gpg --armor --export <fpr>                              # paste into _ambercli_signing_key() in lib
git tag -s vX.Y.Z -m 'amber vX.Y.Z'                     # sign the release tag
```

This repo's `AMBERCLI_SIGNING_FPR` is pinned to Amber's key
(`00FC77A24586FC735DA4AB26BE7CF33811ED73D4`) and the matching public key is
embedded in `lib`, so install/update verify out of the box.

> ⚠️ **Forking this repo? Re-pin to your own key.** If you publish your own
> releases, replace `AMBERCLI_SIGNING_FPR` in BOTH `install` and `lib` with
> your primary fingerprint and replace the key in `_ambercli_signing_key()` (in
> `lib`) with your exported public key. If the fingerprint is ever left at the
> placeholder `REPLACE_WITH_FULL_40_HEX_FINGERPRINT`, **verification hard-fails
> (refuses) by design** -- nothing installs or updates unless you pin a real key
> or pass the escape hatch.

**Escape hatch.** `--no-verify` (flag) and `$AMBERCLI_NO_VERIFY=1` bypass
verification, printing a loud stderr warning every time. This is **discouraged**
and intended only for development, key rotation, or first bootstrap.

---

## Auto-update is notify-only by default

`amber` checks for new releases but **does not pull them on its own**. The
reasoning is supply-chain hygiene: you should get a chance to review what
changed (and re-confirm the pinned key) before code runs on your machine.

How it works:

- On each interactive run, `amber` surfaces any *pending* result from a previous
  check as a single dim line on **stderr** pointing you at `amber update`.
- A background refresh runs **at most once / 24h** (timestamp touched *before*
  the network call, so a hang can't cause hammering). It queries the latest
  release tag, falling back to the default-branch HEAD sha.
- It never blocks the foreground command and never errors out on network
  failure.

Knobs:

- `AMBERCLI_AUTO_UPDATE=1` -- opt into auto-updates. These still go through
  `amber update`, so **signatures are still verified** before anything is
  applied.
- `AMBERCLI_NO_UPDATE_CHECK=1` -- disable the update check entirely.

---

## Uninstall

```bash
amber uninstall              # remove symlinks; offer to remove the library
amber uninstall-prompt       # remove the prompt from both shells
amber uninstall-motd         # sudo
```

`amber uninstall` removes only the symlinks that resolve into `LIB_DIR`, then
asks whether to delete the library directory. **Your config
(`~/.config/amber/`) is always preserved.**

> Installed prompts and motd **update automatically** when you run
> `amber update` -- the bash block sources the repo's `prompts/prompt.bash`, the fish
> conf.d entry is a symlink to `prompts/prompt.fish`, and `amber update` refreshes the
> installed motd copy in place.

---

## License

[MIT](LICENSE) © 2026 amber (amber@flourish.ch)
