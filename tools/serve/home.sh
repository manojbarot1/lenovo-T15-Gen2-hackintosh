#!/bin/sh
# Run from macOS Recovery Terminal on the T15:
#   curl -o /tmp/home.sh http://192.168.1.22:8088/home.sh && sh /tmp/home.sh
# The installed Ventura's /Users carries the SIP "restricted" flag, so macOS cannot create
# /Users/manojb and the first login spins forever. Recovery is not bound by the installed
# system's SIP: clear the flag, build the home folder from Apple's template, add Claude's key.
U=manojb
KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINP7NTGQdcE/p3Shk7dnhsHh8s5uSitdjwiCqE5r5Usc claude-t15-macos'
D=$(ls -d "/Volumes/Macintosh HD - Data" "/Volumes/Data" 2>/dev/null | head -1)
if [ -z "$D" ]; then
  diskutil mount "Macintosh HD - Data" >/dev/null 2>&1
  D=$(ls -d "/Volumes/Macintosh HD - Data" "/Volumes/Data" 2>/dev/null | head -1)
fi
[ -d "$D/Users" ] || { echo "Could not find the macOS Data volume - send Claude: diskutil list"; exit 1; }
echo "Data volume: $D"
REC="$D/private/var/db/dslocal/nodes/Default/users/$U.plist"
UID_=$(/usr/libexec/PlistBuddy -c "Print :uid:0" "$REC" 2>/dev/null); UID_=${UID_:-501}
echo "User $U uid $UID_"

echo "--- before:"; ls -ldO "$D/Users"
chflags norestricted "$D/Users" && echo "restricted flag cleared"
H="$D/Users/$U"
if [ ! -d "$H" ]; then
  mkdir "$H" || exit 1
  diskutil mount "Macintosh HD" >/dev/null 2>&1
  T="/Volumes/Macintosh HD/System/Library/User Template"
  if [ -d "$T/Non_localized" ]; then
    ditto "$T/Non_localized" "$H"; ditto "$T/English.lproj" "$H"; echo "home built from Apple template"
  else
    echo "template not found - created an empty home (macOS fills it in at login)"
  fi
fi
mkdir -p "$H/.ssh"
grep -qF "$KEY" "$H/.ssh/authorized_keys" 2>/dev/null || echo "$KEY" >> "$H/.ssh/authorized_keys"
chown -R "$UID_:20" "$H"
chmod 750 "$H"; chmod 700 "$H/.ssh"; chmod 600 "$H/.ssh/authorized_keys"
echo "--- after:"; ls -ldO "$D/Users" "$H"; ls -la "$H" "$H/.ssh"
echo "Done - restart, choose 'Macintosh HD (external)', log in, and tell Claude."
