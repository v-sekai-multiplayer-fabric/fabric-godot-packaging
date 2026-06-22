# fabric-packaging

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
├── fabric-packaging/      # this repo
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

## Quest 3 APK and Windows MSIX

The two `.github/workflows/release-*.yml` legs check out `godot-loop-slice`,
export with the merged editor + double templates pulled from a `godot-images`
release tag (workflow inputs), then publish the APK to a tagged release and pack
the MSIX (`msix/pack.ps1`). The MSIX self-signs a TEST cert unless
`LOOP_PFX_BASE64` / `LOOP_PFX_PASSWORD` secrets are set.

The MSIX assets under `msix/assets/` are placeholders carried from the template —
rebrand before a real Store submission.
