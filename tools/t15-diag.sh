#!/bin/bash
# Run on the T14. Logs in to the T15 macOS once with your password and keeps that login open
# for 4 hours (socket tools/t15-cm.sock), so Claude can run read-only checks without asking
# you for the password again. Close it any time with:  ssh -S tools/t15-cm.sock -O exit x
cd "$(dirname "$0")"
OPTS=(-o UserKnownHostsFile=~/.ssh/known_hosts_t15mac -o ControlMaster=auto -o ControlPath="$PWD/t15-cm.sock" -o ControlPersist=4h)
ssh "${OPTS[@]}" manojb@192.168.1.17 '
echo "== macOS"; sw_vers
echo "== SIP"; csrutil status
echo "== Users flags"; ls -ldO /Users /System/Volumes/Data/Users; ls -laO /System/Volumes/Data/Users
echo "== mounts"; mount
echo "== write test in /Users/Shared"; touch /Users/Shared/.t && echo shared-writable && rm /Users/Shared/.t
echo "== loginwindow / home errors (last 2h)"
log show --last 2h --style compact --predicate "process == \"loginwindow\" OR process == \"opendirectoryd\" OR process == \"createhomedir\" OR eventMessage CONTAINS[c] \"home dir\"" 2>&1 | grep -iE "home|error|fail|denied|permit" | tail -60
' 2>&1 | tee t15-diag.log
echo; echo "Finished - tell Claude. (Press Enter to close)"; read
