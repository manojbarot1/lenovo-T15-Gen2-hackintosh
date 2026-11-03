#!/bin/bash
# Run on the T14: logs in to the T15 macOS with your password (asked twice: ssh, then sudo),
# creates /Users/manojb if missing, and installs Claude's key. Output is saved to t15-home.log.
cd "$(dirname "$0")"
KEY=$(cat ~/.ssh/id_t15.pub)
ssh -t -o UserKnownHostsFile=~/.ssh/known_hosts_t15mac manojb@192.168.1.17 "
echo '== who'; id; groups
echo '== account record'; dscl . -read /Users/manojb NFSHomeDirectory UniqueID PrimaryGroupID
echo '== /Users'; ls -la /Users
echo '== sudo check (type your macOS password if asked)'; sudo -v || { echo SUDO-FAILED; exit 1; }
if [ ! -d /Users/manojb ]; then
  echo '== createhomedir'; sudo createhomedir -c -u manojb
fi
if [ ! -d /Users/manojb ]; then
  echo '== fallback: copy User Template'
  sudo mkdir -p /Users/manojb && sudo ditto '/System/Library/User Template/Non_localized' /Users/manojb
  sudo chown -R manojb:staff /Users/manojb
fi
echo '== key'
sudo mkdir -p /Users/manojb/.ssh
echo '$KEY' | sudo tee -a /Users/manojb/.ssh/authorized_keys >/dev/null
sudo chown -R manojb:staff /Users/manojb/.ssh
sudo chmod 700 /Users/manojb/.ssh; sudo chmod 600 /Users/manojb/.ssh/authorized_keys
ls -la /Users/manojb /Users/manojb/.ssh && echo KEY-INSTALLED
" 2>&1 | tee t15-home.log
echo; echo "Finished - tell Claude. (Press Enter to close)"; read
