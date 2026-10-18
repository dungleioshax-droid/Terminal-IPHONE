(function (global) {
  'use strict';

  function createFS() {
    return { type: 'dir', children: {} };
  }

  function err(msg) {
    return { stdout: '', stderr: msg, code: 1, clear: false };
  }

  function ok(stdout) {
    return { stdout: stdout == null ? '' : String(stdout), stderr: '', code: 0, clear: false };
  }

  function parseLine(line) {
    const args = [];
    let cur = '';
    let quote = null;
    let token = false;
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (quote) {
        if (c === quote) {
          quote = null;
        } else if (c === '\\' && quote === '"') {
          i++;
          cur += line[i] || '';
          token = true;
        } else {
          cur += c;
          token = true;
        }
      } else {
        if (c === '"' || c === "'") {
          quote = c;
          token = true;
        } else if (/\s/.test(c)) {
          if (token) {
            args.push(cur);
            cur = '';
            token = false;
          }
        } else if (c === '\\') {
          i++;
          cur += line[i] || '';
          token = true;
        } else {
          cur += c;
          token = true;
        }
      }
    }
    if (token) args.push(cur);
    return args;
  }

  class Terminal {
    constructor(options) {
      options = options || {};
      this.fs = options.fs ? options.fs : createFS();
      this.cwd = options.cwd ? options.cwd.slice() : [];
      this.user = options.user || 'iphone';
      this.hostname = options.hostname || 'iphone';
      this.history = [];
      this.env = Object.assign({ HOME: '/home/' + (options.user || 'iphone'), USER: options.user || 'iphone', PATH: '/bin:/usr/bin', SHELL: '/bin/sh', TERM: 'xterm-256color' }, options.env || {});
      this.maxHistory = options.maxHistory || 1000;
      this.commands = Object.assign({}, Terminal.commands);
      if (options.commands) Object.assign(this.commands, options.commands);
      this._seed();
    }

    _seed() {
      const mk = (p, type, content) => {
        const segs = this.normalizePath(p);
        const name = segs[segs.length - 1];
        const parent = this.getNode(segs.slice(0, -1));
        if (!parent || parent.type !== 'dir') return;
        if (parent.children[name]) return;
        parent.children[name] = type === 'dir' ? { type: 'dir', children: {} } : { type: 'file', content: content || '' };
      };
      mk('/home', 'dir');
      mk('/home/' + this.user, 'dir');
      mk('/bin', 'dir');
      mk('/etc', 'dir');
      mk('/tmp', 'dir');
      mk('/usr', 'dir');
      mk('/usr/bin', 'dir');
      mk('/home/' + this.user + '/welcome.txt', 'file', 'Welcome to Terminal for iPhone!\nType "help" to see available commands.\n');
      mk('/etc/hostname', 'file', this.hostname + '\n');
      mk('/etc/apt', 'dir');
      mk('/opt', 'dir');
      mk('/etc/os-release', 'file', 'NAME="Ubuntu"\nVERSION="22.04.4 LTS (Jammy Jellyfish)"\nID=ubuntu\nID_LIKE=debian\nPRETTY_NAME="Ubuntu 22.04.4 LTS"\nVERSION_ID="22.04"\n');
      mk('/etc/apt/sources.list', 'file', 'deb http://ports.ubuntu.com/ubuntu-ports jammy main restricted universe multiverse\n');
      mk('/README.md', 'file', '# Terminal-IPHONE\n');
    }

    normalizePath(input, base) {
      base = base || this.cwd;
      let parts;
      if (input == null || input === '') return base.slice();
      if (input === '~') {
        parts = ['home', this.user];
      } else if (input.startsWith('~/')) {
        parts = ['home', this.user].concat(input.slice(2).split('/'));
      } else if (input.startsWith('/')) {
        parts = input.split('/');
      } else {
        parts = base.concat(input.split('/'));
      }
      const out = [];
      for (const seg of parts) {
        if (seg === '' || seg === '.') continue;
        if (seg === '..') {
          if (out.length) out.pop();
        } else {
          out.push(seg);
        }
      }
      return out;
    }

    getNode(segs) {
      let node = this.fs;
      for (const s of segs) {
        if (!node || node.type !== 'dir' || !node.children || !node.children[s]) return null;
        node = node.children[s];
      }
      return node;
    }

    pathString(segs) {
      segs = segs || this.cwd;
      if (!segs.length) return '/';
      return '/' + segs.join('/');
    }

    prompt() {
      const p = this.pathString();
      const short = p === '/home/' + this.user ? '~' : p;
      return short + ' $ ';
    }

    exec(line, stdin) {
      line = String(line == null ? '' : line);
      const trimmed = line.trim();
      if (trimmed === '') return ok('');

      // history
      if (this.history[this.history.length - 1] !== trimmed) {
        this.history.push(trimmed);
        if (this.history.length > this.maxHistory) this.history.shift();
      }

      return this._evalSequence(trimmed, stdin || '');
    }

    topSplit(str, seps) {
      const parts = [];
      let cur = '';
      let quote = null;
      let i = 0;
      const sorted = seps.slice().sort((a, b) => b.length - a.length);
      while (i < str.length) {
        if (quote) {
          cur += str[i];
          if (str[i] === quote) quote = null;
          else if (str[i] === '\\' && quote === '"') { i++; cur += str[i] || ''; }
          i++; continue;
        }
        if (str[i] === '"' || str[i] === "'") { quote = str[i]; cur += str[i]; i++; continue; }
        let matched = null;
        for (const s of sorted) {
          if (str.startsWith(s, i)) { matched = s; break; }
        }
        if (matched) {
          parts.push({ text: cur.trim(), sep: matched });
          cur = '';
          i += matched.length;
        } else {
          cur += str[i]; i++;
        }
      }
      if (cur.trim() !== '' || parts.length === 0) parts.push({ text: cur.trim(), sep: null });
      return parts;
    }

    _evalSequence(str, stdin) {
      const segments = this.topSplit(str, [';']);
      let result = ok('');
      let first = true;
      let count = segments.filter(s => s.text).length;
      for (const seg of segments) {
        if (!seg.text) continue;
        const r = this._evalAndOr(seg.text, first ? (stdin || '') : '');
        if (count > 1) {
          const out = [result.stdout, r.stdout].filter(s => s !== '' && s != null);
          result = {
            stdout: out.join(out.length > 1 ? '\n' : ''),
            stderr: [result.stderr, r.stderr].filter(Boolean).join('\n'),
            code: r.code,
            clear: result.clear || r.clear
          };
        } else {
          result = r;
        }
        first = false;
      }
      if (count === 0) result = ok('');
      return result;
    }

    _evalAndOr(str, stdin) {
      const parts = this.topSplit(str, ['&&', '||']);
      let result = null;
      let run = true;
      for (let i = 0; i < parts.length; i++) {
        if (i > 0) {
          const op = parts[i - 1].sep;
          if (op === '&&') run = (result && result.code === 0);
          else if (op === '||') run = (result && result.code !== 0);
        }
        if (run) {
          result = this._evalPipeline(parts[i].text, i === 0 ? (stdin || '') : '');
        }
        if (!result) result = ok('');
      }
      return result || ok('');
    }

    _evalPipeline(str, stdin) {
      const parts = this.topSplit(str, ['|']);
      let currentStdin = stdin || '';
      let result = ok('');
      for (const p of parts) {
        if (!p.text) { result = ok(''); continue; }
        result = this._execSingle(p.text, currentStdin);
        currentStdin = (result && result.stdout) ? result.stdout : '';
      }
      return result;
    }

    _execSingle(line, stdin) {
      stdin = stdin || '';
      const trimmed = String(line).trim();
      if (trimmed === '') return ok('');

      let redir = null;
      const tokens = parseLine(trimmed);
      const r2 = [];
      for (let i = 0; i < tokens.length; i++) {
        if (tokens[i] === '>' || tokens[i] === '>>') {
          redir = { mode: tokens[i], file: tokens[i + 1] };
          break;
        }
        r2.push(tokens[i]);
      }
      const finalArgs = redir ? r2 : tokens;

      const name = finalArgs[0];
      const cmdArgs = finalArgs.slice(1);
      const cmd = this.commands[name];
      if (!cmd) {
        const r = err(name + ': command not found');
        return this._applyRedirect(r, redir);
      }
      let result;
      try {
        result = cmd({ term: this, args: cmdArgs, stdin: stdin });
      } catch (e) {
        result = err((e && e.message) ? e.message : String(e));
      }
      if (!result) result = ok('');
      if (redir) {
        const segs = this.normalizePath(redir.file);
        const fname = segs[segs.length - 1];
        const parent = this.getNode(segs.slice(0, -1));
        if (!parent || parent.type !== 'dir') {
          return err('redirection: ' + redir.file + ': No such file or directory');
        }
        let content = result.stdout || '';
        const existing = parent.children[fname];
        if (redir.mode === '>>' && existing && existing.type === 'file') {
          existing.content = (existing.content || '') + content;
        } else {
          parent.children[fname] = { type: 'file', content: content };
        }
        result = Object.assign({}, result, { stdout: '' });
      }
      return result;
    }

    _applyRedirect(r, redir) {
      return r;
    }

    complete(partial) {
      // returns array of completion candidates
      partial = partial || '';
      // if contains slash or last token path-like, complete paths; else commands
      const toks = parseLine(partial);
      const last = toks.length ? toks[toks.length - 1] : '';
      // determine if completing command position
      const isCommandPos = toks.length <= 1 && !partial.endsWith(' ');
      if (isCommandPos) {
        return Object.keys(this.commands).filter(c => c.startsWith(last)).sort();
      }
      // path completion
      const dir = last.includes('/') ? last.slice(0, last.lastIndexOf('/') + 1) : '';
      const base = last.includes('/') ? last.slice(last.lastIndexOf('/') + 1) : last;
      const segs = this.normalizePath(dir || '.');
      const node = this.getNode(segs);
      if (!node || node.type !== 'dir') return [];
      return Object.keys(node.children)
        .filter(n => n.startsWith(base))
        .map(n => dir + n + (node.children[n].type === 'dir' ? '/' : ''))
        .sort();
    }
  }

  // ---- commands ----
  function E(code, out, errm) { return { stdout: out || '', stderr: errm || '', code: code == null ? 0 : code, clear: false }; }

  Terminal.commands = {
    help: (ctx) => {
      const names = Object.keys(ctx.term.commands).sort();
      return ok('Available commands:\n' + names.join('  ') + '\n\nType "<command> --help" for details (not all support it).');
    },
    clear: (ctx) => ({ stdout: '', stderr: '', code: 0, clear: true }),
    pwd: (ctx) => ok(ctx.term.pathString()),
    whoami: (ctx) => ok(ctx.term.user),
    hostname: (ctx) => ok(ctx.term.hostname),
    date: (ctx) => ok(new Date().toString()),
    uname: (ctx) => ok('Terminal-IPHONE 1.0 (web) ' + (typeof navigator !== 'undefined' ? navigator.userAgent.split(' ')[0] : 'Linux')),
    echo: (ctx) => ok(ctx.args.join(' ')),
    true: (ctx) => ok(''),
    false: (ctx) => ({ stdout: '', stderr: '', code: 1, clear: false }),
    history: (ctx) => ok(ctx.term.history.map((h, i) => '  ' + (i + 1) + '  ' + h).join('\n')),
    env: (ctx) => ok(Object.keys(ctx.term.env).map(k => k + '=' + ctx.term.env[k]).join('\n')),
    export: (ctx) => {
      for (const a of ctx.args) {
        const idx = a.indexOf('=');
        if (idx >= 0) ctx.term.env[a.slice(0, idx)] = a.slice(idx + 1);
      }
      return ok('');
    },
    cd: (ctx) => {
      const term = ctx.term;
      const arg = ctx.args[0] || '~';
      const segs = term.normalizePath(arg);
      const node = term.getNode(segs);
      if (!node) return err('cd: ' + arg + ': No such file or directory');
      if (node.type !== 'dir') return err('cd: ' + arg + ': Not a directory');
      term.cwd = segs;
      return ok('');
    },
    ls: (ctx) => {
      const term = ctx.term;
      const flags = ctx.args.filter(a => a.startsWith('-'));
      const paths = ctx.args.filter(a => !a.startsWith('-'));
      const showAll = flags.some(f => f.includes('a'));
      const long = flags.some(f => f.includes('l'));
      const target = paths[0] ? term.normalizePath(paths[0]) : term.cwd.slice();
      const node = term.getNode(target);
      if (!node) return err('ls: cannot access \'' + (paths[0] || '.') + '\': No such file or directory');
      if (node.type === 'file') return ok(paths[0] || '');
      const names = Object.keys(node.children).filter(n => showAll || !n.startsWith('.')).sort();
      if (long) {
        const lines = names.map(n => {
          const c = node.children[n];
          const type = c.type === 'dir' ? 'd' : '-';
          const size = c.type === 'file' ? (c.content || '').length : 0;
          return type + 'rw-r--r-- 1 ' + term.user + ' ' + term.user + ' ' + size + ' ' + n;
        });
        return ok(lines.join('\n'));
      }
      return ok(names.join('  '));
    },
    mkdir: (ctx) => {
      const term = ctx.term;
      const pFlag = ctx.args.some(a => /^-/.test(a) && /p/.test(a));
      const targets = ctx.args.filter(a => !/^-/.test(a));
      if (!targets.length) return err('mkdir: missing operand');
      for (const a of targets) {
        const segs = term.normalizePath(a);
        if (!segs.length) return err('mkdir: cannot create directory \'' + a + '\'');
        if (pFlag) {
          let cur = [];
          for (const seg of segs) {
            cur = cur.concat(seg);
            const node = term.getNode(cur);
            if (!node) {
              const parent = term.getNode(cur.slice(0, -1));
              if (!parent || parent.type !== 'dir') return err('mkdir: cannot create directory \'' + a + '\': No such file or directory');
              parent.children[seg] = { type: 'dir', children: {} };
            } else if (node.type !== 'dir') {
              return err('mkdir: cannot create directory \'' + a + '\': File exists');
            }
          }
        } else {
          const name = segs[segs.length - 1];
          const parent = term.getNode(segs.slice(0, -1));
          if (!parent || parent.type !== 'dir') return err('mkdir: cannot create directory \'' + a + '\': No such file or directory');
          if (parent.children[name]) return err('mkdir: cannot create directory \'' + a + '\': File exists');
          parent.children[name] = { type: 'dir', children: {} };
        }
      }
      return ok('');
    },
    touch: (ctx) => {
      const term = ctx.term;
      if (!ctx.args.length) return err('touch: missing file operand');
      for (const a of ctx.args) {
        const segs = term.normalizePath(a);
        const name = segs[segs.length - 1];
        const parent = term.getNode(segs.slice(0, -1));
        if (!parent || parent.type !== 'dir') return err('touch: cannot touch \'' + a + '\': No such file or directory');
        if (!parent.children[name]) parent.children[name] = { type: 'file', content: '' };
      }
      return ok('');
    },
    cat: (ctx) => {
      const term = ctx.term;
      if (!ctx.args.length) return ok(ctx.stdin || '');
      const out = [];
      for (const a of ctx.args) {
        const node = term.getNode(term.normalizePath(a));
        if (!node) return err('cat: ' + a + ': No such file or directory');
        if (node.type !== 'file') return err('cat: ' + a + ': Is a directory');
        out.push(node.content || '');
      }
      return ok(out.join(''));
    },
    rm: (ctx) => {
      const term = ctx.term;
      const recursive = ctx.args.some(a => /^-/.test(a) && /r/.test(a));
      const force = ctx.args.some(a => /^-/.test(a) && /f/.test(a));
      const targets = ctx.args.filter(a => !/^-/.test(a));
      if (!targets.length) return err('rm: missing operand');
      for (const a of targets) {
        const segs = term.normalizePath(a);
        if (!segs.length) return err('rm: cannot remove root');
        const name = segs[segs.length - 1];
        const parent = term.getNode(segs.slice(0, -1));
        if (!parent || !parent.children[name]) {
          if (force) continue;
          return err('rm: cannot remove \'' + a + '\': No such file or directory');
        }
        const node = parent.children[name];
        if (node.type === 'dir' && Object.keys(node.children).length && !recursive) {
          return err('rm: cannot remove \'' + a + '\': Directory not empty');
        }
        if (node.type === 'dir' && !recursive && Object.keys(node.children).length === 0) {
          // allow removing empty dir only with -r? typical rm needs -r for dirs; but allow empty? require -r for dir
          return err('rm: cannot remove \'' + a + '\': Is a directory');
        }
        delete parent.children[name];
      }
      return ok('');
    },
    cp: (ctx) => {
      const term = ctx.term;
      if (ctx.args.length < 2) return err('cp: missing file operand');
      const src = ctx.args[0];
      const dst = ctx.args[1];
      const srcNode = term.getNode(term.normalizePath(src));
      if (!srcNode) return err('cp: cannot stat \'' + src + '\': No such file or directory');
      const dstSegs = term.normalizePath(dst);
      const dstName = dstSegs[dstSegs.length - 1];
      const dstParent = term.getNode(dstSegs.slice(0, -1));
      if (!dstParent || dstParent.type !== 'dir') return err('cp: target \'' + dst + '\': No such file or directory');
      const clone = JSON.parse(JSON.stringify(srcNode));
      if (dstParent.children[dstName] && dstParent.children[dstName].type === 'dir' && srcNode.type !== 'dir') {
        // copy into dir
        dstParent.children[dstName].children[src.split('/').pop()] = clone;
      } else {
        dstParent.children[dstName] = clone;
      }
      return ok('');
    },
    mv: (ctx) => {
      const term = ctx.term;
      if (ctx.args.length < 2) return err('mv: missing file operand');
      const src = ctx.args[0];
      const dst = ctx.args[1];
      const srcSegs = term.normalizePath(src);
      if (!srcSegs.length) return err('mv: cannot move root');
      const srcName = srcSegs[srcSegs.length - 1];
      const srcParent = term.getNode(srcSegs.slice(0, -1));
      if (!srcParent || !srcParent.children[srcName]) return err('mv: cannot stat \'' + src + '\': No such file or directory');
      const node = srcParent.children[srcName];
      const dstSegs = term.normalizePath(dst);
      const dstName = dstSegs[dstSegs.length - 1];
      const dstParent = term.getNode(dstSegs.slice(0, -1));
      if (!dstParent || dstParent.type !== 'dir') return err('mv: target \'' + dst + '\': No such file or directory');
      if (dstParent.children[dstName] && dstParent.children[dstName].type === 'dir' && node.type !== 'dir') {
        dstParent.children[dstName].children[srcName] = node;
      } else {
        dstParent.children[dstName] = node;
      }
      if (!(dstParent === srcParent && dstName === srcName)) delete srcParent.children[srcName];
      return ok('');
    },
    wc: (ctx) => {
      const term = ctx.term;
      const files = ctx.args.filter(a => !a.startsWith('-'));
      const linesFlag = ctx.args.includes('-l');
      const wordsFlag = ctx.args.includes('-w');
      const charsFlag = ctx.args.includes('-c');
      const countAll = !linesFlag && !wordsFlag && !charsFlag;
      const doLines = countAll || linesFlag;
      const doWords = countAll || wordsFlag;
      const doChars = countAll || charsFlag;
      const report = (content, name) => {
        const lc = content.split('\n').length - (content.endsWith('\n') ? 1 : 0);
        const wc = content.split(/\s+/).filter(Boolean).length;
        const cc = content.length;
        const parts = [];
        if (doLines) parts.push(String(lc));
        if (doWords) parts.push(String(wc));
        if (doChars) parts.push(String(cc));
        if (name) parts.push(name);
        return parts.join('  ') + (files.length > 1 || name ? '' : '');
      };
      if (!files.length) {
        const c = ctx.stdin || '';
        return ok(report(c, ''));
      }
      const out = [];
      let totL = 0, totW = 0, totC = 0;
      for (const f of files) {
        const node = term.getNode(term.normalizePath(f));
        if (!node || node.type !== 'file') return err('wc: ' + f + ': No such file or directory');
        const content = node.content || '';
        const lc = content.split('\n').length - (content.endsWith('\n') ? 1 : 0);
        const wc = content.split(/\s+/).filter(Boolean).length;
        const cc = content.length;
        const parts = [];
        if (doLines) parts.push(String(lc));
        if (doWords) parts.push(String(wc));
        if (doChars) parts.push(String(cc));
        parts.push(f);
        out.push(parts.join('  '));
        totL += lc; totW += wc; totC += cc;
      }
      if (files.length > 1) {
        const parts = [];
        if (doLines) parts.push(String(totL));
        if (doWords) parts.push(String(totW));
        if (doChars) parts.push(String(totC));
        parts.push('total');
        out.push(parts.join('  '));
      }
      return ok(out.join('\n'));
    },
    head: (ctx) => {
      const term = ctx.term;
      let n = 10;
      const args = ctx.args.slice();
      if (args[0] === '-n') { n = parseInt(args[1], 10) || 10; args.splice(0, 2); }
      const file = args[0];
      let content = '';
      if (file) {
        const node = term.getNode(term.normalizePath(file));
        if (!node || node.type !== 'file') return err('head: cannot open \'' + file + '\' for reading: No such file or directory');
        content = node.content || '';
      } else {
        content = ctx.stdin || '';
      }
      const lines = content.split('\n');
      return ok(lines.slice(0, n).join('\n'));
    },
    tail: (ctx) => {
      const term = ctx.term;
      let n = 10;
      const args = ctx.args.slice();
      if (args[0] === '-n') { n = parseInt(args[1], 10) || 10; args.splice(0, 2); }
      const file = args[0];
      let content = '';
      if (file) {
        const node = term.getNode(term.normalizePath(file));
        if (!node || node.type !== 'file') return err('tail: cannot open \'' + file + '\' for reading: No such file or directory');
        content = node.content || '';
      } else {
        content = ctx.stdin || '';
      }
      const lines = content.split('\n');
      return ok(lines.slice(-n).join('\n'));
    },
    grep: (ctx) => {
      const term = ctx.term;
      if (!ctx.args.length) return err('grep: missing pattern');
      const pattern = ctx.args[0];
      const files = ctx.args.slice(1);
      let re;
      try { re = new RegExp(pattern); } catch (e) { return err('grep: invalid pattern'); }
      const search = (content, name) => {
        return content.split('\n').filter(line => re.test(line)).map(line => name ? name + ':' + line : line).join('\n');
      };
      if (!files.length) {
        return ok(search(ctx.stdin || '', ''));
      }
      const out = [];
      for (const f of files) {
        const node = term.getNode(term.normalizePath(f));
        if (!node || node.type !== 'file') return err('grep: ' + f + ': No such file or directory');
        const r = search(node.content || '', files.length > 1 ? f : '');
        if (r) out.push(r);
      }
      return ok(out.join('\n'));
    },
    find: (ctx) => {
      const term = ctx.term;
      const start = ctx.args[0] || '.';
      const nameArg = ctx.args.includes('-name') ? ctx.args[ctx.args.indexOf('-name') + 1] : null;
      const segs = term.normalizePath(start);
      const root = term.getNode(segs);
      if (!root || root.type !== 'dir') return err('find: \'' + start + '\': No such file or directory');
      const results = [];
      function walk(node, path) {
        results.push(path);
        if (node.type === 'dir') {
          for (const k of Object.keys(node.children)) walk(node.children[k], path === '/' ? '/' + k : path + '/' + k);
        }
      }
      walk(root, term.pathString(segs));
      let filtered = results;
      if (nameArg) {
        const re = new RegExp('^' + nameArg.replace(/\*/g, '.*').replace(/\?/g, '.') + '$');
        filtered = results.filter(p => re.test(p.split('/').pop()));
      }
      return ok(filtered.join('\n'));
    },
    tree: (ctx) => {
      const term = ctx.term;
      const start = ctx.args[0] || '.';
      const segs = term.normalizePath(start);
      const root = term.getNode(segs);
      if (!root || root.type !== 'dir') return err('tree: \'' + start + '\': No such file or directory');
      const lines = [];
      function walk(node, prefix, name) {
        lines.push(prefix + name);
        if (node.type === 'dir') {
          const keys = Object.keys(node.children).sort();
          keys.forEach((k, i) => {
            const last = i === keys.length - 1;
            walk(node.children[k], prefix + (last ? '└── ' : '├── '), k);
          });
        }
      }
      walk(root, '', start === '.' ? '.' : start);
      return ok(lines.join('\n'));
    },
    neofetch: (ctx) => {
      const term = ctx.term;
      const art = [
        '        .--.',
        '       |o_o |',
        '       |:_/ |',
        '      //   \\ \\',
        '     (|     | )',
        '    /\'\\_   _/`\\',
        '    \\___)=(___/',
      ];
      const info = [
        term.user + '@' + term.hostname,
        '-----------',
        'OS: Terminal iPhone 1.0',
        'Shell: ' + (term.env.SHELL || '/bin/sh'),
        'Terminal: web',
        'CPU: ' + (typeof navigator !== 'undefined' ? navigator.hardwareConcurrency || '?' : '?') + ' cores',
        'Memory: n/a',
        'Disk: virtual',
      ];
      const out = [];
      const max = Math.max(art.length, info.length);
      for (let i = 0; i < max; i++) {
        out.push((art[i] || '').padEnd(20) + (info[i] || ''));
      }
      return ok(out.join('\n'));
    },
  };

  // ---- Extended environment: Linux / package manager / dev tools / AI CLIs ----
  const AVAILABLE_PACKAGES = {
    'coreutils': { version: '9.4', desc: 'GNU core utilities' },
    'bash': { version: '5.2.21', desc: 'GNU Bourne Again SHell' },
    'nodejs': { version: '20.11.0', desc: 'Node.js JavaScript runtime' },
    'npm': { version: '10.2.4', desc: 'Node package manager' },
    'git': { version: '2.43.0', desc: 'Fast, scalable, distributed revision control' },
    'python3': { version: '3.11.7', desc: 'Python 3 interpreter' },
    'build-essential': { version: '12.10', desc: 'Compilers and build tools' },
    'curl': { version: '8.4.0', desc: 'Transfer data from/to a server' },
    'wget': { version: '1.21.4', desc: 'Network downloader' },
    'nano': { version: '7.2', desc: 'Small, friendly text editor' },
    'vim': { version: '9.1', desc: 'Vi IMproved text editor' },
    'openssh': { version: '9.3p1', desc: 'OpenSSH client and server' },
    'tar': { version: '1.35', desc: 'Tape archiver' },
    'zip': { version: '3.0', desc: 'Zip archive tool' },
    'unzip': { version: '6.0', desc: 'Unzip archive tool' },
    'make': { version: '4.3', desc: 'GNU make' },
    'gcc': { version: '13.2.0', desc: 'GNU C compiler' },
    'g++': { version: '13.2.0', desc: 'GNU C++ compiler' },
    'rustc': { version: '1.75.0', desc: 'Rust compiler' },
    'cargo': { version: '1.75.0', desc: 'Rust package manager' },
    'go': { version: '1.21.5', desc: 'Go compiler' },
    'java': { version: '21.0.1', desc: 'Java runtime' },
    'docker': { version: '24.0.7', desc: 'Container runtime' },
    'claude-code': { version: '1.0.0', desc: 'Claude Code AI CLI' },
    'opencode': { version: '1.0.0', desc: 'OpenCode AI CLI' },
    'aider': { version: '0.60.0', desc: 'Aider AI coding assistant' },
    'codex': { version: '1.0.0', desc: 'OpenAI Codex CLI' },
    'gemini-cli': { version: '1.0.0', desc: 'Google Gemini CLI' },
  };

  function ensureEnv(term) {
    if (!term.installedPackages) {
      term.installedPackages = new Set(Object.keys(AVAILABLE_PACKAGES));
    }
    if (!term.availablePackages) term.availablePackages = AVAILABLE_PACKAGES;
  }

  function evalJs(code) {
    const logs = [];
    const fakeConsole = {
      log: (...a) => logs.push(a.map(x => (x === undefined ? '' : String(x))).join(' ')),
      error: (...a) => logs.push(a.map(x => (x === undefined ? '' : String(x))).join(' ')),
      warn: (...a) => logs.push(a.map(x => (x === undefined ? '' : String(x))).join(' ')),
      info: (...a) => logs.push(a.map(x => (x === undefined ? '' : String(x))).join(' ')),
    };
    try {
      const fn = new Function('console', code);
      const res = fn(fakeConsole);
      if (res !== undefined) logs.push(String(res));
      return { ok: true, out: logs.join('\n') };
    } catch (e) {
      return { ok: false, out: (e && e.message) ? e.message : String(e) };
    }
  }

  const SIMPLE_VERSIONS = {
    node: 'v20.11.0', npm: '10.2.4', npx: '10.2.4', yarn: '1.22.21', pnpm: '8.12.1', corepack: '0.24.0',
    python: 'Python 3.11.7', python2: 'Python 2.7.18', python3: 'Python 3.11.7', pip: 'pip 23.3.1', pip3: 'pip 23.3.1',
    gcc: 'gcc (Ubuntu 13.2.0) 13.2.0', 'g++': 'g++ (Ubuntu 13.2.0) 13.2.0', cc: 'cc (Ubuntu 13.2.0) 13.2.0',
    clang: 'Ubuntu clang version 17.0.2', make: 'GNU Make 4.3', cmake: 'cmake version 3.27.7', rustc: 'rustc 1.75.0', cargo: 'cargo 1.75.0',
    go: 'go version go1.21.5 linux/arm64', java: 'openjdk 21.0.1 2023-10-17', javac: 'javac 21.0.1', mvn: 'Apache Maven 3.9.6', gradle: 'Gradle 8.5',
    curl: 'curl 8.4.0 (aarch64-pc-linux-gnu) libcurl/8.4.0', wget: 'GNU Wget 1.21.4', ssh: 'OpenSSH_9.3p1, OpenSSL 3.0.10',
    scp: 'OpenSSH_9.3p1', sftp: 'OpenSSH_9.3p1', rsync: 'rsync  version 3.2.7',
    nano: 'GNU nano, version 7.2', vim: 'VIM - Vi IMproved 9.1', vi: 'VIM - Vi IMproved 9.1', emacs: 'GNU Emacs 29.1',
    tar: 'tar (GNU tar) 1.35', zip: 'Zip 3.0', unzip: 'UnZip 6.00', gzip: 'gzip 1.12', bzip2: 'bzip2 1.0.8', xz: 'xz (XZ Utils) 5.4.4', '7z': '7-Zip 23.01',
    docker: 'Docker version 24.0.7, build afdd53b', podman: 'podman version 4.7.2', kubectl: 'v1.29.0', helm: 'v3.13.3',
    systemctl: 'systemd 255 (255.4-1ubuntu1)', service: 'service (Ubuntu 22.04)', journalctl: 'systemd 255',
    ip: 'iproute2 6.1.0', ifconfig: 'net-tools 2.10', ping: 'iputils-ping 20221126', netstat: 'net-tools 2.10', ss: 'ss (iproute2 6.1.0)',
    sudo: 'sudo 1.9.15p5', su: 'su (util-linux 2.39.3)', id: 'uid=1000(iphone) gid=1000(iphone)', groups: 'iphone sudo',
    chmod: '', chown: '', chgrp: '', ln: '', stat: 'stat (GNU coreutils) 9.4', du: 'du (GNU coreutils) 9.4', df: 'df (GNU coreutils) 9.4',
    free: 'free (procps-ng) 4.0.4', top: 'top (procps-ng) 4.0.4', ps: 'ps (procps-ng) 4.0.4', kill: '', killall: '', pkill: '',
    less: 'less 643', more: 'more from util-linux 2.39.3', sort: 'sort (GNU coreutils) 9.4', uniq: 'uniq (GNU coreutils) 9.4',
    cut: 'cut (GNU coreutils) 9.4', awk: 'GNU Awk 5.2.2', sed: 'sed (GNU sed) 4.9', tr: 'tr (GNU coreutils) 9.4', xargs: 'xargs (GNU findutils) 4.9.0',
    locate: 'mlocate 0.26', file: 'file-5.45', strings: 'GNU strings 2.40', hexdump: 'hexdump (util-linux 2.39.3)', xxd: 'xxd 1.10',
    alias: '', unalias: '', source: '', bash: 'GNU bash, version 5.2.21', sh: 'dash 0.5.12', zsh: 'zsh 5.9', fish: 'fish 3.7.0',
    man: 'man 2.12.0', info: 'texinfo 7.1', tmux: 'tmux 3.3a', screen: 'Screen 4.09.01', openssl: 'OpenSSL 3.0.10', gpg: 'gpg (GnuPG) 2.4.3',
    sqlite3: '3.44.2 2023-11-24', 'redis-cli': 'redis-cli 7.2.3', psql: 'psql (PostgreSQL) 16.1', mysql: 'mysql Ver 8.2.0', mongo: 'mongosh 2.1.1',
    code: '1.85.0', 'lsb_release': 'lsb_release 11.1.0', hostnamectl: 'systemd 255', timedatectl: 'systemd 255', neofetch: 'neofetch 7.1.0',
    claude: 'claude 1.0.0', opencode: 'opencode 1.0.0', aider: 'aider 0.60.0', codex: 'codex 1.0.0', gemini: 'gemini 1.0.0', copilot: 'copilot 1.0.0',
    cline: 'cline 1.0.0', 'gemini-cli': 'gemini 1.0.0', 'claude-code': 'claude 1.0.0',
  };

  function makeSimple(name, ver) {
    return (ctx) => {
      const term = ctx.term; ensureEnv(term);
      if (ctx.args.includes('--version') || ctx.args.includes('-v') || ctx.args.includes('-V') || ctx.args.includes('version') || ctx.args.includes('--versions')) {
        return ok(ver || name + ' 1.0.0');
      }
      if (ctx.args.includes('--help') || ctx.args.includes('-h') || ctx.args.includes('help')) {
        return ok('Usage: ' + name + ' [options] [args]\n' + name + ' - command available in Terminal iPhone Linux environment.');
      }
      // node eval support
      if (name === 'node') {
        if (ctx.args.includes('-e') || ctx.args.includes('--eval')) {
          const idx = ctx.args.findIndex(a => a === '-e' || a === '--eval');
          const code = ctx.args[idx + 1] || '';
          const r = evalJs(code);
          if (!r.ok) return err(r.out);
          return ok(r.out);
        }
        const file = ctx.args.find(a => !a.startsWith('-'));
        if (file) {
          const n = term.getNode(term.normalizePath(file));
          if (!n || n.type !== 'file') return err('node: ' + file + ': No such file or directory');
          const r = evalJs(n.content || '');
          if (!r.ok) return err(r.out);
          return ok(r.out);
        }
        return ok('Welcome to Node.js ' + (ver || '') + '.\nType ".help" for more information.');
      }
      // python run support
      if (name === 'python' || name === 'python3' || name === 'python2') {
        const file = ctx.args.find(a => !a.startsWith('-'));
        if (file) {
          const n = term.getNode(term.normalizePath(file));
          if (!n || n.type !== 'file') return err(name + ': can\'t open file \'' + file + '\': No such file or directory');
          return ok('[python] executed ' + file);
        }
        if (ctx.args.includes('-c')) {
          const idx = ctx.args.indexOf('-c');
          return ok(ctx.args[idx + 1] || '');
        }
        return ok('Python ' + (ver || '').replace('Python ', '') + ' (default)');
      }
      // npm
      if (name === 'npm') {
        const sub = ctx.args[0];
        if (sub === 'install' || sub === 'i' || sub === 'add') {
          const pkgs = ctx.args.slice(1).filter(a => !a.startsWith('-'));
          return ok(pkgs.length ? 'added ' + pkgs.length + ' package, and audited 1 package in 1s\nfound 0 vulnerabilities' : 'up to date, audited 1 package in 1s\nfound 0 vulnerabilities');
        }
        if (sub === 'run') return ok('> ' + (ctx.args[1] || 'script') + '\n> echo ok');
        if (sub === 'init') return ok('Wrote to ' + term.pathString() + '/package.json');
        if (sub === 'test' || sub === 'start') return ok('> ' + sub + '\necho ok');
        if (sub === 'list' || sub === 'ls') return ok(term.user + '@1.0.0 ' + term.pathString());
        if (sub === 'uninstall' || sub === 'remove') return ok('removed ' + (ctx.args[1] || 'package'));
        if (!sub) return ok('Usage: npm <command>\n\nnpm commands: install, run, init, test, start, list, uninstall');
        return ok('npm ' + sub + ': ok');
      }
      // npx
      if (name === 'npx') {
        const cmd = ctx.args[0];
        if (!cmd) return ok('npx: need a command to run');
        if (Terminal.commands[cmd]) {
          const c2 = Object.assign({}, ctx, { args: ctx.args.slice(1) });
          return Terminal.commands[cmd](c2);
        }
        return ok('npx: executing ' + cmd);
      }
      // pip
      if (name === 'pip' || name === 'pip3') {
        const sub = ctx.args[0];
        if (sub === 'install') return ok('Successfully installed ' + (ctx.args.slice(1).join(' ') || 'requirements'));
        if (sub === 'list') return ok('Package    Version\n---------- -------\npip        23.3.1');
        if (sub === 'uninstall') return ok('Successfully uninstalled ' + (ctx.args[1] || 'package'));
        if (!sub) return ok('Usage: pip <command>');
        return ok('');
      }
      // make
      if (name === 'make') {
        if (ctx.args.includes('-v') || ctx.args.includes('--version')) return ok('GNU Make 4.3');
        return ok('make: Nothing to be done for \'all\'.');
      }
      // tar
      if (name === 'tar') {
        if (ctx.args.includes('--version')) return ok('tar (GNU tar) 1.35');
        return ok('');
      }
      // ssh
      if (name === 'ssh') {
        if (ctx.args.includes('-V')) return ok('OpenSSH_9.3p1, OpenSSL 3.0.10');
        const host = ctx.args[ctx.args.length - 1];
        return err('ssh: connect to host ' + host + ' port 22: Connection refused');
      }
      // curl
      if (name === 'curl') {
        if (ctx.args.includes('--version') || ctx.args.includes('-V')) return ok('curl 8.4.0 (aarch64) libcurl/8.4.0');
        const url = ctx.args.find(a => !a.startsWith('-'));
        const oIdx = ctx.args.indexOf('-o');
        const outFile = oIdx >= 0 ? ctx.args[oIdx + 1] : (ctx.args.includes('-O') ? (url ? url.split('/').pop() : null) : null);
        if (outFile) {
          const segs = term.normalizePath(outFile);
          const fname = segs[segs.length - 1];
          const parent = term.getNode(segs.slice(0, -1));
          if (parent && parent.type === 'dir') parent.children[fname] = { type: 'file', content: 'OK\n' };
        }
        if (url && !outFile) return ok('OK');
        return ok('');
      }
      // wget
      if (name === 'wget') {
        if (ctx.args.includes('--version') || ctx.args.includes('-V')) return ok('GNU Wget 1.21.4');
        const url = ctx.args.find(a => !a.startsWith('-'));
        const fname = url ? url.split('/').pop() : 'index.html';
        const segs = term.normalizePath(fname);
        const parent = term.getNode(segs.slice(0, -1));
        if (parent && parent.type === 'dir') parent.children[segs[segs.length-1]] = { type: 'file', content: 'OK\n' };
        return ok('saved [' + fname + ']');
      }
      // docker
      if (name === 'docker') {
        if (ctx.args.includes('--version')) return ok('Docker version 24.0.7, build afdd53b');
        if (ctx.args[0] === 'ps') return ok('CONTAINER ID   IMAGE   COMMAND   CREATED   STATUS   PORTS   NAMES');
        if (ctx.args[0] === 'images') return ok('REPOSITORY   TAG   IMAGE ID   CREATED   SIZE');
        return ok('Usage: docker [OPTIONS] COMMAND');
      }
      // systemctl
      if (name === 'systemctl') {
        if (ctx.args.includes('--version')) return ok('systemd 255 (255.4-1ubuntu1)');
        if (ctx.args[0] === 'status') return ok('● ' + (ctx.args[1] || 'service') + ' - active (running)');
        if (ctx.args[0] === 'start' || ctx.args[0] === 'restart') return ok('');
        return ok('');
      }
      // git handled separately
      // default
      return ok('');
    };
  }

  // git command
  const gitCmd = (ctx) => {
    const term = ctx.term; ensureEnv(term);
    const sub = ctx.args[0];
    if (!sub) return ok('usage: git [--version] <command> [<args>]');
    if (sub === '--version' || sub === '-v') return ok('git version 2.43.0');
    if (sub === 'init') {
      const dir = ctx.args[1] || '.';
      const segs = term.normalizePath(dir);
      const node = term.getNode(segs);
      if (node && node.type === 'dir') {
        if (!node.children['.git']) node.children['.git'] = { type: 'dir', children: {} };
      }
      return ok('Initialized empty Git repository in ' + term.pathString(segs) + '/.git/');
    }
    if (sub === 'clone') {
      const url = ctx.args[1] || '';
      const dirName = ctx.args[2] || (url.split('/').pop() || 'repo').replace(/\.git$/, '') || 'repo';
      const segs = term.normalizePath(dirName);
      const parent = term.getNode(segs.slice(0, -1));
      if (parent && parent.type === 'dir') {
        if (!parent.children[segs[segs.length-1]]) parent.children[segs[segs.length-1]] = { type: 'dir', children: {} };
        parent.children[segs[segs.length-1]].children['README.md'] = { type: 'file', content: '# ' + dirName + '\n' };
        parent.children[segs[segs.length-1]].children['.git'] = { type: 'dir', children: {} };
      }
      return ok('Cloning into \'' + dirName + '\'...\nremote: Enumerating objects: 3, done.\ndone.');
    }
    if (sub === 'status') return ok('On branch main\nYour branch is up to date with \'origin/main\'.\n\nnothing to commit, working tree clean');
    if (sub === 'add') return ok('');
    if (sub === 'commit') {
      const mIdx = ctx.args.indexOf('-m');
      const msg = mIdx >= 0 ? ctx.args[mIdx + 1] : 'update';
      return ok('[main (root-commit) a1b2c3d] ' + msg + '\n 1 file changed, 1 insertion(+)');
    }
    if (sub === 'log') return ok('commit a1b2c3d (HEAD -> main)\nAuthor: ' + term.user + ' <' + term.user + '@localhost>\nDate:   ' + new Date().toDateString() + '\n\n    Initial commit');
    if (sub === 'branch') return ok('* main');
    if (sub === 'checkout') return ok('Switched to branch \'' + (ctx.args[1] || 'main') + '\'');
    if (sub === 'switch') return ok('Switched to branch \'' + (ctx.args[1] || 'main') + '\'');
    if (sub === 'pull') return ok('Already up to date.');
    if (sub === 'push') return ok('Everything up-to-date');
    if (sub === 'diff') return ok('');
    if (sub === 'remote') return ok('origin\thttps://github.com/user/repo.git (fetch)\norigin\thttps://github.com/user/repo.git (push)');
    if (sub === 'config') return ok('');
    if (sub === 'fetch') return ok('From https://github.com/user/repo\n * branch main -> FETCH_HEAD');
    if (sub === 'merge') return ok('Already up to date.');
    if (sub === 'reset') return ok('');
    if (sub === 'stash') return ok('No local changes to save');
    return ok('git: \'' + sub + '\' is not a git command. See \'git --help\'.');
  };

  // apt / pkg
  const pkgCmd = (ctx) => {
    const term = ctx.term; ensureEnv(term);
    const sub = ctx.args[0];
    if (!sub || sub === 'help' || sub === '--help') return ok('Usage: pkg {update|install|remove|search|list|show} <pkg>...');
    if (sub === 'update' || sub === 'upgrade') {
      return ok('Hit:1 http://ports.ubuntu.com ubuntu InRelease\nReading package lists... Done\nAll packages are up to date.');
    }
    if (sub === 'install') {
      const pkgs = ctx.args.slice(1).filter(a => !a.startsWith('-'));
      if (!pkgs.length) return err('pkg install: missing package name');
      const out = [];
      for (const p of pkgs) {
        if (!term.availablePackages[p]) term.availablePackages[p] = { version: '1.0.0', desc: p };
        term.installedPackages.add(p);
        out.push('Reading package lists... Done\nBuilding dependency tree... Done\nSetting up ' + p + ' (' + (term.availablePackages[p].version || '1.0.0') + ') ...\n' + p + ' installed successfully.');
      }
      return ok(out.join('\n'));
    }
    if (sub === 'remove' || sub === 'uninstall' || sub === 'purge') {
      const pkgs = ctx.args.slice(1).filter(a => !a.startsWith('-'));
      for (const p of pkgs) term.installedPackages.delete(p);
      return ok(pkgs.map(p => 'Removing ' + p + '...\n' + p + ' removed.').join('\n') || '');
    }
    if (sub === 'search') {
      const q = ctx.args[1] || '';
      const names = Object.keys(term.availablePackages).filter(n => !q || n.includes(q));
      return ok(names.map(n => n + ' - ' + (term.availablePackages[n].desc || '')).join('\n'));
    }
    if (sub === 'list') {
      const installed = ctx.args.includes('--installed') || ctx.args.includes('-i');
      const names = installed ? [...term.installedPackages] : Object.keys(term.availablePackages);
      return ok(names.sort().join('\n') || 'No packages.');
    }
    if (sub === 'show') {
      const p = ctx.args[1];
      if (!p || !term.availablePackages[p]) return err('pkg show: package not found: ' + (p || ''));
      return ok('Package: ' + p + '\nVersion: ' + (term.availablePackages[p].version || '1.0.0') + '\nDescription: ' + (term.availablePackages[p].desc || ''));
    }
    return err('pkg: unknown subcommand: ' + sub);
  };

  const aptCmd = (ctx) => {
    const args = ctx.args.slice();
    if (args[0] === '--version') return ok('apt 2.7.14 (aarch64)');
    if (args[0] === 'update' || args[0] === 'upgrade') { ctx.args = ['update']; return pkgCmd(ctx); }
    if (args[0] === 'install') { ctx.args = ['install'].concat(args.slice(1)); return pkgCmd(ctx); }
    if (args[0] === 'remove' || args[0] === 'purge') { ctx.args = ['remove'].concat(args.slice(1)); return pkgCmd(ctx); }
    if (args[0] === 'search') { ctx.args = ['search'].concat(args.slice(1)); return pkgCmd(ctx); }
    if (args[0] === 'list') { ctx.args = ['list'].concat(args.slice(1)); return pkgCmd(ctx); }
    if (args[0] === 'show') { ctx.args = ['show'].concat(args.slice(1)); return pkgCmd(ctx); }
    if (!args.length) return ok('Usage: apt [update|install|remove|search|list|show] ...');
    ctx.args = args;
    return ok('apt: ok');
  };

  const dpkgCmd = (ctx) => {
    if (ctx.args.includes('--version')) return ok('dpkg 1.22.6 (aarch64)');
    if (ctx.args.includes('-l') || ctx.args.includes('--list')) {
      const term = ctx.term; ensureEnv(term);
      return ok([...term.installedPackages].sort().map(p => 'ii  ' + p + '  ' + (term.availablePackages[p]?.version || '1.0.0') + '  ' + (term.availablePackages[p]?.desc || '')).join('\n'));
    }
    return ok('Usage: dpkg {-l|--list} | --version');
  };

  // which / type / command
  const whichCmd = (ctx) => {
    const term = ctx.term; ensureEnv(term);
    const names = ctx.args.filter(a => !a.startsWith('-'));
    const out = []; let code = 0; let stderr = '';
    for (const n of names) {
      if (Terminal.commands[n]) out.push('/usr/bin/' + n);
      else { code = 1; stderr += 'which: no ' + n + ' in PATH\n'; }
    }
    if (!out.length) return { stdout: '', stderr: stderr.trim(), code: 1, clear: false };
    return { stdout: out.join('\n'), stderr: stderr.trim(), code: code, clear: false };
  };
  const typeCmd = (ctx) => {
    const term = ctx.term; ensureEnv(term);
    const names = ctx.args.filter(a => !a.startsWith('-'));
    const out = [];
    for (const n of names) {
      if (Terminal.commands[n]) out.push(n + ' is /usr/bin/' + n);
      else out.push(n + ': not found');
    }
    return ok(out.join('\n'));
  };
  const commandCmd = (ctx) => {
    const term = ctx.term;
    if (ctx.args[0] === '-v' || ctx.args[0] === '-V') {
      const name = ctx.args[1];
      if (name && Terminal.commands[name]) return ok('/usr/bin/' + name);
      return err(name + ': not found');
    }
    const line = ctx.args.join(' ');
    return term.exec(line);
  };

  // sudo / sh / source
  const sudoCmd = (ctx) => ctx.term.exec(ctx.args.join(' '));
  const shCmd = (ctx) => {
    if (ctx.args[0] === '-c') return ctx.term.exec(ctx.args.slice(1).join(' '));
    return ok('');
  };
  const sourceCmd = (ctx) => {
    const term = ctx.term;
    const file = ctx.args[0];
    if (!file) return err('source: filename argument required');
    const node = term.getNode(term.normalizePath(file));
    if (!node || node.type !== 'file') return err('source: ' + file + ': No such file or directory');
    const lines = (node.content || '').split('\n');
    let last = ok('');
    for (const l of lines) { if (l.trim()) last = term.exec(l); }
    return last;
  };

  // uname / lsb_release
  const unameCmd = (ctx) => {
    const args = ctx.args;
    if (!args.length || args.includes('-s')) return ok('Linux');
    if (args.includes('-a')) return ok('Linux ' + ctx.term.hostname + ' 5.15.0-105-generic #115-Ubuntu SMP Mon Apr 15 16:00:00 UTC 2024 aarch64 GNU/Linux');
    if (args.includes('-m')) return ok('aarch64');
    if (args.includes('-r')) return ok('5.15.0-105-generic');
    if (args.includes('-n')) return ok(ctx.term.hostname);
    if (args.includes('-o')) return ok('GNU/Linux');
    if (args.includes('-p')) return ok('aarch64');
    return ok('Linux');
  };
  const lsbCmd = (ctx) => {
    if (ctx.args.includes('-a')) return ok('Distributor ID: Ubuntu\nDescription: Ubuntu 22.04.4 LTS\nRelease: 22.04\nCodename: jammy');
    if (ctx.args.includes('-d')) return ok('Description: Ubuntu 22.04.4 LTS');
    if (ctx.args.includes('-r')) return ok('Release: 22.04');
    if (ctx.args.includes('-i')) return ok('Distributor ID: Ubuntu');
    return ok('Ubuntu');
  };
  const hostnamectlCmd = (ctx) => ok(' Static hostname: ' + ctx.term.hostname + '\n       Icon name: computer\n      Operating System: Ubuntu 22.04.4 LTS\n      Kernel: Linux 5.15.0-105-generic\n    Architecture: arm64');
  const timedatectlCmd = (ctx) => ok('               Local time: ' + new Date().toString() + '\n           Universal time: ' + new Date().toUTCString() + '\n                 RTC time: n/a\n                Time zone: UTC\n     System clock synchronized: yes\n              NTP service: active');
  const ipCmd = (ctx) => {
    if (ctx.args[0] === 'addr' || ctx.args[0] === 'a') return ok('1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536\n    inet 127.0.0.1/8 scope host lo\n2: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500\n    inet 192.168.1.42/24 brd 192.168.1.255 scope global wlan0');
    if (ctx.args[0] === 'route') return ok('default via 192.168.1.1 dev wlan0\n192.168.1.0/24 dev wlan0 proto kernel scope link src 192.168.1.42');
    return ok('Usage: ip {addr|route|link}');
  };
  const ifconfigCmd = (ctx) => ok('wlan0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500\n        inet 192.168.1.42  netmask 255.255.255.0  broadcast 192.168.1.255');
  const pingCmd = (ctx) => {
    const host = ctx.args[ctx.args.length - 1] || 'localhost';
    return ok('PING ' + host + ' (127.0.0.1): 56 data bytes\n64 bytes from 127.0.0.1: icmp_seq=0 ttl=64 time=0.1 ms\n\n--- ' + host + ' ping statistics ---\n1 packets transmitted, 1 received, 0% packet loss');
  };
  const psCmd = (ctx) => ok('PID TTY          TIME CMD\n  1 ?        00:00:01 init\n  2 ?        00:00:00 kthreadd\n100 pts/0    00:00:00 sh\n101 pts/0    00:00:00 node');
  const dfCmd = (ctx) => ok('Filesystem     1K-blocks   Used Available Use% Mounted on\n/dev/disk1s1  62914560 12345678  50568882  20% /');
  const freeCmd = (ctx) => ok('              total        used        free      shared  buff/cache   available\nMem:        4194304     1048576     2097152       65536     1048576     3000000\nSwap:       1048576           0     1048576');
  const topCmd = (ctx) => ok('top - up to date\nTasks: 4 total\n%Cpu(s):  1.0 us\nMiB Mem: 4096.0 total');
  const idCmd = (ctx) => ok('uid=1000(' + ctx.term.user + ') gid=1000(' + ctx.term.user + ') groups=1000(' + ctx.term.user + '),27(sudo)');
  const whoamiCmd = (ctx) => ok(ctx.term.user);
  const editors = (ctx) => {
    const file = ctx.args.find(a => !a.startsWith('-'));
    const term = ctx.term;
    if (file) {
      const segs = term.normalizePath(file);
      const name = segs[segs.length - 1];
      const parent = term.getNode(segs.slice(0, -1));
      if (parent && parent.type === 'dir' && !parent.children[name]) {
        parent.children[name] = { type: 'file', content: '' };
      }
      return ok('Opened ' + file + ' in editor (simulated).');
    }
    return ok('Usage: editor <file>');
  };
  const sshCmd = (ctx) => {
    if (ctx.args.includes('-V')) return ok('OpenSSH_9.3p1, OpenSSL 3.0.10');
    const host = ctx.args[ctx.args.length - 1] || '';
    return err('ssh: connect to host ' + host + ' port 22: Connection refused');
  };
  const scpCmd = (ctx) => ok('scp: transferred (simulated)');
  const rsyncCmd = (ctx) => ok('rsync: done (simulated)');
  const dockerCmd = (ctx) => {
    if (ctx.args.includes('--version')) return ok('Docker version 24.0.7, build afdd53b');
    if (ctx.args[0] === 'ps') return ok('CONTAINER ID   IMAGE   COMMAND   CREATED   STATUS   PORTS   NAMES');
    if (ctx.args[0] === 'images') return ok('REPOSITORY   TAG   IMAGE ID   CREATED   SIZE');
    if (ctx.args[0] === 'run') return ok('container started (simulated)');
    return ok('Usage: docker [OPTIONS] COMMAND');
  };
  const systemctlCmd = (ctx) => {
    if (ctx.args.includes('--version')) return ok('systemd 255 (255.4-1ubuntu1)');
    if (ctx.args[0] === 'status') return ok('● ' + (ctx.args[1] || 'service') + ' - active (running)');
    return ok('');
  };
  const tarCmd = (ctx) => {
    if (ctx.args.includes('--version')) return ok('tar (GNU tar) 1.35');
    return ok('');
  };
  const curlCmd = (ctx) => {
    if (ctx.args.includes('--version') || ctx.args.includes('-V')) return ok('curl 8.4.0 (aarch64) libcurl/8.4.0');
    const url = ctx.args.find(a => !a.startsWith('-'));
    const oIdx = ctx.args.indexOf('-o');
    const outFile = oIdx >= 0 ? ctx.args[oIdx + 1] : (ctx.args.includes('-O') ? (url ? url.split('/').pop() : null) : null);
    if (outFile) {
      const term = ctx.term;
      const segs = term.normalizePath(outFile);
      const parent = term.getNode(segs.slice(0, -1));
      if (parent && parent.type === 'dir') parent.children[segs[segs.length-1]] = { type: 'file', content: 'OK\n' };
    }
    if (url && !outFile) return ok('OK');
    return ok('');
  };
  const wgetCmd = (ctx) => {
    if (ctx.args.includes('--version') || ctx.args.includes('-V')) return ok('GNU Wget 1.21.4');
    const url = ctx.args.find(a => !a.startsWith('-'));
    const fname = url ? url.split('/').pop() : 'index.html';
    const term = ctx.term;
    const segs = term.normalizePath(fname);
    const parent = term.getNode(segs.slice(0, -1));
    if (parent && parent.type === 'dir') parent.children[segs[segs.length-1]] = { type: 'file', content: 'OK\n' };
    return ok('saved [' + fname + ']');
  };

  // AI CLI runners
  function aiRunner(name, ver) {
    return (ctx) => {
      const term = ctx.term; ensureEnv(term);
      if (ctx.args.includes('--version') || ctx.args.includes('-v')) return ok(ver);
      if (ctx.args.includes('--help') || ctx.args.includes('-h') || !ctx.args.length) {
        return ok(name + ' ' + ver + '\nUsage: ' + name + ' [options] [prompt]\nAI coding assistant available in Terminal iPhone Linux environment.');
      }
      return ok(name + ': ' + ctx.args.join(' ') + '\n(thinking...)\nDone.');
    };
  }

  const aiCmd = (ctx) => {
    const term = ctx.term; ensureEnv(term);
    if (!ctx.args.length) return ok('Available AI CLIs: claude, opencode, aider, codex, gemini, copilot\nUse: ai <cli> [args...] or run the CLI directly.');
    const name = ctx.args[0];
    if (Terminal.commands[name]) {
      const c2 = Object.assign({}, ctx, { args: ctx.args.slice(1) });
      return Terminal.commands[name](c2);
    }
    return err('ai: ' + name + ': command not found');
  };

  const bootstrapCmd = (ctx) => {
    const term = ctx.term;
    return ok([
      'Terminal iPhone Linux Environment',
      '================================',
      'Distro: Ubuntu 22.04 (aarch64)',
      'Node.js: ' + (SIMPLE_VERSIONS.node) + ' (via nvm, no APT repo needed)',
      'Package manager: pkg/apt (preconfigured mirrors)',
      'Installed AI CLIs: claude, opencode, aider, codex, gemini',
      '',
      'Quick start:',
      '  pkg update && pkg install nodejs git python3',
      '  npm install -g @anthropic-ai/claude-code',
      '  git clone <repo> && cd <repo>',
      '  nano file.js && node file.js',
    ].join('\n'));
  };

  const linuxCmd = bootstrapCmd;

  // Build command map extension
  const ext = {};
  // simple bins
  for (const [name, ver] of Object.entries(SIMPLE_VERSIONS)) {
    ext[name] = makeSimple(name, ver);
  }
  // overrides
  ext.git = gitCmd;
  ext.pkg = pkgCmd;
  ext.apt = aptCmd;
  ext['apt-get'] = aptCmd;
  ext.dpkg = dpkgCmd;
  ext.which = whichCmd;
  ext.type = typeCmd;
  ext.command = commandCmd;
  ext.sudo = sudoCmd;
  ext.sh = shCmd;
  ext.bash = shCmd;
  ext.source = sourceCmd;
  ext['.'] = sourceCmd;
  ext.uname = unameCmd;
  ext.lsb_release = lsbCmd;
  ext.hostnamectl = hostnamectlCmd;
  ext.timedatectl = timedatectlCmd;
  ext.ip = ipCmd;
  ext.ifconfig = ifconfigCmd;
  ext.ping = pingCmd;
  ext.ps = psCmd;
  ext.df = dfCmd;
  ext.free = freeCmd;
  ext.top = topCmd;
  ext.id = idCmd;
  ext.whoami = whoamiCmd;
  ext.nano = editors;
  ext.vim = editors;
  ext.vi = editors;
  ext.emacs = editors;
  ext.code = editors;
  ext.ssh = sshCmd;
  ext.scp = scpCmd;
  ext.rsync = rsyncCmd;
  ext.docker = dockerCmd;
  ext.podman = dockerCmd;
  ext.systemctl = systemctlCmd;
  ext.service = systemctlCmd;
  ext.tar = tarCmd;
  ext.curl = curlCmd;
  ext.wget = wgetCmd;
  ext.ai = aiCmd;
  ext.bootstrap = bootstrapCmd;
  ext.linux = linuxCmd;
  ext.setup = bootstrapCmd;
  ext.linuxenv = bootstrapCmd;
  ext.environment = bootstrapCmd;
  ext.envinfo = bootstrapCmd;
  ext.sysinfo = bootstrapCmd;
  ext.info = bootstrapCmd;
  ext.install = bootstrapCmd;
  ext.nodejs = ext.node;
  ext.js = ext.node;
  ext.py = ext.python3;
  // extra aliases / platform helpers
  for (const n of ['jailbreak','ios','iphone','procursus','sileo','cydia','nvm','fnm','volta','brew','homebrew']) {
    ext[n] = (ctx) => {
      const term = ctx.term; ensureEnv(term);
      if (ctx.args.includes('--version') || ctx.args.includes('-v')) return ok(n + ' 1.0.0');
      return ok(n + ': available in Terminal iPhone Linux environment. Run "bootstrap" for setup.');
    };
  }
  // AI CLIs
  ext.claude = aiRunner('claude', 'claude 1.0.0');
  ext.opencode = aiRunner('opencode', 'opencode 1.0.0');
  ext.aider = aiRunner('aider', 'aider 0.60.0');
  ext.codex = aiRunner('codex', 'codex 1.0.0');
  ext.gemini = aiRunner('gemini', 'gemini 1.0.0');
  ext.copilot = aiRunner('copilot', 'copilot 1.0.0');
  ext.cline = aiRunner('cline', 'cline 1.0.0');
  // aliases for ls etc already exist
  ext.aptget = aptCmd;

  Object.assign(Terminal.commands, ext);

  // update uname command in place (override existing)
  Terminal.commands.uname = unameCmd;

  if (typeof module !== 'undefined' && module.exports) module.exports = { Terminal, createFS, parseLine };
  if (typeof global !== 'undefined') global.TerminalCore = { Terminal, createFS, parseLine };
})(typeof globalThis !== 'undefined' ? globalThis : (typeof window !== 'undefined' ? window : this));
