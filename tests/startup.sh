#!/bin/bash
# Run inside the built yolk: docker run --rm -v "$PWD:/repo:ro" IMAGE bash /repo/tests/startup.sh
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
testRoot=$(mktemp -d)
trap 'rm -rf "$testRoot"' EXIT
export HOME="$testRoot/server home"
mkdir -p "$HOME"/steamcmd "$HOME"/dta "$HOME"/addons "$HOME"/mpmissions
: > "$HOME/basic.cfg"
: > "$HOME/server.cfg"
: > "$HOME/dta/core.pbo"
: > "$HOME/mpmissions/patrol.altis.pbo"
cat > "$HOME/arma3server_x64" <<'MOCK'
#!/bin/bash
if [[ "$1" == -client || "$1" == -par=startup_params_hc.txt ]]; then
    printf '%s\0' "$@" > "$HOME/hc.argv"
else
    printf '%s\0' "$@" > "$HOME/server.argv"
    pwd -P > "$HOME/server.cwd"
    echo 'fixture server output'
fi
exit "${MOCK_SERVER_EXIT:-0}"
MOCK
cat > "$HOME/steamcmd/steamcmd.sh" <<'MOCK'
#!/bin/bash
printf '%s\0' "$@" > "$HOME/steam.argv"
case "${MOCK_STEAM_MODE:-ok}" in
    fail) exit 42 ;;
    error) echo 'ERROR! App update failed'; exit 0 ;;
    retry)
        if [[ ! -f "$HOME/retried" ]]; then
            touch "$HOME/retried"
            echo 'ERROR! Timeout downloading item'
            exit 1
        fi ;;
esac
echo 'Success! App fully installed.'
MOCK
chmod +x "$HOME/arma3server_x64" "$HOME/steamcmd/steamcmd.sh"
mv "$HOME/dta" "$HOME/core-data"
ln -s core-data "$HOME/dta"
mv "$HOME/arma3server_x64" "$HOME/mock-server"
ln -s mock-server "$HOME/arma3server_x64"
export PARAM_NOLOGS=0 MOD_FILE='' MODIFICATIONS='@123;@mod with spaces;@123;vn;' SERVERMODS='@456;'
export OPTIONALMODS='@789;' UPDATE_SERVER=0 MODS_LOWERCASE=1 HC_NUM=0 HC_HIDE=1
export SERVER_BINARY=arma3server_x64 SERVER_PORT=2302 PARAM_LIMITFPS=50
export PARAM_AUTOINIT=1 PARAM_FILEPATCHING=1 PARAM_LOADMISSIONTOMEMORY=1
export STARTUP='./{{SERVER_BINARY}} -par=startup_params_server.txt "-config=mission configs/custom.cfg" "-profiles=profile dir" -mpmissions=mpmissions'
# shellcheck disable=SC2016 # Exercise literal command substitution in a password.
export SERVER_PASSWORD='a password;$(touch SHOULD_NOT_EXIST)'
export STEAMCMD_ATTEMPTS=2 STEAM_USER=anonymous STEAM_PASS='' STEAMCMD_BETAID='' STEAMCMD_APPID=233780 VALIDATE_SERVER=0
export NSS_WRAPPER_PASSWD="$testRoot/passwd" NSS_WRAPPER_GROUP="$testRoot/group"
: > "$NSS_WRAPPER_GROUP"
fail() { echo "FAIL: $*" >&2; cat "$testRoot/last.log" >&2; exit 1; }
run_entrypoint() {
    local expected=$1 status=0
    bash "$repo/entrypoint.sh" > "$testRoot/last.log" 2>&1 || status=$?
    [[ "$status" == "$expected" ]] || fail "entrypoint status $status, expected $expected"
}
assert_args() {
    local file=$1; shift
    local actual=()
    mapfile -d '' -t actual < "$file"
    [[ ${#actual[@]} == "$#" ]] || fail "argv count ${#actual[@]}, expected $#"
    local arg
    for arg; do
        [[ "${actual[0]}" == "$arg" ]] || fail "argv: ${actual[0]} != $arg"
        actual=("${actual[@]:1}")
    done
}
run_entrypoint 0
assert_args "$HOME/server.argv" -par=startup_params_server.txt '-config=mission configs/custom.cfg' '-profiles=profile dir' -mpmissions=mpmissions
[[ $(cat "$HOME/server.cwd") == "$HOME" ]] || fail 'wrong cwd'
grep -q 'fixture server output' "$HOME"/.local/share/'Arma 3'/rpt/*.rpt || fail 'console log lost'
grep -q -- '-mod=@123;@mod with spaces;vn;' "$HOME/startup_params_server.txt" || fail 'mod list damaged'
grep -q 'core-data/core.pbo' "$testRoot/last.log" || fail 'core symlink resolution missing'
echo 'PASS: par mode, quoted custom paths, cwd, symlinks, mod list, console logging'
export ARMA_DIRECT_ARGS=1 HC_NUM=1
run_entrypoint 0
serverOptions=()
while IFS= read -r arg; do
    [[ -z "$arg" || "$arg" == //* ]] || serverOptions+=("$arg")
done < "$HOME/startup_params_server.txt"
assert_args "$HOME/server.argv" "${serverOptions[@]}" '-config=mission configs/custom.cfg' '-profiles=profile dir' -mpmissions=mpmissions
for ((i=0; i<100; i++)); do
    [[ ! -f "$HOME/hc.argv" ]] || break
    sleep 0.02
done
hcOptions=()
while IFS= read -r arg; do
    [[ -z "$arg" || "$arg" == //* ]] || hcOptions+=("$arg")
done < "$HOME/startup_params_hc.txt"
assert_args "$HOME/hc.argv" "${hcOptions[@]}"
[[ ! -e "$HOME/SHOULD_NOT_EXIST" ]] || fail 'password executed as code'
printf 'Verified direct argv:'
printf ' %q' "./$SERVER_BINARY" "${serverOptions[@]}" '-config=mission configs/custom.cfg' '-profiles=profile dir' -mpmissions=mpmissions
printf '\n'
echo 'PASS: identical generated options in direct argv, including HC password boundaries'
export HC_NUM=0 MOCK_SERVER_EXIT=37
run_entrypoint 37
export PARAM_NOLOGS=1
run_entrypoint 37
export MOCK_SERVER_EXIT=130
run_entrypoint 0
export MOCK_SERVER_EXIT=0 PARAM_NOLOGS=0
# shellcheck disable=SC2016 # Exercise runtime environment expansion.
export STARTUP='./${SERVER_BINARY} -par=startup_params_server.txt "-name=$SERVER_PASSWORD"'
run_entrypoint 0
assert_args "$HOME/server.argv" "${serverOptions[@]}" "-name=$SERVER_PASSWORD"
[[ ! -e "$HOME/SHOULD_NOT_EXIST" ]] || fail 'expanded variable executed as code'
export STARTUP='./{{SERVER_BINARY}} "unterminated'
run_entrypoint 1
export STARTUP=''
run_entrypoint 1
echo 'PASS: server failures with/without tee, SIGINT, literal expansion, invalid/empty STARTUP'
export STARTUP='./{{SERVER_BINARY}} -par=startup_params_server.txt' UPDATE_SERVER=1
for modID in 123 456 789; do
    mkdir -p "$HOME/steamapps/workshop/content/107410/$modID/Addons" "$HOME/steamapps/workshop/content/107410/$modID/keys"
    : > "$HOME/steamapps/workshop/content/107410/$modID/Addons/Some File.PBO"
    : > "$HOME/steamapps/workshop/content/107410/$modID/keys/test.bikey"
done
run_entrypoint 0
assert_args "$HOME/steam.argv" +force_install_dir "$HOME" +login anonymous '' '' +runscript "$HOME/steamcmd/runscript.txt"
grep -q 'app_update 233780 -beta public' "$HOME/steamcmd/runscript.txt" || fail 'empty branch did not select public'
for modID in 123 456 789; do
    grep -q "workshop_download_item 107410 $modID" "$HOME/steamcmd/runscript.txt" || fail 'workshop option shifted'
    [[ -f "$HOME/@$modID/addons/some file.pbo" ]] || fail 'lowercasing/linking damaged spaced file'
    [[ "$HOME/@$modID/addons/some file.pbo" -ef "$HOME/steamapps/workshop/content/107410/$modID/Addons/Some File.PBO" ]] || fail 'hardlink lost'
done
[[ -f "$HOME/keys/test.bikey" ]] || fail 'keys not copied'
echo 'PASS: empty Steam arguments, explicit public, workshop IDs/keys/hardlinks/lowercasing'
export MODIFICATIONS='' SERVERMODS='' OPTIONALMODS=''
run_entrypoint 0
if grep -q workshop_download_item "$HOME/steamcmd/runscript.txt"; then fail 'invented empty workshop ID'; fi
export STEAMCMD_BETAID=profiling
run_entrypoint 0
grep -q 'app_update 233780 -beta profiling' "$HOME/steamcmd/runscript.txt" || fail 'profiling branch lost'
export MOCK_STEAM_MODE=retry
run_entrypoint 0
grep -q 'Timeout downloading item' "$HOME/steamcmd/steamcmd.log" || fail 'retry history lost'
grep -q 'Success! App fully installed' "$HOME/steamcmd/steamcmd.log" || fail 'retry success lost'
export MOCK_STEAM_MODE=fail
rm "$HOME/server.argv"
run_entrypoint 42
[[ ! -e "$HOME/server.argv" ]] || fail 'launched after failed update'
export MOCK_STEAM_MODE=error
run_entrypoint 1
export MOCK_STEAM_MODE=ok STEAMCMD_ATTEMPTS=0
run_entrypoint 1
status=0
timeout 5 bash /steamcmd.sh --beta-id > "$testRoot/last.log" 2>&1 || status=$?
[[ $status == 1 ]] || fail "missing option value status $status"
echo 'PASS: profiling selection, retry recovery, update failures, zero attempts, missing values'
echo 'All startup regression checks passed (mock Arma/SteamCMD, real Linux entrypoint).'
