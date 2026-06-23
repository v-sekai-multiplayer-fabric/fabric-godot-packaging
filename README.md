# fabric-godot-packaging

Native packaging for the multiplayer-fabric stack, modelled on
[`sinew-mocap/packaging`](https://github.com/sinew-mocap/packaging): a relocatable
`/opt/org.v-sekai` tree wrapped by nFPM into `.deb`/`.rpm`, plus a Quest 3 APK
release and a Windows MSIX leg.

It currently packages the loot-action **loop-slice**
([`godot-loop-slice`](https://github.com/v-sekai-multiplayer-fabric/godot-loop-slice));
more fabric products can be added alongside as the suite grows.

This repo holds only the packaging recipe — the game source lives in
`godot-loop-slice`. Clone it **beside** this repo (the default `stage.sh` reads
`../godot-loop-slice`; override with `LOOP_SRC`):

```
loot-action-vertical-slice/
├── fabric-godot-packaging/      # this repo
└── godot-loop-slice/      # the game it packages
```

## Layout on disk (what a package installs)

```
/opt/org.v-sekai/loop-slice/0.1/
├── bin/
│   ├── loop-slice.x86_64        # exported Godot game (double build)
│   ├── loop-slice.pck           # game data (auto-mounted beside the binary)
│   ├── loop-slice               # client launcher
│   └── loop-slice-server        # headless authority launcher
└── share/loop-slice/server_host.txt
```

System integration (added by the package, not under `/opt`): PATH symlinks for
`loop-slice` / `loop-slice-server`, the `loop-slice-server.service` unit
(installed disabled), `/etc/default/loop-slice-server` (`LOOP_HOST`/`LOOP_PORT`,
not overwritten on upgrade), and a desktop entry.

## Build the Linux packages

nFPM writes the archives natively — no dpkg/rpmbuild needed.

```sh
# GODOT must be the merged double-precision editor that owns the matching
# double export templates (from v-sekai-multiplayer-fabric/godot-images).
GODOT=godot.linuxbsd.editor.double.x86_64 ./build.sh
# -> dist/v-sekai-loop-slice_0.1.0_amd64.deb
#    dist/v-sekai-loop-slice-0.1.0.x86_64.rpm
```

`stage.sh` exports the `Linux/X11` preset from `../godot-loop-slice` and lays out
the `/opt` tree; `build.sh` runs it and then `nfpm pkg` for deb + rpm. Override
the version with `LOOP_PKG_VERSION` and the channel dir with `LOOP_VER`.

## Host a server

```sh
sudo systemctl enable --now loop-slice-server      # binds LOOP_HOST:LOOP_PORT
sudoedit /etc/default/loop-slice-server            # then: systemctl restart loop-slice-server
```

## Host a server via Podman quadlet (no native engine on the host)

A second, independent package runs the dedicated server as a **Podman quadlet**
on the published `zone-godot-runtime` image — there's no Godot binary on the
host, only the exported `.pck`. It ships `v-sekai-loop-slice-server-quadlet`
(`.deb`/`.rpm`), which installs:

```
/usr/share/loop-slice/loop-slice.pck                       # exported game data, bind-mounted :ro into the container
/usr/share/containers/systemd/loop-slice-server.container  # the quadlet; daemon-reload generates loop-slice-server.service
/etc/default/loop-slice-server                             # LOOP_HOST/LOOP_PORT (config|noreplace)
```

> **Note:** `server.gd` reads `LOOP_HOST`/`LOOP_PORT` (default `0.0.0.0:54400`,
> ENet/UDP). To change the port, edit `LOOP_PORT` in `/etc/default/loop-slice-server`
> **and** the quadlet's `PublishPort=` (a quadlet can't read the env at unit-generate
> time), then `systemctl daemon-reload && systemctl restart loop-slice-server`.

This package and the native `v-sekai-loop-slice` both provide a
`loop-slice-server.service` and own `/etc/default/loop-slice-server`, so they
declare a mutual `Conflicts:` — install **one** way to host, not both.

```sh
# GODOT must be the merged double-precision editor (as above). The quadlet needs
# ONLY the .pck, so stage.sh exports it template-free with --export-pack.
GODOT=godot.linuxbsd.editor.double.x86_64 ./build-quadlet.sh
# -> dist/v-sekai-loop-slice-server-quadlet_0.1.0_amd64.deb
#    dist/v-sekai-loop-slice-server-quadlet-0.1.0-1.x86_64.rpm
```

`build-quadlet.sh` first runs `bin/pin-runtime-digest.sh`, which rewrites the
quadlet's `Image=` to an **immutable digest** (`:latest` is blocklisted —
resolved from `$RUNTIME_DIGEST`, then `skopeo`, then the latest `godot-images`
build log). Then `stage.sh` with `PCK_ONLY=1` exports just the `.pck`, and nFPM
wraps the `.deb`/`.rpm`. After install:

```sh
sudo systemctl daemon-reload                       # generate the unit from the quadlet
sudo systemctl enable --now loop-slice-server      # pulls the image, binds 0.0.0.0:54400/udp
```

The `release-quadlet.yml` workflow does the same on CI, taking the
`runtime_digest` to pin as a required `workflow_dispatch` input, then runs
`test/server_up_test.sh` to **boot the server on the runtime image and wait for
its `LOOPSRV ready` log** before publishing.

## Tests

```sh
./test/packaging_test.sh    # fast static checks: env-file path, digest pin,
                            # mutual Conflicts:, server.gd launch + bound port
./test/server_up_test.sh    # integration: actually boot the server on the runtime
                            # image and wait for "LOOPSRV ready" (soft-skips if the
                            # image can't be pulled; LOOP_REQUIRE_SERVER_UP=1 enforces)
```

## Quest 3 APK and Windows MSIX

The two `.github/workflows/release-*.yml` legs check out `godot-loop-slice`,
export with the merged editor + double templates pulled from a `godot-images`
release tag (workflow inputs), then publish the APK to a tagged release and pack
the MSIX (`msix/pack.ps1`). The MSIX self-signs a TEST cert unless
`LOOP_PFX_BASE64` / `LOOP_PFX_PASSWORD` secrets are set.

The MSIX assets under `msix/assets/` are placeholders carried from the template —
rebrand before a real Store submission.
