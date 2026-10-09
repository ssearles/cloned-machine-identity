#!/usr/bin/env bash
# De-duplicate a machine restored from a disk image (Rescuezilla, Clonezilla, dd).
#
# A restored image carries the source machine's identity: hostname, machine-id,
# and its system journal. On a network with both machines live, the duplicate
# machine-id causes DHCP collisions and ambiguous logs.
#
# Usage:  sudo ./fix-cloned-machine-identity.sh <new-hostname>
# Re-run safely: every step is idempotent.

set -euo pipefail

NEW_HOSTNAME="${1:-}"
if [[ -z "$NEW_HOSTNAME" ]]; then
	echo "usage: sudo $0 <new-hostname>" >&2
	exit 2
fi

OLD_HOST="$(hostname)"
OLD_MACHINE_ID="$(cat /etc/machine-id)"

echo "=== BEFORE ==="
echo "  hostname:   $OLD_HOST"
echo "  machine-id: $OLD_MACHINE_ID"
echo "  journal:    $(journalctl --no-pager 2>/dev/null | wc -l) entries"
echo

# 1. Fresh machine-id. Must be removed (or truncated) before setup will regenerate.
#    Skipping this is the whole point: identical IDs across two live machines cause
#    DHCP lease collisions and make log aggregation ambiguous.
#
#    The removal is destructive and happens first, so regeneration is treated as
#    fallible rather than assumed. If the systemd tool fails, fall back to the
#    kernel UUID source, then assert the file is non-empty. Without these two
#    checks a failed regeneration leaves the machine with NO machine-id at all,
#    which is worse than the duplicate we started with -- and because the ID is
#    already gone, the original cannot be recovered from this script's state.
echo "==> Regenerating machine-id"
rm -f /etc/machine-id
if ! systemd-machine-id-setup; then
	echo "    systemd-machine-id-setup failed, using /proc fallback" >&2
	cat /proc/sys/kernel/random/uuid | tr -d '-' > /etc/machine-id
fi
if [[ ! -s /etc/machine-id ]]; then
	echo "ERROR: machine-id was removed but not regenerated." >&2
	echo "       Recover with:" >&2
	echo "         cat /proc/sys/kernel/random/uuid | tr -d '-' | sudo tee /etc/machine-id" >&2
	echo "         sudo chmod 444 /etc/machine-id" >&2
	exit 1
fi
chmod 444 /etc/machine-id
echo "    new machine-id: $(cat /etc/machine-id)"

# 2. Correct hostname. Appears in prompts, mDNS/Avahi, DHCP leases, logs.
echo "==> Setting hostname to '$NEW_HOSTNAME'"
hostnamectl set-hostname "$NEW_HOSTNAME"

# 3. Drop the inherited journal. This removes ALL logs older than the cutoff,
#    including this machine's own -- it is not selective about the source machine.
echo "==> Rotating and vacuuming inherited journal"
journalctl --rotate --vacuum-time=1s >/dev/null 2>&1 || true
echo "    journal now: $(journalctl --no-pager 2>/dev/null | wc -l) entries"

echo
echo "=== AFTER ==="
echo "  hostname:   $(hostname)"
echo "  machine-id: $(cat /etc/machine-id)"
echo
if [[ "$(cat /etc/machine-id)" == "$OLD_MACHINE_ID" ]]; then
	echo "WARNING: machine-id unchanged -- the old ID may still be in use."
	exit 1
fi
echo "Done. Reboot to pick up the new hostname everywhere."
