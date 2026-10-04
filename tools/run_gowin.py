#!/usr/bin/env python3
"""Run one immutable whole-design Gowin build from WSL, retaining all evidence.

Windows invocation/staging requires the execution environment's escalation.
No programming, synthesis caching, or cleanup of historical artifacts occurs.
"""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import hashlib
import html
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import uuid


ROOT = Path(__file__).resolve().parents[1]
POWERSHELL = Path('/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe')
DEFAULT_TOOL = Path('/mnt/c/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe')


class BuildError(RuntimeError):
    pass


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def ps_quote(value):
    return "'" + str(value).replace("'", "''") + "'"


def tcl_quote(value):
    # Quoted Tcl words: protect substitutions, quotes, backslashes and newlines.
    value = str(value).replace('\\', '\\\\').replace('$', '\\$')
    value = value.replace('[', '\\[').replace(']', '\\]').replace('"', '\\"')
    return '"' + value.replace('\n', '\\n').replace('\r', '\\r') + '"'


def ps_command(script):
    return [str(POWERSHELL), '-NoProfile', '-NonInteractive', '-Command', script]


def windows_path(path):
    path = Path(path).resolve()
    if str(path).startswith('/mnt/') and len(path.parts) > 3:
        return path.parts[2].upper() + ':/' + '/'.join(path.parts[3:])
    return subprocess.check_output(['wslpath', '-w', str(path)], text=True).strip()


def local_path(path):
    match = re.fullmatch(r'([A-Za-z]):[\\/](.*)', path.strip())
    if not match:
        raise BuildError(f'Expected Windows-native temporary path, got {path!r}')
    return Path('/mnt') / match[1].lower() / match[2].replace('\\', '/')


def plain(value):
    value = re.sub(r'<[^>]*>', ' ', value)
    # Gowin emits some malformed &nbsp without semicolons.
    return ' '.join(html.unescape(value.replace('&nbsp', ' ')).split())


def rows(value):
    return [[plain(cell) for cell in re.findall(r'<t[dh]\b[^>]*>(.*?)</t[dh]>', row, re.S | re.I)]
            for row in re.findall(r'<tr\b[^>]*>(.*?)</tr>', value, re.S | re.I)]


def unique_count(value, label):
    matches = re.findall(r'^\s*' + re.escape(label) + r'\s*\|\s*(\d+)(?:/\d+)?\s*\|', value, re.M)
    if len(matches) != 1:
        raise BuildError(f'Missing, malformed, or ambiguous resource count: {label}')
    return int(matches[0])


def parse_reports(directory):
    directory = Path(directory)
    def one(pattern):
        paths = list(directory.glob(pattern))
        if len(paths) != 1:
            raise BuildError(f'Expected exactly one {pattern}, found {len(paths)}')
        return paths[0].read_text(errors='replace')
    pnr = one('impl/pnr/*.rpt.txt')
    if 'Resource Usage Summary' not in pnr or 'I/O Bank Usage Summary' not in pnr:
        raise BuildError('Incomplete P&R resource report')
    resource = pnr.split('Resource Usage Summary', 1)[1].split('I/O Bank Usage Summary', 1)[0]
    version = re.search(r'<Tool Version>:\s*([^\r\n]+)', pnr)
    part = re.search(r'<Part Number>:\s*([^\r\n]+)', pnr)
    if not version or not part:
        raise BuildError('P&R report missing tool version or part')
    counts = {name: unique_count(resource, label) for name, label in
              [('logic', 'Logic'), ('registers', 'Register')]}
    # This complete report schema omits zero-use optional memory rows.
    for name, label in [('bsram', 'BSRAM'), ('ssram', '--SSRAM(RAM16)')]:
        counts[name] = unique_count(resource, label) if label in resource else 0
    synthesis = one('impl/gwsynthesis/*_syn.rpt.html')
    summary = synthesis.split('name="utilization"', 1)
    if len(summary) != 2:
        raise BuildError('Synthesis utilization summary missing')
    summary = plain(summary[1].split('</table>', 1)[0])
    lut = re.findall(r'\((\d+) LUT,', summary)
    if len(lut) != 1:
        raise BuildError('Missing or malformed synthesis-summary LUT count')
    counts['synthesis_luts'] = int(lut[0])
    timing = one('impl/pnr/*_tr_content.html')
    timing_rows = rows(timing)
    for field, label in [('setup_violated_endpoints', 'Numbers of Setup Violated Endpoints'),
                         ('hold_violated_endpoints', 'Numbers of Hold Violated Endpoints'),
                         ('paths_analyzed', 'Numbers of Paths Analyzed')]:
        values = [row[1] for row in timing_rows if len(row) == 2 and row[0] == label]
        if len(values) != 1 or not values[0].isdigit():
            raise BuildError(f'Missing or malformed timing count: {label}')
        counts[field] = int(values[0])
    if not counts['paths_analyzed']:
        raise BuildError('Timing report analyzed no paths')
    setup_section = timing.split('name="Setup_Slack_Table"', 1)
    if len(setup_section) != 2:
        raise BuildError('Setup slack table missing')
    setup_rows = rows(setup_section[1].split('</table>', 1)[0])
    try:
        setup_slacks = [float(row[1]) for row in setup_rows
                        if len(row) > 1 and row[0].isdigit()]
        if not all(math.isfinite(value) for value in setup_slacks):
            raise ValueError('Nonfinite slack')
        counts['worst_setup_slack_ns'] = min(setup_slacks)
    except ValueError as exc:
        raise BuildError('Setup slack table empty or malformed') from exc
    if not math.isfinite(counts['worst_setup_slack_ns']):
        raise BuildError('Setup slack is not finite')
    counts.update(tool_version=version[1].strip(), part=part[1].strip())
    counts['warning_codes'] = sorted({code for path in directory.rglob('*.log')
                                     for code in re.findall(r'WARN\s*\(([^)]+)\)', path.read_text(errors='replace'))})
    return counts


@contextmanager
def build_lock(path):
    with open(path, 'a') as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise BuildError('Another Gowin job holds the build lock') from exc
        yield


def cleanup_recorded_job(tool, stage):
    """Clean up an interrupted launcher without risking a reused Windows PID."""
    identity_path = stage / 'windows-job.json'
    try:
        identity = json.loads(identity_path.read_text(encoding='utf-8-sig')) if identity_path.exists() else {}
        pid = identity.get('pid')
        ticks = str(identity.get('start_ticks', ''))
        executable = identity.get('executable', '')
        expected_tool = windows_path(tool).replace('\\', '/').casefold()
        if (not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0 or not ticks.isdigit()
                or not isinstance(executable, str)
                or executable.replace('\\', '/').casefold() != expected_tool):
            (stage / 'watchdog-cleanup.log').write_text('No safe recorded process identity; no process killed\n')
            return
        cleanup_script = f"""
$recordedJob = Get-Process -Id {pid} -ErrorAction SilentlyContinue
if ($null -ne $recordedJob -and [string]$recordedJob.StartTime.ToUniversalTime().Ticks -eq {ps_quote(ticks)} -and $recordedJob.Path.Replace('\\', '/') -eq {ps_quote(executable.replace(chr(92), '/'))}) {{
  & taskkill.exe /PID {pid} /T /F
}} else {{ Write-Output 'Recorded job already exited or identity changed; no process killed' }}
"""
        cleanup = subprocess.run(ps_command(cleanup_script), stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, timeout=15)
        (stage / 'watchdog-cleanup.log').write_bytes(cleanup.stdout)
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        (stage / 'watchdog-cleanup.log').write_text('Cleanup failed: ' + str(exc) + '\n')


def execute_job(tool, stage, timeout, command_log):
    """PowerShell owns the Windows PID and kills only that job's tree on timeout."""
    win_stage = windows_path(stage)
    script = f"""
$ErrorActionPreference = 'Stop'
$job = Start-Process -FilePath {ps_quote(windows_path(tool))} -ArgumentList 'build.tcl' -WorkingDirectory {ps_quote(win_stage)} -RedirectStandardOutput {ps_quote(win_stage + '/stdout.log')} -RedirectStandardError {ps_quote(win_stage + '/stderr.log')} -PassThru
# Obtain and retain the process handle before waiting; PowerShell 5.1 can
# otherwise expose a null ExitCode for a very short lived native process.
$nativeHandle = $job.Handle
$job.Id | Set-Content -LiteralPath {ps_quote(win_stage + '/windows-pid.txt')}
$identity = @{{ pid = $job.Id; start_ticks = [string]$job.StartTime.ToUniversalTime().Ticks; executable = {ps_quote(windows_path(tool))} }}
[System.IO.File]::WriteAllText({ps_quote(win_stage + '/windows-job.json')}, ($identity | ConvertTo-Json -Compress))
if (-not $job.WaitForExit({int(timeout * 1000)})) {{
  & taskkill.exe /PID $job.Id /T /F
  'timeout' | Set-Content -LiteralPath {ps_quote(win_stage + '/job-status.txt')}
  exit 124
}}
if ($null -eq $job.ExitCode) {{
  [System.IO.File]::WriteAllText({ps_quote(win_stage + '/job-status.txt')}, 'unknown')
  exit 125
}}
$nativeExitCode = [int]$job.ExitCode
[System.IO.File]::WriteAllText({ps_quote(win_stage + '/job-status.txt')}, [string]$nativeExitCode)
exit $nativeExitCode
"""
    # Keep the complete launcher reviewable as plain text. No execution policy
    # override is supplied; Windows/security approval remains user-operated.
    launcher_path = stage / 'launch.ps1'
    launcher_path.write_text(script)
    command = [str(POWERSHELL), '-NoProfile', '-NonInteractive', '-File',
               windows_path(launcher_path)]
    command_log.write_text(json.dumps({'argv': command, 'powershell': script}, indent=2) + '\n')
    # The inner bounded wait preserves the identity of the only Windows tree killed.
    try:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=timeout + 30)
    except subprocess.TimeoutExpired as exc:
        cleanup_recorded_job(tool, stage)
        (stage / 'launcher.log').write_bytes(exc.stdout or b'')
        raise BuildError('Windows launcher watchdog expired; recorded job tree cleanup attempted') from exc
    (stage / 'launcher.log').write_bytes(result.stdout)
    if result.returncode == 124:
        raise BuildError(f'Gowin exceeded {timeout}s; its process tree was terminated')
    if result.returncode:
        cleanup_recorded_job(tool, stage)
        raise BuildError(f'Gowin/launcher failed with exit status {result.returncode}')
    status = stage / 'job-status.txt'
    if not status.exists() or status.read_text().strip() != '0':
        cleanup_recorded_job(tool, stage)
        raise BuildError('Windows launcher did not record a numeric zero job exit status')
    if not tool.is_file():
        raise BuildError('Gowin executable disappeared during build; inspect Windows security history')


def build(args):
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    manifest = {'candidate': args.candidate, 'parent': args.parent,
                'started_utc': datetime.now(timezone.utc).isoformat(), 'status': 'in_progress',
                'verification_status': args.verification_status,
                'board_acceptance': 'pending', 'timeout_seconds': args.timeout,
                'tool_executable': str(args.tool.resolve())}
    stage = None
    start = time.monotonic()
    def save():
        (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    save()
    try:
        settings = json.loads(args.settings.read_text())
        if settings['part'] != 'GW2AR-LV18QN88C8/I7' or settings['top'] != 'gqh_competition_top':
            raise BuildError('Competition part and top must remain pinned')
        captured = output / 'inputs'
        captured.mkdir()
        sources = {'competition.v': args.rtl, 'board.cst': args.cst, 'clock.sdc': args.sdc,
                   'competition-options.json': args.settings, 'competition.tcl': args.tcl}
        if args.verification_evidence:
            evidence = json.loads(args.verification_evidence.read_text())
            if evidence.get('rtl_sha256') != digest(args.rtl):
                raise BuildError('Verification evidence is not tied to this RTL SHA-256')
            sources['verification-evidence.json'] = args.verification_evidence
            manifest['verification_evidence'] = evidence
        elif args.verification_status == 'locally_verified':
            raise BuildError('Locally verified builds require --verification-evidence tied to RTL SHA-256')
        for name, source in sources.items():
            shutil.copyfile(source, captured / name)
        manifest['inputs'] = {name: {'source': str(source.resolve()), 'sha256': digest(captured / name)}
                              for name, source in sources.items()}
        manifest['runner_sha256'] = digest(Path(__file__))
        if args.source_id:
            manifest['source_id'] = args.source_id
        manifest['requested_settings'] = settings
        manifest['tool_sha256'] = digest(args.tool)
        with build_lock(args.lock):
            temp_result = subprocess.run(ps_command('[Console]::WriteLine([System.IO.Path]::GetTempPath())'),
                                         check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            temp = local_path(temp_result.stdout.decode(errors='replace').strip())
            stage = temp / 'gqh_builds' / (args.candidate + '-' + uuid.uuid4().hex[:12])
            stage.mkdir(parents=True, exist_ok=False)
            manifest['windows_stage'] = windows_path(stage)
            for source in captured.iterdir():
                shutil.copyfile(source, stage / source.name)
            options = ' '.join(tcl_quote(word) for pair in settings['options'].items() for word in pair)
            script = '\n'.join([f'set stage {tcl_quote(windows_path(stage))}',
                                f'set device {tcl_quote(settings["device"])}',
                                f'set part {tcl_quote(settings["part"])}',
                                f'set top {tcl_quote(settings["top"])}',
                                f'set options [list {options}]',
                                'set inputs [list competition.v board.cst clock.sdc]',
                                'source [file join $stage competition.tcl]']) + '\n'
            (stage / 'build.tcl').write_text(script)
            save()
            execute_job(args.tool, stage, args.timeout, output / 'commands.json')
            for name in sources:
                if digest(stage / name) != manifest['inputs'][name]['sha256']:
                    raise BuildError(f'Staged input changed during build: {name}')
            counts = parse_reports(stage)
            if counts['part'] != settings['part']:
                raise BuildError('Report part does not match requested part')
            stdout = (stage / 'stdout.log').read_text(errors='replace')
            if 'GQH_BUILD_COMPLETED' not in stdout:
                raise BuildError('Tool did not acknowledge build completion')
            bitstreams = list(stage.glob('impl/pnr/*.fs'))
            if len(bitstreams) != 1 or not bitstreams[0].stat().st_size:
                raise BuildError('Missing or ambiguous bitstream')
            resolved = stage / 'resolved-settings.tcl'
            if not resolved.is_file() or not resolved.stat().st_size:
                raise BuildError('Resolved settings export missing')
            manifest.update(status='resource_screened', resources=counts,
                            bitstream_sha256=digest(bitstreams[0]),
                            resolved_settings_sha256=digest(resolved))
    except (BuildError, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        manifest.update(status='invalid', error=str(exc))
    finally:
        if stage is not None and stage.exists():
            try:
                manifest['staged_input_verification'] = {
                    name: bool((stage / name).is_file() and digest(stage / name) == identity['sha256'])
                    for name, identity in manifest.get('inputs', {}).items()}
                if not all(manifest['staged_input_verification'].values()):
                    manifest['status'] = 'invalid'
                    manifest['error'] = manifest.get('error', 'Staged input changed during build')
                shutil.copytree(stage, output / 'build', dirs_exist_ok=False)
            except OSError as exc:
                manifest['status'] = 'invalid'
                manifest['collection_error'] = str(exc)
                manifest.setdefault('error', 'Build evidence collection failed')
            if manifest['status'] == 'invalid':
                manifest.pop('resources', None)
        manifest['elapsed_seconds'] = round(time.monotonic() - start, 3)
        manifest['finished_utc'] = datetime.now(timezone.utc).isoformat()
        save()
    print(json.dumps(manifest, indent=2))
    return 0 if manifest['status'] == 'resource_screened' else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--parent', required=True)
    parser.add_argument('--rtl', type=Path, required=True)
    parser.add_argument('--cst', type=Path, default=ROOT / 'constraints/19_tang_nano_20k.cst')
    parser.add_argument('--sdc', type=Path, default=ROOT / 'constraints/tang_nano_20k.sdc')
    parser.add_argument('--settings', type=Path, default=ROOT / 'gowin/competition-options.json')
    parser.add_argument('--tcl', type=Path, default=ROOT / 'gowin/competition.tcl')
    parser.add_argument('--tool', type=Path, default=DEFAULT_TOOL)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--timeout', type=int, default=900)
    parser.add_argument('--lock', type=Path, default=Path('/tmp/gqh-gowin-build.lock'))
    parser.add_argument('--verification-status', required=True,
                        choices=['locally_verified', 'historical_accepted', 'unverified'])
    parser.add_argument('--verification-evidence', type=Path,
                        help='JSON correctness evidence with rtl_sha256 matching the supplied RTL')
    parser.add_argument('--source-id', help='Source commit/archive/patch identity recorded by the caller')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_.-]+', args.candidate):
        parser.error('Candidate ID must use letters, digits, dot, underscore, or hyphen')
    if not 1 <= args.timeout <= 900:
        parser.error('Timeout must be between 1 and 900 seconds')
    return build(args)


if __name__ == '__main__':
    sys.exit(main())
