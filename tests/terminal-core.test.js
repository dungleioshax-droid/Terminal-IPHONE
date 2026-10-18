const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Terminal } = require('../src/terminal-core');

function run(term, line) { return term.exec(line); }

test('basic echo and pwd', () => {
  const t = new Terminal();
  assert.equal(run(t, 'pwd').stdout, '/');
  assert.equal(run(t, 'echo hello world').stdout, 'hello world');
});

test('mkdir cd touch ls', () => {
  const t = new Terminal();
  assert.equal(run(t, 'mkdir foo').code, 0);
  assert.equal(run(t, 'cd foo').code, 0);
  assert.equal(run(t, 'pwd').stdout, '/foo');
  run(t, 'touch bar.txt');
  const ls = run(t, 'ls').stdout;
  assert.ok(ls.includes('bar.txt'));
});

test('cat and redirection', () => {
  const t = new Terminal();
  run(t, 'echo hello > out.txt');
  assert.equal(run(t, 'cat out.txt').stdout, 'hello');
  run(t, 'echo world >> out.txt');
  assert.equal(run(t, 'cat out.txt').stdout, 'helloworld'); // echo no newline
});

test('rm directory requires -r', () => {
  const t = new Terminal();
  run(t, 'mkdir d');
  run(t, 'touch d/f');
  assert.notEqual(run(t, 'rm d').code, 0);
  assert.equal(run(t, 'rm -r d').code, 0);
  assert.equal(t.getNode(t.normalizePath('d')), null);
});

test('cd .. and ~', () => {
  const t = new Terminal({ user: 'bob' });
  run(t, 'mkdir a');
  run(t, 'mkdir a/b');
  run(t, 'cd a/b');
  assert.equal(run(t, 'pwd').stdout, '/a/b');
  run(t, 'cd ..');
  assert.equal(run(t, 'pwd').stdout, '/a');
  run(t, 'cd ~');
  assert.equal(run(t, 'pwd').stdout, '/home/bob');
});

test('unknown command', () => {
  const t = new Terminal();
  const r = run(t, 'nope');
  assert.notEqual(r.code, 0);
  assert.match(r.stderr, /command not found/);
});

test('history', () => {
  const t = new Terminal();
  run(t, 'echo a');
  run(t, 'echo b');
  const h = run(t, 'history').stdout;
  assert.match(h, /echo a/);
  assert.match(h, /echo b/);
});

test('wc', () => {
  const t = new Terminal();
  run(t, 'echo "hello world" > f.txt');
  const r = run(t, 'wc f.txt').stdout;
  assert.match(r, /1/);
  assert.match(r, /f.txt/);
});

test('mkdir -p not supported but mkdir works', () => {
  const t = new Terminal();
  run(t, 'mkdir a');
  run(t, 'mkdir a/b');
  assert.equal(run(t, 'cd a/b').code, 0);
});

test('find and tree', () => {
  const t = new Terminal();
  run(t, 'mkdir dir');
  run(t, 'touch dir/x.txt');
  assert.match(run(t, 'find . -name "*.txt"').stdout, /x.txt/);
  assert.match(run(t, 'tree').stdout, /dir/);
});

test('completion', () => {
  const t = new Terminal();
  const c = t.complete('ec');
  assert.ok(c.includes('echo'));
});

test('clear flag', () => {
  const t = new Terminal();
  const r = run(t, 'clear');
  assert.equal(r.clear, true);
});
