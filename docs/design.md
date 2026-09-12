# social-block — design

*2026-09-12. This is the document the implementation follows; if the code and
this file disagree, one of them is a bug.*

## 1. What it is

A Linux tool that blocks a list of sites during time windows you choose, by
null-routing them in `/etc/hosts`. It is a **commitment device**, not a
security boundary: the person installing it has root and can always undo it.
The tool is honest about that everywhere it speaks.

Install once, configure in one file, forget about it. Nothing about the
schedule ever touches systemd after install.

## 2. Non-goals

- Blocking anything other than hostnames (no firewall, no per-app rules).
- Resisting root. `lock` (§5.5) refuses the tool's own `off`; that is all.
- Any platform other than Linux with systemd.
- A GUI, a tray icon, statistics, streaks.

## 3. The config file — `/etc/social-block/config`

Root-owned, written once by the installer, hand-edited afterwards. There are
**no hidden defaults**: the schedule and the site list are exactly what the
file says. The file is parsed line by line and never `source`d.

```ini
[schedule]
22:00-06:00 daily
09:00-17:00 mon-fri

[options]
lock = false

[sites]
instagram.com
reddit.com
```

Grammar:

- `#` starts a comment (whole line or trailing, preceded by whitespace).
  Blank lines are ignored. Leading/trailing whitespace is ignored.
- Section headers are `[schedule]`, `[options]`, `[sites]`. Any other header,
  or a non-blank line before the first header, is an error.
- **schedule line:** `H:MM-H:MM [DAYS]`. Hours 0–23 (one or two digits),
  minutes exactly two digits 00–59. Start must differ from end. `DAYS` is
  optional and defaults to `daily`. It is a comma-separated list of tokens,
  each one of: a day name `mon tue wed thu fri sat sun`, a range `mon-fri`
  (wrapping allowed: `fri-mon` = fri,sat,sun,mon), or an alias `daily`,
  `weekdays`, `weekends`. Case-insensitive.
- **options line:** `key = value`. The only key is `lock` with values `true`
  or `false`. Unknown keys are errors.
- **sites line:** one hostname, lowercased, matching
  `^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$`.
  The `www.` and `m.` variants are generated automatically for every entry.
  Anything else is an error.
- Every error names the line: `config:14: bad time "25:00"`. Parsing reports
  **all** errors, not just the first.

The shipped default config (what the installer writes with no answers given)
is `22:00-06:00 daily`, `lock = false`, and this site list:
`instagram.com linkedin.com x.com twitter.com reddit.com old.reddit.com
new.reddit.com np.reddit.com redd.it i.redd.it v.redd.it instagr.am lnkd.in
t.co`, with `youtube.com`, `tiktok.com`, `facebook.com`, `snapchat.com`
present but commented out as suggestions.

## 4. Commands

| Command | Root | Does |
|---|---|---|
| `social-block status` | no | current state, the window responsible, the next change, override, lock |
| `social-block apply` | yes | reconcile `/etc/hosts` with config + now, exit. Idempotent |
| `social-block on` | yes | force ON until the next boundary |
| `social-block off` | yes | lift until the next boundary; **refused under lock** during a window |
| `social-block check [FILE]` | no | validate a config (default the installed one), print the parsed schedule |
| `social-block doctor` | no | diagnose "it isn't working" (§7) |
| `social-block daemon` | yes | the loop the service runs (§6.3); not for humans |
| `social-block version`, `help` | no | |

Exit codes: `0` ok · `1` runtime error · `2` usage · `3` refused by lock ·
`4` config invalid.

"Root" means the target hosts file is not writable by the caller. The check is
on writability, not on `EUID`, so tests can point the tool at a temp file.

## 5. Semantics

### 5.1 Time
All times are local wall-clock, minute resolution. "Now" comes from `date`,
overridable by `SOCIAL_BLOCK_NOW` (anything GNU `date -d` accepts) for tests
and debugging.

### 5.2 A window is active when…
For a window `S-E` with day set `D`, day-of-week `dow` and minute-of-day `m`:

- **same-day** (`S < E`): active iff `dow ∈ D` and `S ≤ m < E`.
- **crosses midnight** (`S > E`): active iff (`dow ∈ D` and `m ≥ S`) or
  (`yesterday(dow) ∈ D` and `m < E`).

So the day filter applies to the day the window **starts**:
`22:00-06:00 mon-fri` blocks Saturday 02:00 (started Friday) and does not
block Monday 02:00 (would have started Sunday). Start is inclusive, end is
exclusive: at 22:00 you are blocked, at 06:00 you are not.

The schedule is active iff any window is active. Windows may overlap freely.

### 5.3 Next boundary
The next instant at which "schedule active" flips. Computed exactly: the
candidates are every window's start and end instants over the next 8 days
(via `date -d "YYYY-MM-DD HH:MM"`, so DST is handled by `date`), sorted; the
first candidate at which the aggregate state differs from now is the
boundary. If none flips (empty schedule, or 24×7 coverage) there is no
boundary.

### 5.4 Override
`on`/`off` write `/var/lib/social-block/override`, two lines:
```
state=on|off
until=<unix epoch>
```
`until` is the next boundary, or now + 24 h if there is none. The desired
state is:

```
desired(now) = override.state          if override exists and now < until
             = schedule_active(now)    otherwise
```
`apply` deletes an expired override. Overrides are therefore always
temporary; the schedule reasserts itself at the next boundary no matter what.

### 5.5 Lock
With `lock = true`, `off` is **refused (exit 3)** while the schedule is
active. That is the whole feature. `on` is always allowed; `off` outside a
scheduled window (e.g. lifting a manual `on`) is always allowed.

The README states the escape hatch plainly:
`sudo systemctl stop social-block` then delete the region between
`# BEGIN social-block` and `# END social-block` in `/etc/hosts`.

### 5.6 Invalid config — fail open
If the config does not parse, `apply` **removes the block** and reports the
error; `status`/`check` print the error and exit 4; `on`/`off` still work,
with `until = now + 24 h`. An unblocked machine is the safe
default for a tool strangers install; a typo must never lock anyone out.
The daemon logs a config error once when it appears (last error remembered in
`/var/lib/social-block/last-error`), not once per minute.

## 6. Enforcement

### 6.1 The hosts region
Only the lines between the sentinels are ever touched:
```
# BEGIN social-block
0.0.0.0 instagram.com www.instagram.com m.instagram.com
:: instagram.com www.instagram.com m.instagram.com
...
# END social-block
```
Both an IPv4 (`0.0.0.0`) and an IPv6 (`::`) line per host, so a resolver
that asks per address family (`hosts: files dns` answering AAAA from DNS
when the file only has A) cannot leak. The rest of the file is preserved
byte-for-byte, including a missing trailing newline (one is added before the
region when needed) and a damaged or duplicated region (all are dropped and
one is rewritten).

### 6.2 Writing
`apply` renders the complete desired file and **compares it to the current
one; if identical it exits without touching anything** — no write, no
resolver flush, no log line. On a difference: `mktemp` in the same directory,
write, `chmod`/`chown --reference` the original (mktemp's 0600 would break
name resolution for every non-root process), `mv` over it atomically, then
`resolvectl flush-caches` if `resolvectl` exists (systemd-resolved caches
answers and may otherwise serve the pre-switch address for a while). One
line to stderr per state change: `social-block: on (22:00-06:00 daily, until
06:00)`.

The installer takes a one-time pristine copy, `/etc/hosts.social-block-orig`,
only if it does not already exist. Nothing else ever backs up `/etc/hosts`
— a per-run backup would just be last minute's file.

### 6.3 The daemon
`social-block daemon` is `while true: apply; sleep to the next minute
boundary`. It is one long-lived process rather than a systemd timer so that
the journal does not gain three lines every minute; the loop itself prints
nothing unless state changes. Because it recomputes from scratch each tick:

- boot at noon after a missed 22:00 is simply "off" — no `Persistent`
  replay, no `ExecCondition` clock guard;
- resume from suspend converges within 60 s, with no sleep hook;
- a config edit is live within 60 s, with no reload;
- a hand-mangled region heals within 60 s.

Worst-case lag at a boundary is 60 s. The sleep is `60 - current second`, so
ticks land on the minute.

### 6.4 systemd unit
`/etc/systemd/system/social-block.service`: `Type=simple`,
`ExecStart=/usr/local/bin/social-block daemon`, `Restart=always`,
`RestartSec=5`, `ConditionPathExists=/etc/social-block/config`, modest
hardening (`ProtectHome=yes`, `PrivateTmp=yes`, `NoNewPrivileges=yes`,
`ProtectKernelTunables=yes`, `ProtectControlGroups=yes`,
`ProtectSystem=strict` with `ReadWritePaths=/etc /var/lib/social-block`),
`WantedBy=multi-user.target`. No timer unit exists.

## 7. `doctor`

Runs as the invoking user (browser profiles are found via `SUDO_USER` when
run under sudo). Prints one line per check with `✓` / `⚠` / `✗`, a fix under
each `✗`, and exits 1 if any `✗`.

1. **service** — `systemctl is-enabled` / `is-active social-block.service`.
2. **config** — parses; prints window count, site count, lock.
3. **hosts** — the region's presence matches `desired(now)`.
4. **nsswitch** — the `hosts:` line contains `files` or `resolve`; ✗ otherwise.
5. **DNS-over-HTTPS in browsers** — the failure mode that makes this tool
   silently do nothing, because a browser resolving over DoH never reads
   `/etc/hosts`:
   - Chromium family (`~/.config/google-chrome`, `chromium`,
     `BraveSoftware/Brave-Browser`, `microsoft-edge`, `vivaldi`): `Local
     State` → `dns_over_https.mode`: `off` ✓, `secure` ✗, `automatic` ⚠
     (upgrades to DoH when the system DNS is a known provider such as
     1.1.1.1). Also `DnsOverHttpsMode` in `/etc/opt/chrome/policies`,
     `/etc/chromium/policies`.
   - Firefox (`~/.mozilla/firefox/*/prefs.js`): `network.trr.mode`: `5` ✓,
     `2`/`3` ✗, unset/`0` ⚠ (not explicitly disabled).
   - Profiles that do not exist are skipped silently.
6. **running browser** — `pgrep` for chrome/chromium/brave/firefox: ⚠ that
   an open browser's DNS cache and open tabs outlive the switch.

## 8. Install and uninstall

`sudo ./install.sh [--from H:MM --until H:MM --days DAYS] [--no-prompt]`

1. Refuse without root, without systemd (`/run/systemd/system` absent), or
   without GNU `date`.
2. `install -Dm755 bin/social-block /usr/local/bin/`, unit to
   `/etc/systemd/system/`, `mkdir -p /var/lib/social-block`.
3. Config: if `/etc/social-block/config` exists, keep it (re-running the
   installer is an upgrade). Otherwise, if flags were given use them; else
   if stdin is a TTY and not `--no-prompt`, ask *Block from [22:00]*, *Block
   until [06:00]*, *Days [daily]*, validating each answer with `social-block
   check` on a temp file until it passes; else write the shipped default.
4. Pristine copy of `/etc/hosts` (§6.2).
5. `systemctl daemon-reload && systemctl enable --now social-block.service`.
6. Print `social-block status`, then the DoH warning and `social-block
   doctor` as the next step.

`sudo ./uninstall.sh [--purge]`: `systemctl disable --now`, `social-block
off` (which may be refused under lock — then uninstall stops and says so),
remove binary and unit, `daemon-reload`, remove `/var/lib/social-block`;
`--purge` also removes `/etc/social-block`. The pristine copy is left for
the user.

## 9. Repository layout

```
social-block/
├── LICENSE                 MIT
├── README.md
├── install.sh
├── uninstall.sh
├── bin/social-block        the whole tool, one auditable file
├── systemd/social-block.service
├── config.example          the shipped default config, commented
├── docs/design.md          this file
├── tests/*.bats            bats-core
└── .github/workflows/ci.yml   shellcheck + bats on every push
```

`bin/social-block` is a single file so that someone can read the entire
thing they are about to run as root. It ends with
`[[ ${BASH_SOURCE[0]} != "$0" ]] || main "$@"` so tests can `source` it and
call functions directly.

## 10. Testing

`bats` unit tests source the script and drive it through environment
overrides, never touching the real system:

- `SOCIAL_BLOCK_HOSTS` — hosts file under test
- `SOCIAL_BLOCK_CONFIG` — config under test
- `SOCIAL_BLOCK_STATE` — state directory (override, last-error)
- `SOCIAL_BLOCK_NOW` — fixed "now"

Coverage, at minimum:

- **parse:** every grammar rule in §3, every error case, multiple errors
  reported together, aliases and wrapping ranges, comments and whitespace.
- **active:** same-day, midnight-crossing, start-day rule for day filters
  (Sat 02:00 under `mon-fri` is blocked; Mon 02:00 is not), boundary
  inclusivity, overlapping windows, empty schedule.
- **next boundary:** same-day, midnight-crossing, day-filtered gaps
  (Saturday 06:00 under `22:00-06:00 mon-fri` → Monday 22:00, skipping the
  weekend), no boundary.
- **hosts:** region added / removed / rewritten idempotently; foreign lines,
  mode, owner and missing trailing newline preserved; duplicate and broken
  regions collapsed; unchanged file not rewritten (mtime unchanged).
- **override:** written with the boundary as expiry, honoured, expired
  ignored and deleted, `lock` refuses `off` during a window and allows it
  outside one, `on` always allowed.
- **apply end-to-end:** config + now + override → expected file.
- **invalid config:** `apply` removes the block; `status`/`check` exit 4.
- `shellcheck` clean on every script.

Then a manual pass on a real machine: install, `status`, `on`/`off`,
`getent ahosts reddit.com` → `0.0.0.0`/`::`, an HTTPS request fails, lock
refusal, a config edit going live within a minute, `doctor`, uninstall,
reinstall.

## 11. Things the README must say

- Exactly what it does and does not protect against (§1, §5.5).
- The DoH caveat, first and loudest, with the Chrome and Firefox settings.
- That `off` is temporary and the schedule comes back.
- The lock escape hatch.
- The start-day rule for midnight-crossing windows.
- How to uninstall completely.
