(function () {
  'use strict';
  const { Terminal } = (window.TerminalCore || {});
  if (!Terminal) { console.error('TerminalCore not loaded'); return; }

  const term = new Terminal({ user: 'iphone' });
  const output = document.getElementById('output');
  const input = document.getElementById('input');
  const promptEl = document.getElementById('prompt');
  const terminal = document.getElementById('terminal');
  const btnClear = document.getElementById('btn-clear');

  let ctrlPending = false;
  let historyIndex = -1;
  let savedInput = '';

  function updatePrompt() {
    promptEl.textContent = term.prompt();
  }

  function appendHTML(html) {
    const div = document.createElement('div');
    div.className = 'line';
    div.innerHTML = html;
    output.appendChild(div);
    terminal.scrollTop = terminal.scrollHeight;
  }

  function appendText(text, cls) {
    if (text === '' || text == null) return;
    const div = document.createElement('div');
    div.className = 'line ' + (cls || 'out');
    // escape
    const pre = document.createElement('pre');
    pre.style.margin = '0';
    pre.style.whiteSpace = 'pre-wrap';
    pre.style.wordBreak = 'break-word';
    pre.textContent = text;
    div.appendChild(pre);
    output.appendChild(div);
    terminal.scrollTop = terminal.scrollHeight;
  }

  function runLine(line) {
    const echo = document.createElement('div');
    echo.className = 'line cmd';
    const p = document.createElement('span');
    p.className = 'prompt';
    p.textContent = term.prompt();
    const c = document.createElement('span');
    c.textContent = line;
    echo.appendChild(p);
    echo.appendChild(c);
    output.appendChild(echo);

    const result = term.exec(line);
    if (result.clear) {
      output.innerHTML = '';
    }
    if (result.stderr) appendText(result.stderr, 'err');
    if (result.stdout) appendText(result.stdout, 'out');
    terminal.scrollTop = terminal.scrollHeight;
    updatePrompt();
  }

  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      const line = input.value;
      input.value = '';
      historyIndex = -1;
      runLine(line);
      return;
    }
    if (e.key === 'Tab') {
      e.preventDefault();
      const val = input.value;
      const cands = term.complete(val);
      if (cands.length === 1) {
        // replace last token
        const idx = val.lastIndexOf(' ');
        const prefix = idx >= 0 ? val.slice(0, idx + 1) : '';
        input.value = prefix + cands[0];
      } else if (cands.length > 1) {
        appendText(cands.join('  '), 'out');
      }
      return;
    }
    if (e.key === 'ArrowUp') {
      e.preventDefault();
      if (historyIndex === -1) { savedInput = input.value; historyIndex = term.history.length - 1; }
      else if (historyIndex > 0) historyIndex--;
      if (historyIndex >= 0) input.value = term.history[historyIndex] || '';
      return;
    }
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      if (historyIndex === -1) return;
      historyIndex++;
      if (historyIndex >= term.history.length) {
        historyIndex = -1;
        input.value = savedInput;
      } else {
        input.value = term.history[historyIndex] || '';
      }
      return;
    }
    if (e.key === 'l' && (e.ctrlKey || ctrlPending)) {
      e.preventDefault();
      output.innerHTML = '';
      ctrlPending = false;
      return;
    }
    if (e.key === 'c' && (e.ctrlKey || ctrlPending)) {
      e.preventDefault();
      // echo ^C
      const echo = document.createElement('div');
      echo.className = 'line cmd';
      const p = document.createElement('span'); p.className='prompt'; p.textContent = term.prompt();
      const c = document.createElement('span'); c.textContent = input.value + '^C';
      echo.appendChild(p); echo.appendChild(c);
      output.appendChild(echo);
      input.value = '';
      ctrlPending = false;
      terminal.scrollTop = terminal.scrollHeight;
      return;
    }
    if (e.key === 'u' && (e.ctrlKey || ctrlPending)) {
      e.preventDefault();
      input.value = '';
      ctrlPending = false;
      return;
    }
    if (e.key === 'Control' ) {
      // ignore
    }
  });

  // toolbar handling
  document.querySelectorAll('#toolbar button').forEach(btn => {
    btn.addEventListener('click', () => {
      const key = btn.getAttribute('data-key');
      if (key === 'Control') { ctrlPending = true; btn.classList.add('active'); setTimeout(() => { ctrlPending = false; btn.classList.remove('active'); }, 2000); return; }
      if (key === 'Tab') {
        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Tab', bubbles: true }));
        input.focus();
        return;
      }
      if (key === 'Enter') {
        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
        input.focus();
        return;
      }
      if (key === 'Escape') {
        input.value = '';
        input.focus();
        return;
      }
      // arrows
      input.focus();
      if (key.startsWith('Arrow')) {
        // move cursor roughly by dispatching
        const ev = new KeyboardEvent('keydown', { key: key, bubbles: true });
        input.dispatchEvent(ev);
      }
    });
  });

  btnClear.addEventListener('click', () => { output.innerHTML = ''; });

  // focus input on terminal click
  terminal.addEventListener('click', () => input.focus());

  // initial
  appendText('Welcome to Terminal for iPhone. Type "help" for commands.', 'out');
  updatePrompt();
  input.focus();

  // register service worker
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('/sw.js').catch(() => {});
  }
})();
