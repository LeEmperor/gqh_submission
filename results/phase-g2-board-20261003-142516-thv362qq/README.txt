Prepared for UART port /dev/ttyUSB1. Requires Python 3 and pyserial.
Reset the board before each test. Run run-quick.sh, then run-robust.sh.
Require quick PASS; robust 84/84 packets, 168/168 actions, zero timeouts.
Exit status alone does not prove PASS. Each launcher overwrites its console.log;
prepare a fresh directory for a retry to preserve prior evidence.
Archive the programmed .fs, its hash, and Gowin reports with this run.
