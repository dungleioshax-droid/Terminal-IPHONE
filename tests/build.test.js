const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');
const fs = require('node:fs');
const { spawnSync } = require('node:child_process');

const ROOT = path.resolve(__dirname, '..');

test('parseControl reads simple fields', async () => {
	const { parseControl } = await import('../scripts/build.mjs');
	const fields = parseControl(
		'Package: terminal-iphone-app-roothide\n' +
			'Version: 2.0.0\n' +
			'Architecture: iphoneos-arm64e\n' +
			'Name: Terminal iPhone\n',
	);
	assert.strictEqual(fields.Package, 'terminal-iphone-app-roothide');
	assert.strictEqual(fields.Version, '2.0.0');
	assert.strictEqual(fields.Architecture, 'iphoneos-arm64e');
	assert.strictEqual(fields.Name, 'Terminal iPhone');
});

test('parseControl joins multiline Description values', async () => {
	const { parseControl } = await import('../scripts/build.mjs');
	const fields = parseControl(
		'Package: demo\nDescription: first line\n second line\n third line\nSection: Utilities\n',
	);
	assert.strictEqual(fields.Package, 'demo');
	assert.strictEqual(fields.Description, 'first line\nsecond line\nthird line');
	assert.strictEqual(fields.Section, 'Utilities');
});

test('project control file targets roothide/Sileo', async () => {
	const { parseControl } = await import('../scripts/build.mjs');
	const control = parseControl(fs.readFileSync(path.join(ROOT, 'control'), 'utf8'));
	assert.match(control.Package, /^[a-z0-9][a-z0-9+.-]+$/);
	assert.strictEqual(control.Architecture, 'iphoneos-arm64e');
	assert.ok(/\d+\.\d+/.test(control.Version));
});

test('debFileName matches Theos artifact naming', async () => {
	const { debFileName } = await import('../scripts/build.mjs');
	assert.strictEqual(
		debFileName('terminal-iphone-app-roothide', '2.0.0', 'iphoneos-arm64e'),
		'terminal-iphone-app-roothide_2.0.0_iphoneos-arm64e.deb',
	);
});

test('plistutil shim converts xml to binary plist', () => {
	const out = path.join(ROOT, '.theos', 'test-plistutil.plist');
	fs.mkdirSync(path.dirname(out), { recursive: true });
	const result = spawnSync(
		path.join(ROOT, 'scripts', 'plistutil'),
		['-i', path.join(ROOT, 'Resources', 'Info.plist'), '-f', 'bin', '-o', out],
		{ encoding: 'utf8' },
	);
	assert.strictEqual(result.status, 0, result.stderr);
	const bytes = fs.readFileSync(out);
	assert.strictEqual(bytes.subarray(0, 8).toString('latin1'), 'bplist00');
	assert.match(bytes.toString('latin1'), /com\.terminaliphone\.app/);
});

test('layout ships the AI environment wrappers (v3)', async () => {
	const wrappers = [
		'layout/usr/local/bin/node',
		'layout/usr/local/bin/npm',
		'layout/usr/local/bin/npx',
		'layout/usr/local/bin/aienv',
		'layout/usr/local/bin/claude-auth',
		'layout/usr/bin/terminal-iphone',
	];
	for (const rel of wrappers) {
		const file = path.join(ROOT, rel);
		assert.ok(fs.existsSync(file), `${rel} must exist`);
		const mode = fs.statSync(file).mode & 0o111;
		assert.strictEqual(mode, 0o111, `${rel} must be executable`);
		const head = fs.readFileSync(file, 'utf8').split(/\r?\n/, 1)[0];
		assert.match(head, /^#!.*bin\/sh$/, `${rel} must be a POSIX sh script`);
	}
});

test('node wrapper carries the iOS-safe V8 flags and the shim preload', () => {
	const src = fs.readFileSync(path.join(ROOT, 'layout/usr/local/bin/node'), 'utf8');
	for (const flag of ['--no-wasm-code-gc', '--no-opt', '--no-sparkplug', '--single-threaded', '--liftoff', '--no-wasm-tier-up']) {
		assert.ok(src.includes(flag), `missing iOS flag ${flag}`);
	}
	assert.match(src, /usr\/local\/share\/aienv\/segmenter-shim\.js/);
});

test('aienv exposes the documented subcommands', () => {
	const src = fs.readFileSync(path.join(ROOT, 'layout/usr/local/bin/aienv'), 'utf8');
	for (const sub of ['doctor', 'fix-node', 'install-claude', 'python', 'bootstrap', 'status', 'version', 'help']) {
		assert.ok(src.includes(sub), `aienv must implement ${sub}`);
	}
	assert.match(src, /@anthropic-ai\/claude-code/);
});

test('npm wrapper pins the prefix inside the jailbreak root', () => {
	const src = fs.readFileSync(path.join(ROOT, 'layout/usr/local/bin/npm'), 'utf8');
	assert.match(src, /NPM_CONFIG_PREFIX/);
	assert.match(src, /npm-cli\.js/);
});

test('bootstrap-iphone.sh delegates to aienv and stays POSIX', () => {
	const src = fs.readFileSync(path.join(ROOT, 'scripts/bootstrap-iphone.sh'), 'utf8');
	assert.doesNotMatch(src, /apt-get|ubuntu-ports|nvm/);
	assert.match(src, /aienv/);
});

test('fetch-runtime exposes prepareRuntime and pins the iOS Node build', async () => {
	const mod = await import('../scripts/fetch-runtime.mjs');
	assert.strictEqual(typeof mod.prepareRuntime, 'function');
	const src = fs.readFileSync(path.join(ROOT, 'scripts/fetch-runtime.mjs'), 'utf8');
	assert.match(src, /18\.20\.4/);
	assert.match(src, /sha256/i);
	assert.match(src, /registry\.npmjs\.org/);
});