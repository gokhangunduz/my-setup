---
description: Diff this machine against install.sh and propose list updates (drift check)
---

# /reconcile — machine ↔ install.sh drift check

`install.sh` is the single source of truth for this Mac's setup. Over time the machine
drifts from it: packages get added/removed, casks get renamed or deprecated (e.g.
`codex-app` folded into `chatgpt`), new apps land in the Dock. Your job is to find that
drift, verify the interesting cases, and propose concrete `install.sh` edits — **do not
edit or commit anything without the user's approval.**

Everything here is read-only until the user approves. Work top to bottom.

## 1. Read the source of truth

Read `install.sh` and extract these arrays: `TAPS`, `FORMULAE`, `CASKS`, `MAS_APPS`
(`id|name`), `DOCK_APPS`. This awk helper parses any of them:

```bash
SH=install.sh
arr() { awk -v k="$1" '$0 ~ "^" k "=\\(" {f=1;next} f&&/^\)/{f=0} f{sub(/#.*/,"");gsub(/^[ \t]+|[ \t]+$/,"");gsub(/"/,"");if(length)print}' "$SH"; }
# e.g. arr FORMULAE   arr CASKS   arr TAPS   arr MAS_APPS   arr DOCK_APPS
```

## 2. Gather the machine's real state

```bash
brew tap                       # taps
brew leaves                    # explicitly-installed formulae (not deps)
brew list --cask               # casks
mas list                       # Mac App Store apps (id + name)
dockutil --list                # dock items (label \t url \t section \t plist \t bundleid)
```

## 3. Diff both directions

Run this and read the output:

```bash
bash -c '
SH=install.sh
arr() { awk -v k="$1" "\$0 ~ \"^\" k \"=\\\\(\" {f=1;next} f&&/^\)/{f=0} f{sub(/#.*/,\"\");gsub(/^[ \t]+|[ \t]+\$/,\"\");gsub(/\"/,\"\");if(length)print}" "$SH"; }

echo "== FORMULAE: in script, NOT installed =="
while read -r f; do [ -z "$f" ] && continue; brew list --formula --versions "$f" >/dev/null 2>&1 || echo "  !! $f"; done < <(arr FORMULAE)
echo "== FORMULAE: installed leaf, NOT in script =="
sf="$(arr FORMULAE)"
while read -r leaf; do base="${leaf%@*}"; base="${base##*/}"; printf "%s\n" "$sf" | grep -qxF "$leaf" && continue; printf "%s\n" "$sf" | grep -qxF "$base" && continue; echo "  ++ $leaf"; done < <(brew leaves)
echo "== CASKS diff =="; diff <(arr CASKS|sort) <(brew list --cask|sort) | grep "^[<>]" | sed "s/^</  in script, not installed:/; s/^>/  installed, not in script:/" || echo "  match"
echo "== TAPS diff =="; diff <(arr TAPS|sort) <(brew tap|sort) | grep "^[<>]" || echo "  match"
echo "== MAS: in script, not on machine =="; comm -23 <(arr MAS_APPS|sed "s/|.*//"|sort) <(mas list|awk "{print \$1}"|sort) | grep . || echo "  none"
echo "== MAS: on machine, not in script =="; comm -13 <(arr MAS_APPS|sed "s/|.*//"|sort) <(mas list|awk "{print \$1}"|sort) | while read -r id; do echo "  ++ $id $(mas list|grep ^$id)"; done
'
```

**Normalisation / known false-positives — do NOT report these as drift:**
- Formula aliases: `postgresql`→`postgresql@NN`, `python`→`python@NN`. Already handled by the
  base-name strip above; if a versioned leaf maps to an unversioned script entry, it matches.
- Tapped formulae show as `mongodb/brew/mongodb-community` in `brew leaves` but `mongodb-community`
  in the script — same thing, not drift.
- `git` is added by the script automatically (a task, not in `FORMULAE`) — never flag it.
- **Intentionally excluded** leaves the user does NOT want in the script (keep this list current):
  `actionlint`, `age`, `coreutils`. Note them as "known-excluded", don't propose adding them.

## 4. Verify the interesting cases (this is the point)

For every real diff that isn't in the ignore list above, don't guess — verify:
- **Removed from machine but still in script:** ask the user if they still want it on a fresh
  Mac (they may have uninstalled deliberately, or it may have broken). Don't assume.
- **A cask/formula that looks renamed, deprecated, or moved:** run `brew info <name>` and
  `brew info --cask <name>`; if it looks deprecated/relocated, **web-search** to confirm where
  it went (this is how we caught `codex-app` → merged into `chatgpt`, and `codex` being the
  separate terminal CLI). Report the finding with the source.
- **New leaf/cask on the machine:** decide with the user whether it's intentional (add) or
  incidental/a dependency (skip — the user's rule: don't put dependencies in the script,
  they come by themselves).

## 5. Dock

Compare `dockutil --list` (persistentApps, in order) against `DOCK_APPS`. Note that
`arrange_dock_apps` rebuilds to the exact list, so order matters. Flag apps present in one
but not the other. Safari may show a `…/Cryptexes/…/Safari.app` path on the machine vs
`/Applications/Safari.app` in the script — same app, converges on first rebuild, not drift.

## 6. Report + propose (no writes)

Produce a short report:
- ✓ what's already in sync (one line per category)
- ➕ / ➖ real drift, each with your recommendation and — for anything verified via web — the source
- The exact `install.sh` edits you'd make (array additions/removals), grouped by array

Then ask the user which changes to apply. Only after they approve do you edit `install.sh`
(and, if they ask, install/uninstall on the machine and commit). The script stays the single
source of truth; you are the maintenance layer, not a replacement for it.
