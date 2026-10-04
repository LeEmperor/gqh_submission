# Selected submission rebuild — October 4, 2026

The portable `submission/gowin/build.tcl` was run with **Gowin V1.9.11.03
Education** in a new temporary directory containing only the build script and
the selected RTL, CST, SDC and options. Synthesis and P&R completed successfully.
The saved console output is [rebuild.log](rebuild.log).

- Total Logic: **195**, including 195 mapped LUT / 0 ALU / 0 ROM16.
- Registers: **98** (97 logic FF and 1 I/O FF).
- BSRAM: **4**.
- Supplied image SHA-256:
  `a26f7ec1900b6cde817a8df396610a7a3e58f9b262331652e326bf5f1e892fa0`.
- Rebuilt image SHA-256:
  `03f667c234f1a4994f84146bf364bf5c49f9193969fef4bbc7a7e4c77ef977b2`.

Both files are 7,262,008 bytes. The **only differing line is line 20**, the
`//Created Time:` comment (07:34:06 versus 07:52:51). All programming-data lines
are byte-identical. The supplied, board-tested image remains `bitstream/gqh_serial.fs`.

The input/image/report hashes in [manifest.json](manifest.json) were checked
before packaging. No existing candidate build or board-test output was overwritten.
