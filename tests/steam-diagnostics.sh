#!/bin/bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
testRoot=$(mktemp -d)
sleeper=''
trap '[[ -z "$sleeper" ]] || kill "$sleeper" 2>/dev/null; rm -rf "$testRoot"' EXIT
export HOME="$testRoot/server home" SERVER_BINARY=arma3server_x64
mkdir -p "$HOME/.steam/sdk64" "$HOME/steamcmd/linux64"

bash "$repo/steam-diagnostics.sh" > "$testRoot/diagnostics.log"
grep -q 'Cannot read' "$testRoot/diagnostics.log"
[[ ! -e "$HOME/steam_appid.txt" ]]
echo 'PASS: missing AppID/libraries are informational and no files are created'

printf '107410\r\n' > "$HOME/steam_appid.txt"
printf 'current SteamCMD fixture' > "$HOME/steamcmd/linux64/steamclient.so"
printf 'older SDK fixture' > "$HOME/.steam/sdk64/steamclient.so"
ln -s steamcmd/linux64/steamclient.so "$HOME/steamclient.so"
export SteamAppId=107410
before=$(sha256sum "$HOME/steam_appid.txt" "$HOME/steamclient.so" "$HOME/.steam/sdk64/steamclient.so")
bash "$repo/steam-diagnostics.sh" > "$testRoot/diagnostics.log"
grep -q 'steam_appid.txt=107410' "$testRoot/diagnostics.log"
grep -q 'environment SteamAppId=107410' "$testRoot/diagnostics.log"
[[ $(grep -c 'sha256 ' "$testRoot/diagnostics.log") == 3 ]]
[[ "$before" == "$(sha256sum "$HOME/steam_appid.txt" "$HOME/steamclient.so" "$HOME/.steam/sdk64/steamclient.so")" ]]
[[ -L "$HOME/steamclient.so" && "$SteamAppId" == 107410 ]]
echo 'PASS: AppID, hashes and symlink targets reported without changing files or environment'

printf '233780\n' > "$HOME/steam_appid.txt"
bash "$repo/steam-diagnostics.sh" > "$testRoot/diagnostics.log"
grep -q 'Unexpected runtime AppID' "$testRoot/diagnostics.log"
[[ $(cat "$HOME/steam_appid.txt") == 233780 ]]
export SERVER_BINARY=arma3server
mkdir -p "$HOME/.steam/sdk32" "$HOME/steamcmd/linux32"
bash "$repo/steam-diagnostics.sh" > "$testRoot/diagnostics.log"
grep -q sdk32 "$testRoot/diagnostics.log"
grep -q linux32 "$testRoot/diagnostics.log"
echo 'PASS: unexpected AppID left unchanged and 32-bit diagnostic paths preserved'

status=0
bash "$repo/steam-diagnostics.sh" invalid > "$testRoot/diagnostics.log" 2>&1 || status=$?
[[ $status == 2 ]]
status=0
bash "$repo/steam-diagnostics.sh" 999999999 > "$testRoot/diagnostics.log" 2>&1 || status=$?
[[ $status == 1 ]]

# Load a real shared object under the Steam filename to exercise /proc parsing with spaces.
rm "$HOME/steamclient.so"
cp /usr/lib/x86_64-linux-gnu/libc.so.6 "$HOME/steamclient.so"
ln -s steamclient.so "$HOME/libc.so.6"
LD_LIBRARY_PATH="$HOME" sleep 30 &
sleeper=$!
for ((i=0; i<100; i++)); do
    bash "$repo/steam-diagnostics.sh" "$sleeper" > "$testRoot/diagnostics.log"
    grep -Fxq "$HOME/steamclient.so" "$testRoot/diagnostics.log" && break
    sleep 0.02
done
grep -Fxq "$HOME/steamclient.so" "$testRoot/diagnostics.log"
echo 'PASS: actual mapped library path detected, including paths containing spaces'
/sbin/ifconfig -a > /dev/null
echo 'PASS: /sbin/ifconfig available and works as the container user'
