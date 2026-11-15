#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
cd /Users/ayushkumar/Pocket_Phone_DE_2026
git add -A
git commit -m "CP1 (Ayush Kumar): gmaps schema + load, ER diagram, problem-understanding & schema-design docs, work division"
git push origin main
git log --oneline -3
echo "PUSH_DONE"
