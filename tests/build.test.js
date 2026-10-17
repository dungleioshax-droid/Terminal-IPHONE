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