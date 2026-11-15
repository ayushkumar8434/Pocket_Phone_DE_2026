#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
cd /Users/ayushkumar/Pocket_Phone_DE_2026
date > .push_start.txt
git add -A > .push_log.txt 2>&1
git commit -m "CP1 (Ayush Kumar): gmaps schema + load, ER diagram, problem-understanding & schema-design docs, work division" >> .push_log.txt 2>&1
git push origin main >> .push_log.txt 2>&1
echo "RESULT: $?" >> .push_log.txt
git log --oneline -3 >> .push_log.txt 2>&1
date > .push_done.txt
