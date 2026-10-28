#!/usr/bin/env bash
# 0027 fact (d) (tests/0027-backup-facts.stand-in.sh): what a volume may hold, written into /data by a
# container of the database's image, as root: owners 999 and 70, modes 0700 and 2755, a relative and
# an absolute symbolic link, a hard-link pair, a fifo, an empty directory, names with a space, a
# leading '-' and a newline
set -euo pipefail
cd /data
mkdir pg
echo secret > pg/file
chmod 0600 pg/file
chown -R 999:999 pg
chmod 0700 pg
mkdir shared
echo shared > shared/file
chown -R 70:70 shared
chmod 2755 shared
mkdir empty
ln -s pg/file relative-link
ln -s /etc/passwd absolute-link
echo hard > hard-1
ln hard-1 hard-2
mkfifo fifo
echo space > 'with space'
echo dash > ./-dash
echo newline > "$(printf 'new\nline')"
chown 999:70 /data
chmod 0751 /data
