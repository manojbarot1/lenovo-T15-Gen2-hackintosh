#!/bin/sh
# Run from macOS Recovery Terminal on the T15:
#   curl -o /tmp/ssh.sh http://192.168.1.22:8088/ssh.sh && sh /tmp/ssh.sh
# Enables sshd on the installed Ventura and authorizes the T14's public key
# for every local user, so Claude can log in with the key (no password needed).
KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINP7NTGQdcE/p3Shk7dnhsHh8s5uSitdjwiCqE5r5Usc claude-t15-macos'
D=$(ls -d "/Volumes/Macintosh HD - Data" "/Volumes/Data" 2>/dev/null | head -1)
if [ -z "$D" ]; then
  V=$(diskutil apfs list | awk '/Macintosh HD - Data|Data \(Role/ {getline; print}' | grep -oE 'disk[0-9]+s[0-9]+' | head -1)
  diskutil mount "${V:-Macintosh HD - Data}" >/dev/null 2>&1
  D=$(ls -d "/Volumes/Macintosh HD - Data" "/Volumes/Data" 2>/dev/null | head -1)
fi
[ -d "$D/Users" ] || { echo "Could not find the macOS Data volume - send Claude: diskutil list"; exit 1; }
echo "Data volume: $D"
for H in "$D"/Users/*; do
  U=$(basename "$H"); [ "$U" = Shared ] && continue; [ -d "$H" ] || continue
  O=$(stat -f %u "$H"); G=$(stat -f %g "$H")
  mkdir -p "$H/.ssh"; grep -qF "$KEY" "$H/.ssh/authorized_keys" 2>/dev/null || echo "$KEY" >> "$H/.ssh/authorized_keys"
  chown -R $O:$G "$H/.ssh"; chmod 700 "$H/.ssh"; chmod 600 "$H/.ssh/authorized_keys"
  echo "Key added for user: $U"
done
P="$D/private/var/db/com.apple.xpc.launchd/disabled.plist"
mkdir -p "$(dirname "$P")"
/usr/libexec/PlistBuddy -c "Delete :com.openssh.sshd" "$P" >/dev/null 2>&1
/usr/libexec/PlistBuddy -c "Add :com.openssh.sshd bool false" "$P" && echo "SSH enabled for next boot"
echo "--- check:"
/usr/libexec/PlistBuddy -c "Print :com.openssh.sshd" "$P"
ls -la "$P"; diskutil info "$D" | grep -E "Volume Name|Mount Point|Role|Device Identifier"
ls "$D/Users"
echo "Done - restart, choose 'Macintosh HD (external)', log in, and tell Claude."
