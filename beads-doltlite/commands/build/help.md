Build or install DoltLite-linked binaries for Gas City and beads-doltlite.

The default target is `gc`.

Use `gc beads-doltlite build gc --install --no-restart` for normal Gas City
iteration or fresh DoltLite init. By default this installs the latest released
DoltLite-linked Gas City archive for the current platform. The `gc` target uses
the latest released DoltLite-linked `gc` archive unless a release is pinned. Pass
`--build-gc-from-source` only after Gas City source, native read fastpath, or
build-tag changes.

Use `gc beads-doltlite build bd --install --no-restart` to install the pinned
released `bd-doltlite` binary. Pass `--build-bd-from-source` only after the
beads-doltlite source or bd link inputs change.

Use `gc beads-doltlite build client --no-restart` only when refreshing the
DoltLite diagnostic client.

Use `gc beads-doltlite build all --install --no-restart` only for a coordinated
rebuild that includes the optional diagnostic client.

`all` builds `bd`, `doltlite-client`, then `gc`; it does not skip unchanged
targets. Fresh `gc init` installs only the required `bd` and `gc` targets.

The command first looks for an installed `libdoltlite` and then downloads the
pinned DoltLite release library into the pack runtime cache when needed. Pass
`--lib DIR` or set `DOLTLITE_LIB`/`GC_DOLTLITE_LIB` to use a development build.
Likewise, local source checkouts are preferred, but the command can fetch
default Gas City and beads-doltlite sources into the pack runtime cache on a
fresh machine.

The `bd` target defaults to the pinned released `bd-doltlite` binary for the
current platform and verifies it against the release `checksums.txt`. Pass
`--build-bd-from-source`, `--bd-source`, or set `GC_DOLTLITE_BUILD_BD_FROM_SOURCE=1`
when you need a source build.

The `gc` target defaults to the latest non-draft DoltLite workflow release from
`https://github.com/duncan4123/gascity/releases` and verifies the current
platform archive against the Gas City release checksum file. Set
`GC_DOLTLITE_GC_RELEASE_VERSION` to pin a specific release. Pass
`--build-gc-from-source`, `--gc-source`, or set
`GC_DOLTLITE_BUILD_GC_FROM_SOURCE=1` when you need a source build.

Pass `--skip-local-source`, or set `GC_DOLTLITE_SKIP_LOCAL_SOURCE=1`, to skip
automatic local source checkout discovery. Explicit `--gc-source`, `--bd-source`,
or `--source` values still take precedence.

Pass `--skip-local-lib`, or set `GC_DOLTLITE_SKIP_LOCAL_LIB=1`, to skip
automatic local libdoltlite discovery and use the pinned DoltLite release
library. Explicit `--lib`, `DOLTLITE_LIB`, or `GC_DOLTLITE_LIB` values still
take precedence.

With `--install`, the `gc` target updates every distinct home-owned entrypoint
the city may use: the running supervisor binary, the configured supervisor unit
binary, and the active controller `gc` path. Symlinks are resolved before
writing so aliases such as `$HOME/go/bin/gc` keep pointing at the same real
installed binary.

Examples:

```bash
gc beads-doltlite build gc --install --no-restart
gc beads-doltlite build bd --install --no-restart
```
