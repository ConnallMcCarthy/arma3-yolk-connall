#!/bin/bash
# Read-only checks; optionally pass an Arma PID to show its actual loaded Steam libraries.
if (( $# > 1 )) || [[ $# == 1 && ! "$1" =~ ^[1-9][0-9]*$ ]]; then
    echo 'Usage: /steam-diagnostics.sh [Arma PID]' >&2
    exit 2
fi

printf '[STEAM_DIAG]: expected runtime AppID=107410 (server install AppID=233780)\n'
appidFile="${HOME}/steam_appid.txt"
if [[ -f "$appidFile" && -r "$appidFile" ]]; then
    appid=$(head -c 64 -- "$appidFile" | tr -d '\r\n')
    printf '[STEAM_DIAG]: steam_appid.txt=%q\n' "$appid"
    [[ "$appid" == 107410 ]] || echo '[STEAM_DIAG_WARN]: Unexpected runtime AppID; file left unchanged.'
else
    printf '[STEAM_DIAG_WARN]: Cannot read %q; continuing without changing it.\n' "$appidFile"
fi
for variable in SteamAppId SteamGameId; do
    [[ ! -v "$variable" ]] || printf '[STEAM_DIAG]: environment %s=%q\n' "$variable" "${!variable}"
done

sdk=sdk64
platform=linux64
if [[ "${SERVER_BINARY:-arma3server_x64}" != *x64* ]]; then
    sdk=sdk32
    platform=linux32
fi
for library in "${HOME}/steamclient.so" "${HOME}/.steam/${sdk}/steamclient.so" "${HOME}/steamcmd/${platform}/steamclient.so"; do
    if [[ -f "$library" && -r "$library" ]]; then
        printf '[STEAM_DIAG]: library %q -> %q\n' "$library" "$(readlink -f -- "$library")"
        printf '[STEAM_DIAG]: sha256 '
        sha256sum -- "$library"
    else
        printf '[STEAM_DIAG]: library candidate unavailable: %q\n' "$library"
    fi
done

if (( $# == 1 )); then
    maps="/proc/$1/maps"
    if [[ ! -r "$maps" ]]; then
        printf '[STEAM_DIAG_WARN]: Cannot read %q; process may have exited or access is restricted.\n' "$maps" >&2
        exit 1
    fi
    printf '[STEAM_DIAG]: process %s executable=%q\n' "$1" "$(readlink -- "/proc/$1/exe")"
    loaded=$(sed -nE 's@^[^/]*(/.*(steamclient|libsteam_api)\.so( \(deleted\))?)$@\1@p' "$maps" | sort -u)
    if [[ -n "$loaded" ]]; then
        printf '[STEAM_DIAG]: mapped Steam libraries:\n%s\n' "$loaded"
    else
        echo '[STEAM_DIAG]: No Steam libraries matched in this process snapshot.'
    fi
else
    echo '[STEAM_DIAG]: Candidate paths do not identify the loaded library; inspect a running server with /steam-diagnostics.sh <Arma PID>.'
fi
