#!/usr/bin/env node
//
// Stage the on-device runtime into build/runtime/:
//
//   usr/local/lib/nodejs/node            -> arm64 Node.js 18.20.4 binary (iOS)
//   usr/local/lib/nodejs/entitlements.xml
//   usr/local/lib/node_modules/npm/...   -> npm 10.8.2 (pure JS, Node >=18)
//
// The Node.js binary comes from the arm64 iOS .deb published by
// https://github.com/imcynic/nodejs-ios (Node.js itself is MIT-licensed).
// Everything is fetched at BUILD time only — the device never downloads it:
// the final Terminal-IPHONE .deb is fully self-contained (Node, npm, the AI
// CLI helpers and the segmenter shim all install straight from the package).
//
// Both artifacts are integrity-checked (SHA-256 for the .deb, the npm
// registry sha512 for the tarball) before anything is staged.
//
// Usage: node scripts/fetch-runtime.mjs [--force]
// Used automatically by scripts/build.mjs before `make package`.
//
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const PROJECT_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const RUNTIME_DIR = join(PROJECT_ROOT, 'build', 'runtime');
const CACHE_DIR = join(PROJECT_ROOT, 'build', 'runtime-cache');

const NODE_VERSION = '18.20.4-1';
const NODE_DEB_SHA256 =
	'89232afced627c58ff3e5dd5843d2aeebbfabcb5f4855987505c9387d7386f15';
const NODE_DEB_NAME = `nodejs_${NODE_VERSION}_iphoneos-arm64.deb`;
const NODE_DEB_URLS = [
	`https://raw.githubusercontent.com/imcynic/nodejs-ios/main/${NODE_DEB_NAME}`,
	`https://cdn.jsdelivr.net/gh/imcynic/nodejs-ios@main/${NODE_DEB_NAME}`,
];

const NPM_VERSION = '10.8.2';
const NPM_TGZ_NAME = `npm-${NPM_VERSION}.tgz`;
const NPM_URL = `https://registry.npmjs.org/npm/-/${NPM_TGZ_NAME}`;
const NPM_PREFIX = 'node_modules/npm'; // path inside the npm tarball

const FORCE =
	process.argv.includes('--force') || process.env.FETCH_RUNTIME === 'force';

function fail(message) {
	console.error(`\u001b[31m\u2717 fetch-runtime: ${message}\u001b[0m`);
	process.exit(1);
}

function info(message) {
	console.log(`\u001b[36m==>\u001b[0m fetch-runtime: ${message}`);
}

function sha256File(filePath) {
	const hash = createHash('sha256');
	hash.update(readFileSync(filePath));
	return hash.digest('hex');
}

function download(url, dest) {
	const result = spawnSync(
		'curl',
		['-fL', '--retry', '3', '--connect-timeout', '30', '-o', dest, url],
		{ stdio: ['ignore', 'ignore', 'inherit'] },
	);
	return (
		!result.error && result.status === 0 && existsSync(dest) &&
		statSync(dest).size > 0
	);
}

/// Minimal POSIX `ar` member extractor (the .deb container format).
function debMembers(debPath) {
	const bytes = readFileSync(debPath);
	if (bytes.subarray(0, 8).toString('ascii') !== '!<arch>\n') {
		fail(`${NODE_DEB_NAME}: not a Debian archive (bad ar magic)`);
	}
	const members = [];
	let offset = 8;
	while (offset + 60 <= bytes.length) {
		const header = bytes.subarray(offset, offset + 60);
		const name = header.subarray(0, 16).toString('ascii').trim();
		const size = parseInt(header.subarray(48, 58).toString('ascii').trim(), 10);
		if (!Number.isFinite(size)) fail(`${debPath}: broken ar header`);
		const start = offset + 60;
		members.push({ name, data: bytes.subarray(start, start + size) });
		offset = start + size + (size % 2); // members are 2-byte aligned
	}
	return members;
}

/// npm dist.integrity for the pinned version, straight from the registry
/// ("sha512-<base64>"; falls back to legacy dist.sha512 when present).
async function npmSha512() {
	const response = await fetch(`https://registry.npmjs.org/npm/${NPM_VERSION}`);
	if (!response.ok) fail(`registry.npmjs.org returned ${response.status}`);
	const meta = await response.json();
	const integrity = meta.dist?.integrity || '';
	if (integrity.startsWith('sha512-')) return integrity.slice('sha512-'.length);
	return meta.dist?.sha512 || fail('npm metadata has no sha512 integrity');
}

async function acquireNodeDeb() {
	const cachePath = join(CACHE_DIR, NODE_DEB_NAME);
	if (existsSync(cachePath) && !FORCE) {
		info(`node: using cached ${NODE_DEB_NAME}`);
	} else {
		mkdirSync(CACHE_DIR, { recursive: true });
		let downloaded = false;
		for (const url of NODE_DEB_URLS) {
			info(`node: downloading ${url}`);
			if (download(url, cachePath)) {
				downloaded = true;
				break;
			}
			info('node: mirror failed, trying the next one');
		}
		if (!downloaded) fail('could not download the Node.js iOS deb (all mirrors failed)');
	}
	if (statSync(cachePath).size < 5_000_000) {
		fail(`${NODE_DEB_NAME}: suspiciously small (${statSync(cachePath).size} bytes)`);
	}
	const actual = sha256File(cachePath);
	if (actual !== NODE_DEB_SHA256) {
		fail(
			`${NODE_DEB_NAME}: sha256 mismatch\n` +
				`  expected ${NODE_DEB_SHA256}\n` +
				`  actual   ${actual}`,
		);
	}
	info('node: sha256 verified');
	return cachePath;
}

async function acquireNpmTarball() {
	const cachePath = join(CACHE_DIR, NPM_TGZ_NAME);
	if (existsSync(cachePath) && !FORCE) {
		info(`npm: using cached ${NPM_TGZ_NAME}`);
	} else {
		mkdirSync(CACHE_DIR, { recursive: true });
		info(`npm: downloading ${NPM_URL}`);
		if (!download(NPM_URL, cachePath)) fail('could not download the npm tarball');
	}
	const hash = createHash('sha512');
	hash.update(readFileSync(cachePath));
	const actual = hash.digest('base64');
	const expected = await npmSha512();
	if (actual !== expected) {
		fail(
			`${NPM_TGZ_NAME}: sha512 mismatch\n` +
				`  expected ${expected}\n` +
				`  actual   ${actual}`,
		);
	}
	info('npm: sha512 verified against the registry');
	return cachePath;
}

function extractNodeDeb(debPath) {
	info('node: extracting the <root>/usr/local payload');
	rmSync(join(RUNTIME_DIR, 'usr'), { recursive: true, force: true });
	rmSync(join(RUNTIME_DIR, 'jb'), { recursive: true, force: true });
	mkdirSync(RUNTIME_DIR, { recursive: true });

	const dataTarXz = debMembers(debPath).find((m) => m.name === 'data.tar.xz') ||
		fail(`${NODE_DEB_NAME}: no data.tar.xz member`);
	const tmp = join(CACHE_DIR, 'nodejs-data.tar.xz');
	mkdirSync(CACHE_DIR, { recursive: true });
	writeFileSync(tmp, dataTarXz.data);

	// The deb stores paths as ./var/jb/usr/local/... (rootless layout). GNU
	// tar counts the leading "./" as one path component, so stripping three
	// components (./ + var + jb) lands the payload at RUNTIME_DIR/usr/local.
	const extract = spawnSync(
		'sh',
		[
			'-c',
			`xz -dc "${tmp}" | tar -xpf - -C "${RUNTIME_DIR}" --strip-components=3`,
		],
		{ stdio: 'inherit' },
	);
	rmSync(tmp, { force: true });
	if (extract.error || extract.status !== 0) {
		fail('extracting the deb failed (xz-utils and GNU tar are required)');
	}
}

function extractNpmTarball(tgzPath) {
	info('npm: extracting');
	const target = join(
		RUNTIME_DIR, 'usr', 'local', 'lib', NPM_PREFIX,
	);
	rmSync(join(RUNTIME_DIR, 'usr', 'local', 'lib', 'node_modules'), {
		recursive: true,
		force: true,
	});
	mkdirSync(target, { recursive: true });
	const extract = spawnSync('tar', ['-xzf', tgzPath, '-C', target, '--strip-components=1'], {
		stdio: 'inherit',
	});
	if (extract.error || extract.status !== 0) fail('extracting npm failed');
}

function stageShimDirectory() {
	// layout/usr/local/share/aienv/segmenter-shim.js is committed in the repo;
	// nothing to fetch here. Kept as a no-op hook for future runtime extras.
}

function verifyStaged() {
	const node = join(RUNTIME_DIR, 'usr', 'local', 'lib', 'nodejs', 'node');
	const ents = join(RUNTIME_DIR, 'usr', 'local', 'lib', 'nodejs', 'entitlements.xml');
	const npmCli = join(RUNTIME_DIR, 'usr', 'local', 'lib', 'node_modules', 'npm', 'bin', 'npm-cli.js');
	for (const file of [node, ents, npmCli]) {
		if (!existsSync(file)) throw new Error(`staged runtime incomplete, missing ${file}`);
	}
	const head = readFileSync(node).subarray(0, 4);
	if (head.toString('hex') !== 'cffaedfe') {
		// little-endian MH_MAGIC_64 (0xfeedfacf)
		throw new Error('staged node binary is not a Mach-O arm64 executable');
	}
	const size = statSync(node).size;
	if (size < 30_000_000) throw new Error(`staged node binary too small (${size} bytes)`);
	info(`staged runtime OK: node ${NODE_VERSION}, npm ${NPM_VERSION}`);
}

async function runPrepare() {
	mkdirSync(RUNTIME_DIR, { recursive: true });
	const deb = await acquireNodeDeb();
	const tgz = await acquireNpmTarball();
	extractNodeDeb(deb);
	extractNpmTarball(tgz);
	stageShimDirectory();
	verifyStaged();
}

/// Stage (or reuse) the runtime. Skips the network when everything is already
/// staged and healthy, unless `force` (or `--force` / FETCH_RUNTIME=force).
export async function prepareRuntime({ force = false } = {}) {
	const skipForce = force || FORCE;
	const nodeTarget = join(RUNTIME_DIR, 'usr', 'local', 'lib', 'nodejs', 'node');
	const npmTarget = join(RUNTIME_DIR, 'usr', 'local', 'lib', 'node_modules', 'npm', 'bin', 'npm-cli.js');
	if (!skipForce && existsSync(nodeTarget) && existsSync(npmTarget)) {
		try {
			verifyStaged();
			info('runtime already staged and healthy — skipping the network.');
			return;
		} catch (error) {
			info(`staged runtime unusable (${error.message.split('\n')[0]}) — re-staging.`);
		}
	}
	await runPrepare();
}

// Invoked directly: node scripts/fetch-runtime.mjs [--force]
const invokedDirectly = process.argv[1] &&
	import.meta.url === new URL(`file://${resolve(process.argv[1])}`).href;
if (invokedDirectly) {
	prepareRuntime().catch(fail);
}
