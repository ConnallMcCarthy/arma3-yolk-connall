# Steam diagnostics testing image

Use `ghcr.io/connallmccarthy/arma3-yolk-connall:testing`.

Every startup prints a `[STEAM_DIAG]` block before launching Arma. It reports:

- The runtime `steam_appid.txt` value and the expected value, `107410`.
- Existing `SteamAppId` and `SteamGameId` environment overrides.
- Resolved paths and SHA-256 hashes for bundled `steamclient.so` / `libsteam_api.so`, local, SDK, and SteamCMD library candidates, selecting 32/64-bit paths from SERVER_BINARY.

The checks do not write files, change environment variables, replace libraries, log in to Steam, or alter startup options. Missing files or diagnostic failures do not block server startup. Candidate paths/hashes alone do not establish which library Arma loaded. Different hashes warrant investigation; they do not establish incompatibility. The supplied live process map shows Arma using `/home/container/linux64/steamclient.so` and `/home/container/linux64/libsteam_api.so`; a stale SDK copy is not established as the cause of those warnings.

An admin shell inside the running container can inspect the libraries actually mapped by an Arma process:

```bash
/steam-diagnostics.sh <Arma PID>
```

Use the PID inside the container. The helper reads `/proc/<PID>/maps` and reports mapped `steamclient.so` / `libsteam_api.so` paths. If the process has exited or access is restricted, it reports that instead. It can also be invoked from the node with `docker exec <container> /steam-diagnostics.sh <Arma PID>`.

`net-tools` is included so `/sbin/ifconfig` is available. Existing libraries, locale configuration, SteamCMD behavior, mod handling, generated parameter files, and server command arguments are retained.

This update collects evidence for the SteamAPI warnings; it does not claim to fix Steam initialization. Successful mission loading has already been observed on the earlier testing image. Actual Steam authentication/browser behavior still requires verification on the real server.

Validation:

```bash
docker build -t arma3-yolk-diagnostics:local .
docker run --rm -v "$PWD:/repo:ro" koalaman/shellcheck:v0.11.0 /repo/entrypoint.sh /repo/steamcmd.sh /repo/steam-diagnostics.sh /repo/tests/startup.sh /repo/tests/steam-diagnostics.sh
docker run --rm -v "$PWD:/repo:ro" arma3-yolk-diagnostics:local bash -c 'bash -n /entrypoint.sh /steamcmd.sh /steam-diagnostics.sh /repo/tests/startup.sh /repo/tests/steam-diagnostics.sh && bash /repo/tests/steam-diagnostics.sh && bash /repo/tests/startup.sh'
```

The diagnostics tests verify read-only behavior, symlink resolution, checksums, unexpected/missing AppIDs, both architecture paths, invalid/exited PIDs, actual mapped-library detection including spaced paths, and unprivileged `ifconfig` execution. Existing startup regressions continue to cover Workshop, HCs, argv boundaries, logging, updates/retries, and exit statuses. Runtime tests use mock Arma/SteamCMD executables.
