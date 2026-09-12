# social-block

Block the sites that eat your evenings, on a schedule, on Linux.

`social-block` null-routes a list of hostnames in `/etc/hosts` during the hours
you choose — 22:00 to 06:00 every night, 09:00 to 17:00 on weekdays, whatever you
set — and lifts the block again by itself. One shell script, one config file,
one systemd service. No account, no browser extension, nothing phoning home.

It is a **commitment device, not a security boundary**. You have root, so you can
always undo it. What it does is make "just a quick look" cost more than it is
worth at one in the morning.

## Install

```sh
git clone https://github.com/anmol-goyal7/social-block
cd social-block
sudo ./install.sh
```

The installer asks three questions — block from, block until, which days —
writes `/etc/social-block/config`, starts the service and shows you the status.
Or answer up front:

```sh
sudo ./install.sh --from 22:00 --until 06:00 --days weekdays
sudo ./install.sh --no-prompt        # 22:00-06:00 daily, no questions
```

Re-running the installer upgrades the code and keeps your config.

Needs Linux with systemd, bash 4.4 or newer and GNU coreutils — every mainstream
distro. Read `bin/social-block` before you run it as root; it is one file and it
was written to be read.

## The one thing that breaks it: DNS-over-HTTPS

If your browser resolves names over DNS-over-HTTPS ("secure DNS"), it never asks
the system resolver, never sees `/etc/hosts`, and this block **silently does
nothing** while looking perfectly installed. Turn it off:

- **Chrome / Brave / Edge / Chromium:** Settings → Privacy and security →
  Security → *Use secure DNS* → **off**
- **Firefox:** `about:config` → `network.trr.mode` → **5**

Then run `social-block doctor`. It reads your browser profiles (read-only) and
tells you if anything would stop the block from working.

## Configure

Everything lives in `/etc/social-block/config`. Edit it, save it — it is live
within a minute, no reload. Check it any time with `social-block check`.

```ini
[schedule]
22:00-06:00 daily
09:00-17:00 weekdays

[options]
lock = false

[sites]
instagram.com
reddit.com
old.reddit.com
x.com
```

- **Windows** are `START-END [DAYS]` in 24-hour local time, as many lines as you
  like. `DAYS` is `daily` (the default), `weekdays`, `weekends`, a list
  (`mon,wed,fri`) or a range (`mon-fri`, `fri-mon`).
- A window whose end is earlier than its start **crosses midnight and belongs to
  the day it starts on**: `22:00-06:00 mon-fri` still blocks Saturday at 02:00
  (that window started Friday) and does not block Monday at 02:00 (that one
  would have started Sunday).
- Start is inclusive, end is exclusive: at 22:00 you are blocked, at 06:00 you
  are not.
- **Sites** are one hostname per line; `www.` and `m.` variants are added for
  you. The shipped list covers Instagram, LinkedIn, X/Twitter and Reddit with
  their short links and side doors (`old.reddit.com` serves the whole site past
  a plain `reddit.com` block). YouTube, TikTok, Facebook and Snapchat are in the
  file, commented out.

## Commands

| Command | What it does |
|---|---|
| `social-block status` | what is blocked right now, why, and when that next changes |
| `sudo social-block on` | block now, until the next scheduled change |
| `sudo social-block off` | unblock now, until the next scheduled change |
| `social-block check [FILE]` | validate a config and show what it means |
| `social-block doctor` | find out why the block is not working |
| `sudo social-block apply` | reconcile `/etc/hosts` right now instead of within a minute |

### `off` is temporary

`social-block off` lifts the block only until the next scheduled change — the
end of the current window, or the start of the next one. Then the schedule takes
over again. There is no way to accidentally leave it off forever; to stop it for
good, uninstall it.

### Lock mode

Set `lock = true` and an active window refuses `social-block off` until it ends.
That is the entire feature: one refused command. Outside a window, `on` and
`off` behave as usual.

The escape hatch, because you should always know it: `sudo systemctl stop
social-block`, then delete the lines between `# BEGIN social-block` and
`# END social-block` in `/etc/hosts`. Whether you use it is between you and
your future self.

## How it works

A small service runs `social-block apply` once a minute. Each pass reads the
config, decides whether the block should be on *right now*, and rewrites the
region between the two sentinel comments in `/etc/hosts` only if it differs from
what is there. Because every pass starts from scratch, there is nothing to
"catch up": boot at noon after a missed 22:00 is simply off, resume from
suspend converges within a minute, a config edit is live within a minute, and a
hand-edited region heals itself within a minute.

Nothing outside the sentinels is ever touched. Replacement is atomic (write a
temporary file next to `/etc/hosts`, move it over). Both an IPv4 (`0.0.0.0`) and
an IPv6 (`::`) line are written per host so a resolver that asks per address
family cannot leak.

What it puts on your system:

| Path | Purpose |
|---|---|
| `/usr/local/bin/social-block` | the tool |
| `/etc/systemd/system/social-block.service` | the service |
| `/etc/social-block/config` | your schedule and sites |
| `/var/lib/social-block/` | a temporary `on`/`off` override, if any |
| `/etc/hosts.social-block-orig` | a copy of `/etc/hosts` from before the first install, taken once |

A switch takes effect within a couple of seconds: systemd-resolved re-checks
`/etc/hosts` at most every two seconds. Open tabs and a browser's own DNS cache
outlive it, though — if a site still loads right after 22:00, that is why
(Chrome: `chrome://net-internals/#dns` → *Clear host cache*).

## Uninstall

```sh
sudo ./uninstall.sh            # keeps /etc/social-block/config
sudo ./uninstall.sh --purge    # removes the config too
```

Stops the service, removes the block from `/etc/hosts`, deletes the tool and the
unit. During a locked window it refuses, like `off` does.

## Development

```sh
bats tests            # bats-core; every test runs against a temp hosts file
shellcheck -x bin/social-block install.sh uninstall.sh
```

Set `SOCIAL_BLOCK_NOW='2026-09-12 23:00'` to ask what the tool would do at some
other moment, e.g. `SOCIAL_BLOCK_NOW='sat 02:00' social-block status`.

## License

MIT.
