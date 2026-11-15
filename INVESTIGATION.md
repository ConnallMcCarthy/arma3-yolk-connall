# Arma 3 startup investigation — 15 November 2026

Status: verified yolk defects fixed; the reported mission/core-data failure is **not yet reproduced or resolved**. No Arma executable, game data, server.cfg, affected RPT, actual panel environment, or affected container is present in this repository. Tests use mock game and update executables inside the real Linux image. No game reinstall or mod removal was performed.

## Upstream evidence

Queried Valve directly using a fresh SteamCMD in a disposable container, with anonymous login and `+app_info_update 1 +app_info_print 233780 +quit`. This downloads SteamCMD itself, not Arma. Returned dedicated-server branch metadata:

| Branch | Build ID | timeupdated (Unix) | Updated UTC |
| --- | --- | --- | --- |
| public | 25600558 | 1790774085 | 2026-09-30 13:14:45 |
| profiling | 26641393 | 1794564934 | 2026-11-13 10:15:34 |

Thus a recent profiling build is confirmed. The public branch's current metadata does not show a November weekend build. That does not establish which build was actually installed on the affected server. In particular, the old wrapper did not explicitly select public after using another branch. The installed appmanifest and RPT executable version must be checked before treating the branch tests as a comparison of different binaries.

[Official SPOTREP #00122](https://dev.arma3.com/post/spotrep-00122) describes the September 30 public mini-update. Its listed changes do not identify a Linux `-par` or core-data regression. [Bohemia's profiling page](https://dev.arma3.com/profiling-branch) describes experimental builds; switching branches is not evidence of a fix. Searches of official release pages, forums, and the feedback tracker did not locate a confirmed November regression matching these symptoms. This is a search result limitation, not proof that no regression exists.

[Bohemia's known-issues page](https://dev.arma3.com/known-issues) mentions incorrect installation selection for add-ons and steam_appid.txt. Neither is demonstrated here. No engine paths or official mod lists were changed on that basis.

## Complete startup trace

1. `.github/workflows/docker-publish.yml` builds/publishes this Dockerfile. The base is mutable `debian:trixie-slim`; `apt-get update/upgrade` and unpinned packages mean rebuilding can change libraries even without a source change. No installed image digest or host Docker/Wings version was provided, so a runtime/container change cannot be ruled in or out.
2. `Dockerfile:51` creates `/home/container`; HOME and WORKDIR point there. Tini starts `/entrypoint.sh` and forwards group signals; Docker stop signal is SIGINT. SteamCMD/game installation is supplied by the egg/server volume, not baked into this yolk.
3. `entrypoint.sh` changes to HOME. It combines manual mods and the Launcher HTML export, deduplicates using the existing sorted order, collects Workshop IDs from client/server/optional lists, and optionally runs `/steamcmd.sh`.
4. The wrapper writes `$HOME/steamcmd/runscript.txt`, invokes `$HOME/steamcmd/steamcmd.sh` with force_install_dir before login, updates STEAMCMD_APPID and Workshop app 107410, logs output, and retries recoverable errors.
5. The entrypoint copies keys and makes hardlink copies from `$HOME/steamapps/workshop/content/107410/<id>` into `@<id>`. With MODS_LOWERCASE=1, copied names are lowercased. These are hardlinks, not symlinks; renaming copied paths does not rename Steam's source paths, although writing file contents affects both links.
6. It checks SERVER_BINARY, prepares console logging and basic.cfg, installs the NSS wrapper environment, and writes both generated parameter files.
7. `startup_params_server.txt` contains one option per line, with a `//` comment header and blank lines for disabled flags. It carries `-name`, `-ip`, `-port`, `-cfg`, `-config`, `-mod`, `-serverMod`, the existing toggle flags, and `-limitFPS`. The HC file carries its existing client/connect/password/mod options. Optional-only mods remain absent from the server's `-mod` list.
8. The [upstream egg](https://raw.githubusercontent.com/pelican-eggs/games-steamcmd/main/arma/arma3/egg-arma3.json) uses `./{{SERVER_BINARY}} -par=startup_params_server.txt`. This repository contains no egg export, so the affected panel's actual STARTUP and extra options are unknown.
9. The new launcher parses STARTUP quotes into argv without eval, then expands `{{VAR}}`, `${VAR}`, or `$VAR` literally within each argument. In default mode it executes the generated `-par` argument. With ARMA_DIRECT_ARGS=1 it replaces that exact generated server token with an array containing the same non-comment, non-empty generated lines. Other arguments and other parameter files are retained. HCs use the same transport selection. The generated files remain available in both modes.

## Verified bugs and exact responsibility

Original line numbers refer to HEAD `3be0e67` before this patch.

| Original source | Evidence / consequence | Fix |
| --- | --- | --- |
| entrypoint.sh:264–273 | Empty unquoted STEAMCMD_BETAID disappears: `--beta-id --add-redist 0`; wrapper consumes `--add-redist` as the branch and exits with `Unknown argument: 0`. Empty passwords and whitespace have the same boundary problem. | Quote every scalar option; pass Workshop IDs as an array. |
| entrypoint.sh:264–273, then 345 onward | Wrapper failure was ignored; startup and mod linking continued after an incomplete update. | Stop and propagate the wrapper status. |
| entrypoint.sh:483, 491, 493 | `eval echo` consumes quotes, followed by unquoted string execution. The original code demonstrably passes a quoted config path as two arguments. | Parse quotes once; expand environment values as literal data; execute an array. |
| entrypoint.sh:485–489 | Printed command substituted the file contents for `-par`, but executed `-par` unchanged. | Log actual shell-escaped argv, generated options, cwd, and resolved readable paths separately. |
| entrypoint.sh:493–500 | Mock Arma exiting 37 through tee produced entrypoint exit 0. | Capture PIPESTATUS immediately and preserve Arma's status; also detect logging failures. |
| steamcmd.sh:63–128 | A terminal option with no value can fail shift without reducing argument count and loop indefinitely. | Reject a missing value before consuming the option. |
| steamcmd.sh:201–277 | Zero attempts skipped Steam entirely and reported success, reproduced with no Steam binary installed. | Require a positive integer. |
| steamcmd.sh:163–173 | Empty branch formed an incomplete `-beta`; public did not explicitly select a branch when returning from a beta. | Normalize empty to public and emit `-beta public` explicitly. Actual branch-switch installation still needs live verification. |
| steamcmd.sh:212–220 | Appending every retry to one file, then inspecting the entire file, let earlier transient errors poison later successful attempts. | Preserve the full log while classifying only the current attempt; check tee status. |
| entrypoint.sh:185–187, 235–236; 175–181 | Mod deduplication and lowercase traversal split whitespace. | Preserve semicolon-separated entries and use NUL-delimited traversal. Existing sorted load order is preserved. |
| entrypoint.sh:412 | Used BASIC_URL while the documented egg variable is BASIC_CFG_URL; failed downloads were ignored. | Prefer BASIC_CFG_URL, retain BASIC_URL fallback, fail on HTTP/download errors. |

The untouched original launch block was run in a disposable Linux container. It produced:

```text
legacy argv: <-par=startup_params_server.txt> <-config=mission> <configs/custom.cfg>
legacy entrypoint exit status after server exit 37: 0
Unknown argument: 0
legacy wrapper status after empty unquoted branch: 1
legacy wrapper status with zero attempts and no Steam binary: 0
```

These prove launcher/update bugs. They do **not** prove the cause of the reported November game failure, especially if the real STARTUP has no spaced values and all update options are populated.

## Paths, missions, and interpreting dta/core

HOME is both the wrapper's default install directory and the entrypoint's cwd. The child SteamCMD script cannot change its parent's cwd. There is no demonstrated cwd change in this repository. The patch logs the actual physical binary/core/config paths instead of adding a speculative chdir or rewriting configured paths.

`-cfg=basic.cfg` and `-config=server.cfg` are relative to the launch context; configured overrides remain in their original argument order. This code does not generate `-profiles` or `-mpmissions`. Custom instances are preserved. No profile path is added: [Bohemia's startup-parameter documentation](https://community.bistudio.com/wiki/Arma_3:_Startup_Parameters) notes Linux limitations for `-profiles` and describes the alternative mission-directory option. The actual server.cfg mission template, mission PBO names, selected terrain, and their capitalization are unavailable for inspection.

Linux path case and resolved symlink targets still matter even when the expected files exist. The image tests include a symlinked core directory and binary, spaced HOME/config/profile/mod paths, lowercase Workshop copying, and an existing mission PBO. They prove the launcher's behavior, not engine mission discovery or PBO parsing.

[Bohemia documents](https://community.bistudio.com/wiki/Startup_Parameters_Config_File) `.txt` as the plain-text format, one option per line, and preprocessing before parsing. The generated filename has that extension. `-par` is therefore not demonstrably invalid here. Some low-level options cannot be initialized from parameter files; keep custom cpu/memory/profile options on the direct STARTUP command where intended. Direct mode bypasses the generated file's preprocessing, so punctuation/comment-sensitive values are one reason to compare it against actual engine behavior.

A verbose `dta/core` failure without `.pbo` is insufficient to classify core loading. It may be a failed loose-directory probe preceding a successful archive open. An existing, readable core.pbo is likewise insufficient to prove the engine accepted its contents. To distinguish them, correlate the same process's file trace with its `Loaded addons` section. A failed extensionless probe followed by successful core.pbo access **and a loaded-addon entry** is evidence of a harmless probe. A fatal core load failure or absent loaded entry requires investigation of that process's root/cwd, resolved archive, and full RPT. No affected trace/RPT was supplied, so this warning cannot honestly be classified yet.

SteamCMD's real bootstrap and anonymous metadata query succeeded in the built image. This establishes basic client/library/network compatibility here, not authenticated Workshop downloads or live game compatibility. Nothing in the supplied evidence establishes a Docker, Wings, Pterodactyl, or mod-loading upstream change as the incident cause.

## Validation

- `bash -n entrypoint.sh steamcmd.sh tests/startup.sh`: passed inside Linux.
- ShellCheck v0.11.0 on all three scripts: passed with no findings.
- `docker build -t arma3-yolk-investigation:local .`: passed on linux/amd64. Docker's NSS_WRAPPER_PASSWD secret-name heuristic warns about a passwd-file *path*, not a stored password.
- `tests/startup.sh`: passed inside the built image as the container user with real NSS wrapper setup and mocked Arma/SteamCMD. Checks both parameter transports, exact argument boundaries/order, HC password, custom config/profile/mission paths, environment expansion without code execution, symlinks/cwd, console log output, both logging modes' exit codes, SIGINT, malformed STARTUP, empty Steam credentials/branch/mod lists, public/profiling runscript selection, Workshop IDs/keys/hardlinks/lowercasing, retry recovery with full history, failed updates, invalid retry counts, and missing option values.
- Before/after reproduction above uses untouched HEAD scripts for the baseline.
- `git diff --check`: passed.

Repeat locally (Linux shell):

```bash
docker build -t arma3-yolk-investigation:local .
docker run --rm -v "$PWD:/repo:ro" koalaman/shellcheck:v0.11.0 /repo/entrypoint.sh /repo/steamcmd.sh /repo/tests/startup.sh
docker run --rm -v "$PWD:/repo:ro" arma3-yolk-investigation:local bash -c 'bash -n /repo/entrypoint.sh /repo/steamcmd.sh /repo/tests/startup.sh && bash /repo/tests/startup.sh'
git diff -- entrypoint.sh steamcmd.sh
```

## Required real-server comparison

1. Build/deploy the revised yolk normally and confirm the container uses that image digest. This investigation did not deploy to a live server. Preserve all mods, mission files, and server.cfg.
2. Record the installed `steamapps/appmanifest_233780.acf` buildid and branch metadata, RPT version/executable name, and new startup diagnostics. STEAMCMD_BETAID alone does not prove what binary ran.
3. After ensuring the update is complete, do two otherwise identical starts against the **same installed binary and files**, with PARAM_NOLOGS=0. Use UPDATE_SERVER=0 during this comparison so the executable and mods cannot change between runs. Restore its previous value afterwards.
4. First use ARMA_DIRECT_ARGS=0 (or leave unset); then ARMA_DIRECT_ARGS=1. Expose this optional environment variable through the panel's egg/admin configuration. Keep STARTUP's generated token `-par=startup_params_server.txt` exactly; the entrypoint replaces that token in direct mode. Custom parameter files are deliberately not flattened. Do not start a second server concurrently on the same ports.
5. Compare loaded addons, mission selection/initialization, and actual process status, in addition to Host identity created. If direct alone succeeds, that demonstrates a generated-parameter transport compatibility issue for that installed build/configuration; keep direct mode as the workaround and retain both RPTs. It does not by itself identify the engine source-code change.
6. If both fail, do not conclude `-par` caused it. Inspect `/proc/<arma-pid>/cwd`, `/proc/<arma-pid>/exe`, `/proc/<arma-pid>/root`, and the NUL-separated cmdline. If necessary, trace startup file operations (`strace -ff -e trace=%file`) from before exec on the real host/container, preserving the same cwd/argv/environment. strace is not installed in the production image by this patch. Check core archive access and the exact mission path/case selected by the configuration.

Remaining limitations: no actual Arma startup, mission load, client connection, authenticated Workshop download, or live Wings/container integration was tested. The reported incident remains open until those observations establish a cause and successful mission load.
