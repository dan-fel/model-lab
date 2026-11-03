// Small helpers the runner shares: content digests and running the checker.
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';

export const digest = value => crypto.createHash('sha256').update(value).digest('hex');

export function run(program, args, cwd, input, timeout = 30000) {
    const result = spawnSync(program, args, { cwd, input, encoding: 'utf8', timeout, maxBuffer: 256 * 1024 });
    if (result.error) throw result.error;
    return { exit_code: result.status, stdout: result.stdout, stderr: result.stderr, signal: result.signal };
}
