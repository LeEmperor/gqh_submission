# Isolated H2–H5 verification toolchain

The optimization run restored missing HDL prerequisites beneath
`/tmp/gqh-hopt-toolchain`, without system installation or OCaml upgrades.
`hopt-toolchain.json` records the exact package/source hashes, URLs, Yosys
configuration, and OCaml package repair identity. The measured versions are
Icarus 12.0-3 and Yosys 0.33 (tag `yosys-0.33`, source identity `2584903a060`).
The existing compiler was GCC 15.2.0-16ubuntu1; these Ubuntu packages require
a compatible x86_64 Linux runtime and are not portable Windows binaries.

To reproduce from the preserved download cache in a fresh directory:

```sh
python3 tools/prepare_hopt_toolchain.py \
  --root /tmp/gqh-hopt-toolchain-rebuilt \
  --from-downloads /tmp/gqh-hopt-toolchain/downloads --jobs 4
source /tmp/gqh-hopt-toolchain-rebuilt/env.sh
yosys -V
iverilog -V
vvp -V
```

Alternatively replace `--from-downloads PATH` with `--download` to fetch the
exact archived inputs. Network access needs the execution environment's
approval. The script verifies all SHA-256 values before extraction/building.
It uses `dpkg-deb -x` into the isolated root, not `apt install` or `dpkg -i`.
Existing directories are rejected to preserve previous builds. The toolchain
root must have no spaces because Yosys Makefile include paths are unquoted.

Required existing host tools are Python 3.12+, GCC/G++, make, and dpkg-deb.
The additional packages are flex 2.6.4-8.2build2, bison
2:3.8.2+dfsg-1ubuntu0.26.04.1, libffi-dev 3.5.2-4, pytest 9.0.2-4,
pluggy 1.6.0-2, iniconfig 2.1.0-2, pygments 2.19.2+dfsg-1, and packaging 26.0-1.
Their exact package SHA-256 values and archive paths are in the JSON manifest.

The Icarus wrapper supplies `-B ROOT/usr-root/usr/lib/x86_64-linux-gnu/ivl`;
otherwise the extracted driver searches the system installation for its
preprocessor/compiler. The environment also sets `BISON_PKGDATADIR` to the
extracted grammar skeletons and extends `PYTHONPATH` for the isolated pytest
packages. It leaves ordinary host tools available later on `PATH`.

Yosys is built with the following settings (ROOT is the isolated directory):

```make
CONFIG := gcc
ENABLE_TCL := 0
ENABLE_READLINE := 0
ENABLE_ZLIB := 0
ENABLE_ABC := 0
PREFIX := ROOT/install
CXXFLAGS += -include cstdint
CXXFLAGS += -IROOT/usr-root/usr/include/x86_64-linux-gnu
LDFLAGS += -LROOT/usr-root/usr/lib/x86_64-linux-gnu
```

The explicit `cstdint` inclusion accommodates GCC 15's header behavior when
building the older Yosys release. libffi supports the compiled DPI frontend.
ABC, Tcl, readline and zlib are disabled. This build supports the regression
flow's Verilog parsing, hierarchy/proc/check, statistics and SAT checks; it does
not support ABC technology mapping, Tcl scripts, readline interaction or gzip
I/O. Local Yosys statistics do not establish Gowin counts/timing. An ABC source
archive was downloaded during setup but is unused, as recorded in the evidence.

Do not use this 0.33 build to generate the competition FPGA image. The mapping
audit reproduced an 18-bit SPX9 address-packing defect in that version with a
failing poisoned-history negative control. The pinned newer
[open-source build suite](../gowin/OPEN_SOURCE_AUTOMATION.md) retains all five
logical RAM address bits and passes the mapped-engine checks. This does not
affect the older tool's parsing, structural checks, or combinational SAT lemmas.

The existing OCaml switch remains `5.2.0+ox`. A missing `ppx_hardcaml` package
was restored at the same version as installed Hardcaml:

```sh
opam install --switch=5.2.0+ox 'ppx_hardcaml.v0.18~preview.130.106+341'
opam list --switch=5.2.0+ox --installed --columns=name,version hardcaml ppx_hardcaml dune
opam exec --switch=5.2.0+ox -- dune build
```

The package metadata resolves to commit
`c0459d9433a88419e67c40af6abc17ec2309b2cf`, source SHA-256
`771f79e15d77644e121853e7678900ff7977e3e9827db504b147a93004ecc6fc`.
Installed Hardcaml and ppx_hardcaml are both
`v0.18~preview.130.106+341`, and Dune is 3.24.2. Do not upgrade the switch to
resolve this prerequisite. The reproduction script deliberately does not
invoke opam or mutate an existing switch.

The setup script completed an independent offline rebuild in
`/tmp/gqh-hopt-toolchain-rebuilt`. Both tool versions match the manual setup;
the rebuilt environment also passed all 62 host-runner tests and all 19 Gowin
runner tests. The compiler log and exact inputs remain in that directory.
