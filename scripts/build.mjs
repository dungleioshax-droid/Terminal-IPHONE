#!/usr/bin/env node
//
// Build the RootHide .deb on Linux and verify it lands in dist/.
//
//   THEOS=/path/to/roothide/theos node scripts/build.mjs
//
// Without THEOS set it falls back to ~/theos. The roothide package scheme is
// applied here so a plain `npm run build:deb` always produces the Sileo-ready
// iphoneos-arm64e artifact in dist/.
//
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, rmSync, statSync } from 'node:fs';
import { delimiter, dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const PROJECT_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const DIST_DIR = join(PROJECT_ROOT, 'dist');
export const SCHEME = 'roothide';

/// Parse a Debian control stanza (handles multiline `Description:` values).
export function parseControl(text) {
	const fields = {};
	let current = null;
	for (const rawLine of text.split(/\r?\n/)) {
		if ((rawLine.startsWith(' ') || rawLine.startsWith('\t')) && current) {
			fields[current] += '\n' + rawLine.trim();
			continue;
		}
		const match = /^([A-Za-z][A-Za-z0-9-]*):\s?(.*)$/.exec(rawLine);
		if (!match) continue;
		current = match[1];
		fields[current] = match[2];
	}
	return fields;
}

/// Theos names artifacts <Package>_<Version>_<Architecture>.deb.
export function debFileName(name, version, architecture) {
	return `${name}_${version}_${architecture}.deb`;
}

function fail(message) {
	console.error(`\u001b[31m\u2717 ${message}\u001b[0m`);
	process.exit(1);
}

function info(message) {
	console.log(`\u001b[36m==>\u001b[0m ${message}`);
}

function resolveTheos() {
	const candidates = [process.env.THEOS];
	const home = process.env.HOME || process.env.USERPROFILE;
	if (home) candidates.push(join(home, 'theos'));
	for (const candidate of candidates) {
		if (candidate && existsSync(join(candidate, 'makefiles', 'common.mk'))) {
			return candidate;
		}
	}
	fail(
		'Theos not found. Clone https://github.com/roothide/theos and point ' +
			'THEOS at it (toolchain + iOS SDK required, see docs/BUILDING.md).',
	);
}

function run(command, args, options = {}) {
	const result = spawnSync(command, args, {
		stdio: 'inherit',
		cwd: PROJECT_ROOT,
		...options,
	});
	if (result.error) fail(`${command}: ${result.error.message}`);
	if (result.status !== 0) {
		fail(`\`${command} ${args.join(' ')}\` exited with status ${result.status}`);
	}
}

/// Deep-check the produced artifact with dpkg-deb when it is available.
function verifyDeb(debPath, expected) {
	const probe = spawnSync('dpkg-deb', ['--version'], { stdio: 'ignore' });
	if (probe.error || probe.status !== 0) {
		info('dpkg-deb unavailable on this host: deep control check skipped');
		return;
	}
	const result = spawnSync('dpkg-deb', ['-f', debPath], { encoding: 'utf8' });
	if (result.status !== 0) {
		fail(`dpkg-deb -f failed: ${result.stderr.trim()}`);
	}
	const control = parseControl(result.stdout);
	for (const field of ['Package', 'Version', 'Architecture']) {
		if (control[field] !== expected[field]) {
			fail(
				`${field} mismatch in artifact: expected ${expected[field]}, got ${control[field]}`,
			);
		}
	}
	if (control.Architecture !== 'iphoneos-arm64e') {
		fail(`artifact must be Architecture: iphoneos-arm64e, got ${control.Architecture}`);
	}
}

export function main() {
	const theos = resolveTheos();
	const control = parseControl(readFileSync(join(PROJECT_ROOT, 'control'), 'utf8'));
	const expected = {
		Package: (control.Package || '').trim(),
		Version: (control.Version || '').trim(),
		Architecture: (control.Architecture || '').trim(),
	};
	if (!expected.Package || !expected.Version || !expected.Architecture) {
		fail('control file must declare Package, Version and Architecture');
	}

	// PATH order matters: the repo's python plistutil shim shadows the
	// toolchain's plistutil, which links a libplist shared object that most
	// runners do not ship.
	const pathParts = [
		join(PROJECT_ROOT, 'scripts'),
		join(theos, 'bin'),
		join(theos, 'toolchain', 'linux', 'iphone', 'bin'),
	];
	if (process.env.PATH) pathParts.push(process.env.PATH);
	const env = {
		...process.env,
		THEOS: theos,
		PATH: pathParts.join(delimiter),
	};

	const artifact = join(DIST_DIR, debFileName(
		expected.Package, expected.Version, expected.Architecture,
	));
	mkdirSync(DIST_DIR, { recursive: true });
	if (existsSync(artifact)) rmSync(artifact);

	info(`THEOS=${theos}`);
	info(`building ${expected.Package} ${expected.Version} (${expected.Architecture}) scheme=${SCHEME}`);
	run('make', ['package', 'FINALPACKAGE=1', `THEOS_PACKAGE_SCHEME=${SCHEME}`], { env });

	if (!existsSync(artifact)) {
		const dir = readdirSync(DIST_DIR);
		fail(
			`expected ${artifact} but dist/ contains: ${dir.join(', ') || '(nothing)'}`,
		);
	}
	verifyDeb(artifact, expected);
	const { size } = statSync(artifact);
	info(`\u2713 output: ${join('dist', debFileName(
		expected.Package, expected.Version, expected.Architecture,
	))} (${(size / 1024).toFixed(1)} KiB)`);
}

const invokedDirectly = process.argv[1] &&
	import.meta.url === pathToFileURL(resolve(process.argv[1])).href;
if (invokedDirectly) main();