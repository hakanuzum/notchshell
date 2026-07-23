/* ═══════════════════════════════════════════════
   SHELL EMULATOR — command handler & virtual FS
   kitty-style CLI: hakuke <command> [--flags]
   ═══════════════════════════════════════════════ */

window.MQ_SHELL = {

  completions: [
    'hakuke state','hakuke ls','hakuke toggle','hakuke show','hakuke hide',
    'hakuke new-tab','hakuke new-tab --title','hakuke close-tab','hakuke close-tab --match',
    'hakuke focus-tab','hakuke focus-tab --match',
    'hakuke split --horizontal','hakuke split --vertical',
    'hakuke close-pane','hakuke send-text','hakuke send-key',
    'hakuke launch','hakuke get-text','hakuke get-text --lines',
    'hakuke pin','hakuke unpin',
    'hakuke resize --width','hakuke resize --height',
    'hakuke settings','hakuke clear',
    'ls','pwd','whoami','echo','cat README.md','cat Package.swift','neofetch','clear','help',
    'fortune','cowsay','matrix','nmap','top','uptime','date','sl','brew install hakuke'
  ],

  // Virtual filesystem for cat
  files: {
    'README.md': [
      '\x1b[1m# hakuke\x1b[0m', '',
      '\x1b[90m> Quake-style drop-down terminal for macOS, powered by Ghostty.\x1b[0m', '',
      'One hotkey. Instant terminal. \x1b[36mOption+Space\x1b[0m slides it down from the top.', '',
      '\x1b[1m## Features\x1b[0m',
      '- GPU-accelerated (GhosttyKit Metal renderer)',
      '- Hotkey toggle from any app',
      '- Tabs & split panes',
      '- MCP server (17 tools)',
      '- Socket API at /tmp/hakuke.sock',
      '- Auto-updates via Sparkle'
    ],
    'Package.swift': [
      '\x1b[35mimport\x1b[0m PackageDescription', '',
      '\x1b[35mlet\x1b[0m package = \x1b[36mPackage\x1b[0m(',
      '    name: \x1b[31m"Hakuke"\x1b[0m,',
      '    platforms: [.\x1b[36mmacOS\x1b[0m(.\x1b[36mv14\x1b[0m)],',
      '    targets: [',
      '        .\x1b[36mexecutableTarget\x1b[0m(name: \x1b[31m"Hakuke"\x1b[0m, ...)',
      '    ]',
      ')'
    ],
  },

  // Neofetch art
  neofetch: [
    ['\x1b[32m                    \'c.          ', '\x1b[36muser\x1b[0m@\x1b[36mmacbook\x1b[0m'],
    ['\x1b[32m                 ,xNMM.          ', '\x1b[0m-----------'],
    ['\x1b[32m               .OMMMMo            ', '\x1b[36mOS:\x1b[0m macOS Sonoma 14.2'],
    ['\x1b[32m               OMMM0,             ', '\x1b[36mHost:\x1b[0m MacBook Pro (M3 Pro)'],
    ['\x1b[32m     .;loddo:\' loolloddol;.      ', '\x1b[36mShell:\x1b[0m zsh 5.9'],
    ['\x1b[32m   cKMMMMMMMMMMNWMMMMMMMMMM0:     ', '\x1b[36mTerminal:\x1b[0m hakuke 0.1.0'],
    ['\x1b[32m .KMMMMMMMMMMMMMMMMMMMMMMMWd.     ', '\x1b[36mCPU:\x1b[0m Apple M3 Pro'],
    ['\x1b[32m XMMMMMMMMMMMMMMMMMMMMMMMX.       ', '\x1b[36mMemory:\x1b[0m 18432 MiB'],
  ],

  lsOutput: ['Hakuke/', 'Package.swift', 'README.md', 'scripts/', 'vendor/', 'site/'],

  readLines: [
    'drwxr-xr-x  12 user staff  384 Mar  7 10:22 .',
    '-rw-r--r--   1 user staff 2048 Mar  7 10:20 Package.swift',
    '-rw-r--r--   1 user staff  890 Mar  7 09:30 README.md',
    'drwxr-xr-x   8 user staff  256 Mar  7 10:22 Hakuke',
    'drwxr-xr-x   4 user staff  128 Mar  7 09:15 scripts',
  ],

  validControlChars: ['c', 'd', 'z', 'l', 'u', 'a', 'e', 'k', 'w'],

  // Parse --flag value pairs from parts array
  parseFlags(parts) {
    const flags = {};
    const positional = [];
    for (let i = 0; i < parts.length; i++) {
      if (parts[i].startsWith('--')) {
        const key = parts[i].slice(2);
        // boolean flag if next is missing or another flag
        if (i + 1 >= parts.length || parts[i + 1].startsWith('--')) {
          flags[key] = true;
        } else {
          flags[key] = parts[++i];
        }
      } else {
        positional.push(parts[i]);
      }
    }
    return { flags, positional };
  },

  /**
   * Handle a command from any pane's shell.
   * @param {string} input — raw command string
   * @param {Terminal} terminal — xterm.js Terminal instance
   * @param {string} paneId — ID of the pane that ran the command
   * @param {object} ctx — app context
   */
  handleCmd(input, terminal, paneId, ctx) {
    const self = window.MQ_SHELL;
    const parts = input.split(/\s+/), cmd = parts[0];

    // Color helpers
    const G = '\x1b[32m', C = '\x1b[36m', Y = '\x1b[33m', R = '\x1b[31m';
    const D = '\x1b[90m', W = '\x1b[1m', N = '\x1b[0m';

    // ── Shell built-ins ──

    if (cmd === 'help') {
      terminal.writeln(W + 'hakuke' + N + ' — Quake-style terminal for macOS\r\n');
      terminal.writeln(D + '  COMMANDS' + N);
      const cmds = [
        ['state',                    'Show terminal state (visible, pinned, tabs, panes)'],
        ['ls',                       'List all tabs and panes'],
        ['toggle',                   'Toggle terminal visibility'],
        ['show / hide',              'Show or hide the terminal window'],
        ['new-tab [--title NAME]',   'Create a new tab'],
        ['close-tab [--match ID]',   'Close a tab (default: current)'],
        ['focus-tab --match ID',     'Focus a tab by ID'],
        ['split [--horizontal | --vertical]', 'Split the current pane'],
        ['close-pane',               'Close the current pane'],
        ['launch <cmd>',             'Run a command in the active pane'],
        ['send-text <text>',         'Send text to the active pane'],
        ['send-key <key>',           'Send Ctrl+key (c, d, z, l, ...)'],
        ['get-text [--lines N]',     'Read terminal output (default: 5 lines)'],
        ['pin / unpin',              'Pin or unpin above all windows'],
        ['resize [--width N] [--height N]', 'Set width/height percent'],
        ['settings',                 'Open the settings panel'],
        ['clear',                    'Clear the terminal buffer'],
      ];
      cmds.forEach(([c, d]) => terminal.writeln('  ' + C + ('hakuke ' + c).padEnd(40) + N + D + d + N));
      terminal.writeln('');
      terminal.writeln(D + '  SHELL' + N);
      const sh = [
        ['ls',          'List files'],
        ['pwd',         'Current directory'],
        ['whoami',      'Current user'],
        ['echo <text>', 'Echo text'],
        ['cat <file>',  'Show file contents'],
        ['neofetch',    'System info'],
        ['clear',       'Clear terminal'],
        ['help',        'Show this help'],
      ];
      sh.forEach(([c, d]) => terminal.writeln('  ' + C + c.padEnd(40) + N + D + d + N));
      return;
    }
    if (cmd === 'clear') { terminal.clear(); return; }
    if (cmd === 'ls' && parts[1] !== '--') { self.lsOutput.forEach(f => terminal.writeln(f.endsWith('/') ? '\x1b[34m' + f + '\x1b[0m' : f)); return; }
    if (cmd === 'pwd') { terminal.writeln('/Users/user/Projects/hakuke'); return; }
    if (cmd === 'whoami') { terminal.writeln('user'); return; }
    if (cmd === 'echo') { terminal.writeln(parts.slice(1).join(' ')); return; }
    if (cmd === 'cat') {
      const file = parts[1];
      if (!file) { terminal.writeln(R + 'Usage: cat <file>' + N); return; }
      if (self.files[file]) self.files[file].forEach(l => terminal.writeln(l));
      else terminal.writeln(R + 'cat: ' + file + ': No such file' + N);
      return;
    }
    if (cmd === 'neofetch') {
      self.neofetch.forEach(([a, b]) => terminal.writeln(a + b));
      return;
    }

    // ── Easter eggs ──

    if (cmd === 'claude') {
      const M = '\x1b[38;2;194;101;74m'; // Claude orange
      terminal.writeln('');
      terminal.writeln(M + ' \u2590\u259B\u2588\u2588\u2588\u259C\u258C' + N + '   ' + W + 'Claude Code' + N + ' ' + D + 'v2.1.71' + N);
      terminal.writeln(M + '\u259D\u259C\u2588\u2588\u2588\u2588\u2588\u259B\u2598' + N + '  ' + D + 'Opus 4.6 with extended thinking' + N);
      terminal.writeln(M + '  \u2598\u2598 \u259D\u259D' + N + '    ' + D + '~/Projects/hakuke' + N);
      terminal.writeln('');
      const scenarios = [
        // Rate limit
        () => {
          terminal.writeln(C + '>' + N + ' ' + W + 'refactor the entire codebase to Rust' + N);
          terminal.writeln('');
          terminal.writeln(D + '  Thinking...' + N);
          terminal.writeln('');
          terminal.writeln(Y + '  \u26A0 Claude is experiencing high demand right now.' + N);
          terminal.writeln(Y + '  Your rate limit will reset in ' + W + '3h 47m' + N + Y + '.' + N);
          terminal.writeln(D + '  Tip: Upgrade to Max for 20x higher usage.' + N);
          terminal.writeln('');
          terminal.writeln(D + '  (' + N + 'You stare at the terminal.' + D);
          terminal.writeln('   The terminal stares back.' + D);
          terminal.writeln('   You open a new tab and write the code yourself.)' + N);
        },
        // Context window
        () => {
          terminal.writeln(C + '>' + N + ' ' + W + 'fix one more bug please' + N);
          terminal.writeln('');
          terminal.writeln(Y + '  \u26A0 This conversation has used ' + W + '95%' + N + Y + ' of the context window.' + N);
          terminal.writeln(Y + '  Auto-compacting conversation...' + N);
          terminal.writeln(Y + '  Auto-compacting conversation...' + N);
          terminal.writeln(Y + '  Auto-compacting conversation...' + N);
          terminal.writeln('');
          terminal.writeln(R + '  Error: Context window exceeded.' + N);
          terminal.writeln(D + '  Claude has forgotten everything you discussed' + N);
          terminal.writeln(D + '  for the past 2 hours. Start a new conversation.' + N);
          terminal.writeln('');
          terminal.writeln(D + '  (You whisper "I should have committed more often.")' + N);
        },
        // Max output tokens
        () => {
          terminal.writeln(C + '>' + N + ' ' + W + 'write comprehensive tests for every module' + N);
          terminal.writeln('');
          terminal.writeln(D + '  I\'ll write comprehensive tests for all 47 modules.' + N);
          terminal.writeln(D + '  Starting with the first one...' + N);
          terminal.writeln('');
          terminal.writeln(G + '  // test_module_1.swift' + N);
          terminal.writeln(G + '  func testInit() {' + N);
          terminal.writeln(G + '    let sut = Modu\u2014' + N);
          terminal.writeln('');
          terminal.writeln(Y + '  \u26A0 Reached max output tokens for this turn.' + N);
          terminal.writeln(D + '  (1 of 47 modules. 46 to go. Press Enter to continue.)' + N);
          terminal.writeln('');
          terminal.writeln(D + '  (The tests were never completed. They say Claude' + N);
          terminal.writeln(D + '   is still thinking about testModule2 to this day.)' + N);
        },
        // 529 overloaded
        () => {
          terminal.writeln(C + '>' + N + ' ' + W + 'deploy to production' + N);
          terminal.writeln('');
          terminal.writeln(R + '  529 Overloaded' + N);
          terminal.writeln(R + '  529 Overloaded' + N);
          terminal.writeln(R + '  529 Overloaded' + N);
          terminal.writeln('');
          terminal.writeln(D + '  Claude is at capacity right now.' + N);
          terminal.writeln(D + '  Please check back in:  ' + Y + '\u221E' + N);
          terminal.writeln('');
          terminal.writeln(D + '  (Friday 5pm deploy attempt #1 of 12.' + N);
          terminal.writeln(D + '   You should not have waited until Friday.)' + N);
        },
      ];
      scenarios[Math.floor(Math.random() * scenarios.length)]();
      return;
    }

    if (cmd === 'sudo') {
      const rest = parts.slice(1).join(' ');
      if (rest === 'make me a sandwich') {
        terminal.writeln(D + '[sudo] password for user: ' + N + '********');
        terminal.writeln(G + 'Okay.' + N);
        terminal.writeln('  \u250C\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2510');
        terminal.writeln('  \u2502 ' + Y + '\u2584\u2584\u2584\u2584\u2584\u2584\u2584\u2584\u2584\u2584\u2584\u2584\u2584\u2584' + N + ' \u2502');
        terminal.writeln('  \u2502 ' + G + '\u2591\u2591\u2591\u2591\u2591\u2591\u2591\u2591\u2591\u2591\u2591\u2591\u2591\u2591' + N + ' \u2502');
        terminal.writeln('  \u2502 ' + R + '\u2593\u2593\u2593\u2593\u2593\u2593\u2593\u2593\u2593\u2593\u2593\u2593\u2593\u2593' + N + ' \u2502');
        terminal.writeln('  \u2502 ' + Y + '\u2584\u2584\u2584\u2584\u2584\u2584\u2584\u2584\u2584\u2584\u2584\u2584\u2584\u2584' + N + ' \u2502');
        terminal.writeln('  \u2514\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2518');
      } else {
        terminal.writeln(R + 'user is not in the sudoers file. This incident will be reported.' + N);
      }
      return;
    }

    if (input === 'rm -rf /' || input === 'rm -rf /*' || input.startsWith('rm -rf /')) {
      terminal.writeln(R + 'hakuke: refusing to destroy root.' + N);
      terminal.writeln(D + 'nice try, chaos engineer.' + N);
      return;
    }

    if (cmd === 'sl') {
      terminal.writeln(D + '      ====        ________                ' + N);
      terminal.writeln(D + '  _D _|  |_______/        \\__I_I_____===__|' + N);
      terminal.writeln(D + ' |(_)---  |   H\\________/ |   |        =|_' + N);
      terminal.writeln(D + ' /     |  |   H  |  |     |   |         ||' + N);
      terminal.writeln(D + '|      |  |   H  |__----__|   |         | |' + N);
      terminal.writeln(D + '|      |  |___H__|         |___|         |_|' + N);
      terminal.writeln(D + '|______|     _|| ||_____     _|| ||________|' + N);
      terminal.writeln(D + '       |   (____)       |   (____)         ' + N);
      terminal.writeln(Y + 'tip: you probably meant ' + W + 'ls' + N);
      return;
    }

    if (cmd === 'vim' || cmd === 'nvim' || cmd === 'vi') {
      terminal.writeln('');
      terminal.writeln(D + '~' + N);
      terminal.writeln(D + '~' + N);
      terminal.writeln(D + '~                    VIM - Vi IMproved' + N);
      terminal.writeln(D + '~' + N);
      terminal.writeln(D + '~                    version 9.1' + N);
      terminal.writeln(D + '~              by Bram Moolenaar et al.' + N);
      terminal.writeln(D + '~' + N);
      terminal.writeln(D + '~' + N);
      terminal.writeln(W + '-- INSERT --' + N + '                ' + D + 'type :q! to escape' + N);
      return;
    }

    if (cmd === ':q' || cmd === ':q!' || cmd === ':wq' || cmd === ':x') {
      if (cmd === ':q') {
        terminal.writeln(R + 'E37: No write since last change' + N);
        terminal.writeln(D + 'hint: try :q! or accept your fate' + N);
      } else {
        terminal.writeln(G + 'You escaped vim. Few have this power.' + N);
      }
      return;
    }

    if (cmd === 'emacs') {
      terminal.writeln(D + 'Loading 127 packages...' + N);
      terminal.writeln(D + 'Starting Emacs server...' + N);
      terminal.writeln(D + 'Opening M-x therapist...' + N);
      terminal.writeln(C + 'How does that make you feel?' + N);
      return;
    }

    if (cmd === '42') {
      terminal.writeln(C + 'Answer to the Ultimate Question detected.' + N);
      terminal.writeln(D + 'Please provide a better question.' + N);
      return;
    }

    if (cmd === 'fortune') {
      const fortunes = [
        '"There are only two hard things in Computer Science:\ncache invalidation, naming things, and off-by-one errors."',
        '"It works on my machine." \u2014 Every developer, at some point',
        '"Any sufficiently advanced technology is indistinguishable from magic."\n\u2014 Arthur C. Clarke',
        '"Talk is cheap. Show me the code." \u2014 Linus Torvalds',
        '"The best error message is the one that never shows up."\n\u2014 Thomas Fuchs',
        '"Programming is the art of telling another human\nwhat one wants the computer to do." \u2014 Donald Knuth',
        '"First, solve the problem. Then, write the code."\n\u2014 John Johnson',
        '"Unix is user-friendly. It\'s just choosy about\nwho its friends are." \u2014 Anonymous',
        '"There is no place like 127.0.0.1"',
        '"Works on my machine. Ship the machine."',
      ];
      const f = fortunes[Math.floor(Math.random() * fortunes.length)];
      f.split('\n').forEach(l => terminal.writeln(C + l + N));
      return;
    }

    if (cmd === 'cowsay') {
      const msg = parts.slice(1).join(' ') || 'moo';
      const line = '\u2500'.repeat(msg.length + 2);
      terminal.writeln(' \u250C' + line + '\u2510');
      terminal.writeln(' \u2502 ' + msg + ' \u2502');
      terminal.writeln(' \u2514' + line + '\u2518');
      terminal.writeln('        \\   ^__^');
      terminal.writeln('         \\  (oo)\\_______');
      terminal.writeln('            (__)\\       )\\/\\');
      terminal.writeln('                ||----w |');
      terminal.writeln('                ||     ||');
      return;
    }

    if (cmd === 'make') {
      const target = parts.slice(1).join(' ') || 'love';
      terminal.writeln(R + 'make: *** No rule to make target \'' + target + '\'. Stop.' + N);
      return;
    }

    if (cmd === 'iddqd') {
      terminal.writeln(G + W + 'GOD MODE ON' + N);
      terminal.writeln(D + 'damage: ' + G + '0' + N);
      terminal.writeln(D + 'confidence: ' + G + '+9000' + N);
      return;
    }

    if (cmd === 'idkfa') {
      terminal.writeln(G + W + 'ALL KEYS ACQUIRED' + N);
      terminal.writeln(D + 'ammo: ' + G + 'infinite' + N);
      terminal.writeln(D + 'tabs open: ' + Y + '47' + N);
      return;
    }

    if (cmd === 'xyzzy') {
      terminal.writeln(D + 'A hollow voice says ' + W + '"Fool."' + N);
      return;
    }

    if (cmd === 'nmap') {
      terminal.writeln(D + 'Starting Nmap 7.94 ...' + N);
      terminal.writeln('');
      terminal.writeln(W + 'PORT      STATE  SERVICE' + N);
      terminal.writeln(G + '22/tcp    open   ' + N + 'curiosity');
      terminal.writeln(G + '80/tcp    open   ' + N + 'creativity');
      terminal.writeln(G + '443/tcp   open   ' + N + 'shipping');
      terminal.writeln(G + '8080/tcp  open   ' + N + 'dev-server');
      terminal.writeln(G + '31337/tcp open   ' + N + C + 'elite' + N);
      return;
    }

    if (cmd === 'brew') {
      if (parts[1] === 'install' && parts[2] === 'hakuke') {
        terminal.writeln(G + '==> ' + N + W + 'Downloading hakuke...' + N);
        terminal.writeln(G + '==> ' + N + 'Pouring hakuke-1.0.0.arm64_sonoma.bottle.tar.gz');
        terminal.writeln(G + '\uD83C\uDF7A ' + N + W + 'hakuke' + N + ' installed successfully');
        terminal.writeln(D + 'Try: ' + C + 'hakuke --quake-mode' + N);
      } else {
        terminal.writeln(D + 'Usage: brew install hakuke' + N);
      }
      return;
    }

    if (cmd === 'python' || cmd === 'python3') {
      terminal.writeln(D + 'Python 3.12.0' + N);
      terminal.writeln(D + '>>> ' + C + 'import antigravity' + N);
      terminal.writeln(G + 'xkcd.com/353 \u2014 I\'m flying!' + N);
      return;
    }

    if (cmd === 'node') {
      terminal.writeln(D + 'Welcome to Node.js v22.0.0.' + N);
      terminal.writeln(D + '> ' + C + 'typeof NaN' + N);
      terminal.writeln(Y + '\'number\'' + N);
      terminal.writeln(D + '> ' + N + D + '// of course it is' + N);
      return;
    }

    if (cmd === 'git') {
      if (parts[1] === 'push' && parts.includes('--force')) {
        terminal.writeln(R + 'Whoa there.' + N);
        terminal.writeln(D + 'git push --force?' + N + Y + ' You monster.' + N);
        return;
      }
      if (parts[1] === 'blame') {
        terminal.writeln(D + 'git blame? In ' + W + 'this' + N + D + ' economy?' + N);
        return;
      }
      terminal.writeln(D + 'git: this is a demo terminal.' + N);
      terminal.writeln(D + 'But yes, hakuke ' + W + 'does' + N + D + ' support git.' + N);
      return;
    }

    if (cmd === 'docker') {
      terminal.writeln(D + 'Cannot connect to the Docker daemon.' + N);
      terminal.writeln(D + 'Is the Docker daemon running?' + N);
      terminal.writeln(Y + '(It never is when you need it.)' + N);
      return;
    }

    if (cmd === 'ping') {
      terminal.writeln(G + 'PONG' + N);
      return;
    }

    if (cmd === 'exit') {
      terminal.writeln(D + 'There is no escape.' + N);
      terminal.writeln(D + 'Press ' + W + 'Option+Space' + N + D + ' to hide the terminal.' + N);
      return;
    }

    if (cmd === 'ssh') {
      terminal.writeln(R + 'ssh: connect to host ' + (parts[1] || 'localhost') + ' port 22: Connection refused' + N);
      terminal.writeln(D + '(nice try)' + N);
      return;
    }

    if (cmd === 'curl') {
      if (input.includes('parrot.live')) {
        terminal.writeln(G + '            .--.' + N);
        terminal.writeln(G + '           /    \\' + N);
        terminal.writeln(Y + '          ## a]a ## ' + N);
        terminal.writeln(Y + '          \\  =  / ' + N);
        terminal.writeln(R + '           />--<' + N);
        terminal.writeln(R + '          //     \\\\' + N);
        terminal.writeln(D + '   PARTY PARROT!' + N);
      } else {
        terminal.writeln(D + 'curl: this is a demo. Try ' + C + 'curl parrot.live' + N);
      }
      return;
    }

    if (cmd === 'telnet') {
      terminal.writeln(D + 'Trying ' + (parts[1] || '...') + '...' + N);
      terminal.writeln(D + 'Connected to a galaxy far, far away.' + N);
      terminal.writeln(Y + '           .          .' + N);
      terminal.writeln(Y + '     .  *        *   .    *' + N);
      terminal.writeln(Y + '  *    STAR WARS     .  *' + N);
      terminal.writeln(Y + '     .          *       .' + N);
      terminal.writeln(D + 'Connection closed.' + N);
      return;
    }

    if (cmd === 'konami' || input === 'up up down down left right left right b a') {
      terminal.writeln(Y + '\u2191 \u2191 \u2193 \u2193 \u2190 \u2192 \u2190 \u2192 B A' + N);
      terminal.writeln(G + W + '+30 extra lives' + N);
      terminal.writeln(D + '(you\'ll need them for debugging)' + N);
      return;
    }

    if (cmd === 'hacktheplanet' || input === 'hack the planet') {
      terminal.writeln('');
      terminal.writeln(G + W + '  HACK THE PLANET!' + N);
      terminal.writeln(D + '  modem noises intensify...' + N);
      terminal.writeln(D + '  [' + G + '\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2588' + D + '] 100%' + N);
      terminal.writeln(G + '  Access granted.' + N);
      terminal.writeln('');
      return;
    }

    if (cmd === 'matrix') {
      const chars = '\u30A2\u30AB\u30B5\u30BF\u30CA\u30CF\u30DE\u30E4\u30E9\u30EF01';
      for (let i = 0; i < 6; i++) {
        let line = '';
        for (let j = 0; j < 40; j++) { line += (Math.random() > 0.7 ? G + W : G) + chars[Math.floor(Math.random() * chars.length)]; }
        terminal.writeln(line + N);
      }
      terminal.writeln(G + W + '  Wake up, Neo...' + N);
      return;
    }

    if (input === ':(){ :|:& };:') {
      terminal.writeln(R + 'fork bomb signature detected.' + N);
      terminal.writeln(D + 'spawning 0 processes.' + N);
      terminal.writeln(D + 'nice museum piece.' + N);
      return;
    }

    if (cmd === 'apt-get' || cmd === 'apt' || cmd === 'yum' || cmd === 'dnf' || cmd === 'pacman') {
      terminal.writeln(R + cmd + ': command not found' + N);
      terminal.writeln(D + 'This is macOS. Try ' + C + 'brew install hakuke' + N);
      return;
    }

    if (cmd === 'top' || cmd === 'htop') {
      terminal.writeln(W + 'PID    CPU%  MEM%  COMMAND' + N);
      terminal.writeln(G + '1337   0.0   0.1   hakuke' + N);
      terminal.writeln(D + '420    98.2  45.0   node_modules' + N);
      terminal.writeln(D + '9999   12.4  8.3    vscode --disable-gpu' + N);
      terminal.writeln(D + '666    0.0   99.9   chrome' + N);
      terminal.writeln(D + '42     4.2   2.1    slack' + N);
      return;
    }

    if (cmd === 'uptime') {
      terminal.writeln(D + 'up 42 days, 13:37, 1 user, load averages: 0.42 0.13 0.37' + N);
      return;
    }

    if (cmd === 'date') {
      terminal.writeln(new Date().toString());
      return;
    }

    if (cmd === 'lolcat' || cmd === 'cmatrix' || cmd === 'figlet' || cmd === 'toilet') {
      terminal.writeln(D + cmd + ': great taste. Try ' + C + 'cowsay' + N + D + ' or ' + C + 'fortune' + N + D + ' instead.' + N);
      return;
    }

    if (cmd === 'rm') {
      terminal.writeln(Y + 'rm: not today.' + N);
      return;
    }

    if (cmd === 'man') {
      terminal.writeln(D + 'No manual entry for ' + (parts[1] || 'nothing') + '.' + N);
      terminal.writeln(D + 'Try ' + C + 'help' + N + D + ' instead.' + N);
      return;
    }

    if (cmd === 'yes') {
      for (let i = 0; i < 8; i++) terminal.writeln(G + (parts[1] || 'y') + N);
      terminal.writeln(D + '^C' + N);
      return;
    }

    if (cmd === 'hello' || cmd === 'hi' || cmd === 'hey') {
      terminal.writeln(C + 'Hello! \uD83D\uDC4B Type ' + W + 'help' + N + C + ' to see what I can do.' + N);
      return;
    }

    if (cmd === 'cd') {
      terminal.writeln(D + '(nowhere to go, but you\'re already home)' + N);
      return;
    }

    if (cmd === 'touch') {
      terminal.writeln(D + 'touch: permission denied (read-only demo)' + N);
      return;
    }

    if (cmd === 'chmod' || cmd === 'chown') {
      terminal.writeln(R + cmd + ': operation not permitted' + N);
      terminal.writeln(D + 'nice try, root.' + N);
      return;
    }

    if (cmd === 'which') {
      if (parts[1] === 'hakuke') { terminal.writeln('/usr/local/bin/hakuke'); }
      else { terminal.writeln(D + parts[1] + ' not found' + N); }
      return;
    }

    if (cmd === 'impulse' && parts[1] === '9') {
      terminal.writeln(G + W + 'ALL WEAPONS AND KEYS ADDED' + N);
      terminal.writeln(D + 'armor: ' + G + '200' + N);
      terminal.writeln(D + 'nails: ' + G + '200' + N);
      terminal.writeln(D + 'rockets: ' + G + '100' + N);
      terminal.writeln(Y + 'You are ready to frag.' + N);
      return;
    }

    if (cmd === 'coffee') {
      terminal.writeln('');
      terminal.writeln(Y + '       ( (' + N);
      terminal.writeln(Y + '        ) )' + N);
      terminal.writeln(D + '     ........' + N);
      terminal.writeln(D + '     |      |]' + N);
      terminal.writeln(D + '     \\      /' + N);
      terminal.writeln(D + '      `----\'' + N);
      terminal.writeln(R + '  HTTP 418: I\'m a teapot.' + N);
      return;
    }

    if (cmd === 'history') {
      terminal.writeln(D + '    1  ' + N + 'sudo rm -rf /var/log');
      terminal.writeln(D + '    2  ' + N + 'git push --force origin main');
      terminal.writeln(D + '    3  ' + N + 'google "how to undo git push force"');
      terminal.writeln(D + '    4  ' + N + 'google "cheap flights to mexico"');
      terminal.writeln(D + '    5  ' + N + 'history');
      return;
    }

    if (cmd === 'kill') {
      if (input.includes('$$')) {
        terminal.writeln(D + 'Terminal terminated...' + N);
        terminal.writeln(G + 'Just kidding. You can\'t kill a DOM element that easily.' + N);
      } else {
        terminal.writeln(R + 'kill: no process found' + N);
      }
      return;
    }

    if (cmd === 'bofh') {
      const excuses = [
        'solar flares affecting the server room',
        'stray alpha particles from memory packaging',
        'the network is being reconfigured to support RFC 2549',
        'someone tripped over the ethernet cable again',
        'cosmic rays flipped a bit in production',
        'the hamster powering the server took a break',
        'DNS propagation (it\'s always DNS)',
        'the intern pushed to main on Friday at 5pm',
      ];
      terminal.writeln(R + 'EXCUSE: ' + N + excuses[Math.floor(Math.random() * excuses.length)]);
      return;
    }

    if (cmd === 'whereami') {
      terminal.writeln(D + 'You are in a maze of twisty little passages, all alike.' + N);
      return;
    }

    if (cmd === 'cargo' || cmd === 'rustc') {
      terminal.writeln(D + 'error[E0308]: mismatched types' + N);
      terminal.writeln(D + '  --> demo.rs:1:1' + N);
      terminal.writeln(R + '  | expected `real_terminal`, found `web_demo`' + N);
      terminal.writeln(D + 'For more info, try ' + C + 'rustc --explain E0308' + N);
      return;
    }

    // ── hakuke CLI commands ──

    if (cmd === 'hakuke') {
      const sub = parts[1];
      const args = parts.slice(2);
      const { flags, positional } = self.parseFlags(args);

      if (!sub) { terminal.writeln(D + 'Usage: hakuke <command> [flags]. Type ' + W + 'help' + N + D + ' for commands.' + N); return; }

      // ── state ──
      if (sub === 'state') {
        const tree = ctx.paneTrees.get(ctx.state.activeTabId);
        const paneCount = tree ? ctx.collectLeaves(tree).length : 1;
        terminal.writeln(C + 'Visible:   ' + N + (ctx.state.visible ? G + 'yes' + N : R + 'no' + N));
        terminal.writeln(C + 'Pinned:    ' + N + (ctx.state.pinned ? G + 'yes' + N : D + 'no' + N));
        terminal.writeln(C + 'Tabs:      ' + N + Y + ctx.state.tabs.length + N);
        terminal.writeln(C + 'Panes:     ' + N + Y + paneCount + N);
        terminal.writeln(C + 'Active tab:' + N + ' ' + Y + ctx.state.activeTabId + N);
        terminal.writeln(C + 'Version:   ' + N + '0.1.0');
        return;
      }

      // ── ls / list (tabs & panes) ──
      if (sub === 'ls' || sub === 'list') {
        ctx.state.tabs.forEach((t, i) => {
          const tree = ctx.paneTrees.get(t.id);
          const panes = tree ? ctx.collectLeaves(tree) : [];
          const active = t.id === ctx.state.activeTabId;
          const marker = active ? G + ' *' + N : '  ';
          terminal.writeln(marker + C + ' Tab ' + Y + '#' + t.id + N + '  ' + W + t.title + N + D + '  (' + panes.length + (panes.length === 1 ? ' pane' : ' panes') + ')' + N);
          panes.forEach(pid => {
            const isFocused = pid === paneId;
            terminal.writeln('    ' + D + '\u2514 ' + N + (isFocused ? G + pid + ' (focused)' + N : D + pid + N));
          });
        });
        return;
      }

      // ── toggle / show / hide ──
      if (sub === 'toggle') {
        ctx.state.visible = !ctx.state.visible;
        terminal.writeln(G + 'Terminal ' + (ctx.state.visible ? 'shown' : 'hidden') + '.' + N);
        if (!ctx.state.visible) setTimeout(() => { if (ctx.interactiveOpen) ctx.toggleInteractive(); }, 300);
        return;
      }
      if (sub === 'show') {
        ctx.state.visible = true;
        terminal.writeln(G + 'Terminal shown.' + N);
        return;
      }
      if (sub === 'hide') {
        ctx.state.visible = false;
        terminal.writeln(G + 'Terminal hidden.' + N + D + ' Press Option+Space to show.' + N);
        setTimeout(() => { if (ctx.interactiveOpen) ctx.toggleInteractive(); }, 300);
        return;
      }

      // ── new-tab [--title NAME] or positional ──
      if (sub === 'new-tab') {
        const title = flags.title || positional.join(' ') || '~';
        const tab = ctx.addNewTab(title);
        terminal.writeln(G + 'Created tab ' + N + W + '"' + title + '"' + N + D + ' (' + ctx.state.tabs.length + ' tabs open)' + N);
        return;
      }

      // ── close-tab [--match ID] ──
      if (sub === 'close-tab') {
        if (ctx.state.tabs.length <= 1) {
          terminal.writeln(Y + 'Cannot close the last tab.' + N);
          return;
        }
        let tabId = ctx.state.activeTabId;
        if (flags.match !== undefined) {
          const id = parseInt(flags.match);
          const found = ctx.state.tabs.find(t => t.id === id);
          if (!found) { terminal.writeln(R + 'No tab matching id ' + flags.match + N); return; }
          tabId = id;
        } else if (positional[0] !== undefined) {
          const id = parseInt(positional[0]);
          const found = ctx.state.tabs.find(t => t.id === id);
          if (!found) { terminal.writeln(R + 'No tab matching id ' + positional[0] + N); return; }
          tabId = id;
        }
        const tab = ctx.state.tabs.find(t => t.id === tabId);
        const name = tab ? tab.title : tabId;
        ctx.closeTab(tabId);
        terminal.writeln(G + 'Closed tab ' + N + W + '"' + name + '"' + N + D + '. ' + ctx.state.tabs.length + ' tab' + (ctx.state.tabs.length === 1 ? '' : 's') + ' remaining.' + N);
        return;
      }

      // ── focus-tab --match ID ──
      if (sub === 'focus-tab') {
        const id = parseInt(flags.match || positional[0]);
        if (isNaN(id)) { terminal.writeln(R + 'Usage: hakuke focus-tab --match <id>' + N); return; }
        const found = ctx.state.tabs.find(t => t.id === id);
        if (!found) { terminal.writeln(R + 'No tab matching id ' + id + N); return; }
        ctx.state.activeTabId = id;
        ctx.renderTabs();
        if (ctx.renderPanes) ctx.renderPanes();
        terminal.writeln(G + 'Focused tab ' + N + W + '"' + found.title + '"' + N);
        return;
      }

      // ── split [--horizontal | --vertical | h | v] ──
      if (sub === 'split') {
        let dir = 'h';
        if (flags.vertical || positional[0] === 'v' || positional[0] === 'vertical') dir = 'v';
        // --horizontal is default
        const newId = ctx.splitPane(paneId, dir);
        if (newId) {
          const dirName = dir === 'h' ? 'horizontal' : 'vertical';
          const tree = ctx.paneTrees.get(ctx.state.activeTabId);
          const count = tree ? ctx.collectLeaves(tree).length : 1;
          terminal.writeln(G + 'Split pane ' + dirName + 'ly.' + N + D + ' ' + count + ' panes in tab.' + N);
        }
        return;
      }

      // ── close-pane ──
      if (sub === 'close-pane') {
        const tree = ctx.paneTrees.get(ctx.state.activeTabId);
        if (tree && tree.type !== 'leaf') {
          ctx.closePane(paneId);
          const newTree = ctx.paneTrees.get(ctx.state.activeTabId);
          const count = newTree ? ctx.collectLeaves(newTree).length : 1;
          terminal.writeln(G + 'Closed pane.' + N + D + ' ' + count + ' pane' + (count === 1 ? '' : 's') + ' remaining.' + N);
        } else {
          terminal.writeln(Y + 'Only one pane. Use ' + W + 'hakuke close-tab' + N + Y + ' to close the tab.' + N);
        }
        return;
      }

      // ── launch <cmd> (execute command) ──
      if (sub === 'launch' || sub === 'execute') {
        const execCmd = (flags.command || positional.join(' ')) || '';
        if (!execCmd) { terminal.writeln(R + 'Usage: hakuke launch <command>' + N); return; }
        terminal.writeln(G + 'Running: ' + N + W + execCmd + N);
        return;
      }

      // ── send-text <text> ──
      if (sub === 'send-text' || sub === 'paste') {
        const text = positional.join(' ');
        if (!text) { terminal.writeln(R + 'Usage: hakuke send-text <text>' + N); return; }
        terminal.writeln(G + 'Sent ' + N + Y + text.length + N + G + ' chars.' + N);
        return;
      }

      // ── send-key <key> (control char) ──
      if (sub === 'send-key' || sub === 'control-char') {
        const ch = (positional[0] || '').toLowerCase();
        if (!ch) { terminal.writeln(R + 'Usage: hakuke send-key <key>' + N + D + '  Valid: ' + self.validControlChars.join(', ') + N); return; }
        if (self.validControlChars.includes(ch)) {
          terminal.writeln(G + 'Sent ' + N + W + 'Ctrl+' + ch.toUpperCase() + N);
        } else {
          terminal.writeln(R + 'Invalid key: ' + ch + N + D + '. Valid: ' + self.validControlChars.join(', ') + N);
        }
        return;
      }

      // ── get-text [--lines N] (read terminal) ──
      if (sub === 'get-text' || sub === 'read') {
        const n = parseInt(flags.lines || positional[0]) || 5;
        terminal.writeln(D + 'Reading last ' + n + ' lines from active pane:' + N);
        self.readLines.slice(0, n).forEach(l => terminal.writeln('  ' + l));
        return;
      }

      // ── pin / unpin ──
      if (sub === 'pin') {
        ctx.state.pinned = true;
        ctx.pinBtn.classList.add('pinned');
        if (ctx.interactiveOpen) ctx.backdrop.classList.remove('visible');
        terminal.writeln(G + 'Pinned above all windows.' + N);
        return;
      }
      if (sub === 'unpin') {
        ctx.state.pinned = false;
        ctx.pinBtn.classList.remove('pinned');
        if (ctx.interactiveOpen) ctx.backdrop.classList.add('visible');
        terminal.writeln(G + 'Unpinned.' + N);
        return;
      }

      // ── resize [--width N] [--height N] [--opacity N] ──
      if (sub === 'resize' || sub === 'set-appearance') {
        const w = Math.min(100, Math.max(30, parseInt(flags.width || positional[0]) || 80));
        const h = Math.min(90, Math.max(20, parseInt(flags.height || positional[1]) || 50));
        terminal.writeln(G + 'Resized.' + N + '  Width: ' + Y + w + '%' + N + '  Height: ' + Y + h + '%' + N);
        return;
      }

      // ── settings ──
      if (sub === 'settings') {
        terminal.writeln('');
        terminal.writeln('  ' + W + 'Settings' + N);
        terminal.writeln('  ' + D + '\u2500'.repeat(36) + N);
        terminal.writeln('  ' + C + 'Hotkey           ' + N + 'Option+Space');
        terminal.writeln('  ' + C + 'Width            ' + N + '80%');
        terminal.writeln('  ' + C + 'Height           ' + N + '50%');
        terminal.writeln('  ' + C + 'Opacity          ' + N + '1.0');
        terminal.writeln('  ' + C + 'Pin on top       ' + N + (ctx.state.pinned ? G + 'Yes' + N : D + 'No' + N));
        terminal.writeln('  ' + C + 'Display          ' + N + 'Follow cursor');
        terminal.writeln('  ' + C + 'API access       ' + N + G + 'Enabled' + N);
        terminal.writeln('  ' + C + 'Auto-update      ' + N + G + 'Enabled' + N);
        terminal.writeln('  ' + C + 'Ghostty config   ' + N + '~/.config/ghostty/config');
        return;
      }

      // ── clear ──
      if (sub === 'clear') {
        terminal.clear();
        terminal.writeln(G + 'Buffer cleared.' + N);
        return;
      }

      terminal.writeln(R + 'Unknown command: hakuke ' + sub + N);
      terminal.writeln(D + 'Run ' + W + 'help' + N + D + ' for available commands.' + N);
      return;
    }

    terminal.writeln(R + 'command not found: ' + cmd + N);
  }
};
