# Cloned Machine Identity — Agent Skill

An [agent skill](https://github.com/anthropics/skills) for sanitizing a Linux
machine that was created from a disk image.

A restored image is a byte-for-byte copy of a filesystem, and that includes the
files that identify *which machine this is*. Restore one onto different
hardware and you get a working system still carrying the source machine's
machine-id, hostname, and journal.

This is not an edge case. Restoring an image to a laptop is the intended
workflow, and every restore does this.

## The skill

### `cloned-machine-identity`

- Telling a **clone** apart from the **source** machine and from a **fresh
  install** — only the first needs fixing, and the source is the one that looks
  most affected
- Detecting a clone from a stale hostname and inherited journal
- Regenerating a duplicate machine-id
- Fixing a hostname that names the wrong laptop
- Clearing logs carried over from the source machine
- SSH host key checks — when there is nothing to regenerate
- Rolling the fix across a fleet and proving the IDs are distinct

Two scripts ship with it:

| Script | Risk | Purpose |
|---|---|---|
| `survey-fleet-identity.sh` | Read-only, no root | Classify every machine as source, clone, or unique |
| `fix-cloned-machine-identity.sh` | **Destructive** | Apply the fix — hostname, machine-id, journal |

Survey first. The survey is safe on any machine, including ones that need no
work; the fix is not.

## Why this exists

Found on Omarchy (Arch/Hyprland) on an HP Pavilion 15, restored via the
Rescuezilla clone feature from an image of a Lenovo T440p. The restored system
booted cleanly, reported the correct hardware from DMI, and was still calling
itself `lenovot440p` with that machine's machine-id and eight days of its logs.

Nothing in a normal boot process checks these files, which is why the problem
survives an otherwise successful restore.

| Trap | Consequence |
|---|---|
| Running the fix on the source machine | Renames a healthy machine, wipes its real journal |
| `systemd-machine-id-setup` on an existing file | Exits 0, changes nothing, ID stays duplicated |
| `journalctl --vacuum-time=1s` | Not selective — discards the current machine's logs too |
| Assuming a fresh USB install is a clone | Nothing was inherited; nothing to fix |
| Skipping the vacuum to preserve logs | Does not work — the machine-id change discards them anyway |

### The journal clears itself

Regenerating the machine-id discards the inherited journal as a side effect.
No vacuum, no `journalctl` flags. systemd keys journal storage by machine-id,
so entries written under the previous ID stop being addressable and are
dropped on the next boot.

Measured on the same HP Pavilion 15, with the vacuum deliberately not run
`[PROVEN]`:

    before:  85,006 entries, oldest 2026-10-01, logged as lenovot440p
    after:    2,171 entries, every one from the current boot

This reframes the vacuum step. `journalctl --vacuum-time=1s` deletes by
timestamp across everything on disk, which is why it is not selective about
which machine wrote the entries. But by the time step 3 runs, step 1 has
already changed the machine-id and the inherited entries are gone anyway — so
the vacuum is belt-and-braces rather than the mechanism.

Two practical consequences:

- Expect to lose pre-restore logs either way. Skipping the vacuum does not
  preserve them, and that is worth knowing before treating a backup as intact.
- Step order does not affect the journal outcome. The hostname step is the
  only one that is genuinely selective about what it alters.

## Installation

```bash
git clone https://github.com/ssearles/cloned-machine-identity.git
cp -r cloned-machine-identity/skills/* ~/.agents/skills/
```

Skills live in `~/.agents/skills/`. The `description` field in the YAML
frontmatter determines when an agent loads it, so it is written as trigger
vocabulary.

For a one-off on a machine you are sitting at, the fix alone is enough:

```bash
sudo ./skills/cloned-machine-identity/fix-cloned-machine-identity.sh <new-hostname>
```

## Confidence markers

Claims are tagged throughout:

- **`[PROVEN]`** — directly observed and diagnosed on real hardware
- **`[INFERRED]`** — concluded from output, not isolated in a controlled test

The distinction matters: some guidance is established by measurement, some is
reasoned from symptoms. Treat them accordingly.

## Requirements

Linux with `systemd` (`systemd-machine-id-setup`), `journalctl`, and Python 3
for the survey's journal-hostname probe. Root for the fix, none for the survey.

No sudo is needed for diagnosis, which is deliberate — the read-only checks are
safe on any machine, including the source.

## Related

Companion to [`disk-backup-skills`](https://github.com/ssearles/disk-backup-skills),
which covers the imaging workflow these problems come from.

## Licence

MIT — use, modify, redistribute freely.
