/* ═══════════════════════════════════════════════
   hakuke landing — main app
   State, scroll demo, tabs, pane management, xterm.js
   ═══════════════════════════════════════════════ */

window.addEventListener('DOMContentLoaded', () => {
  gsap.registerPlugin(ScrollTrigger);

  const qtBody    = document.getElementById('qt-body');
  const qtXterm   = document.getElementById('qt-xterm');
  const qtTabs    = document.getElementById('qt-tabs');
  const quake     = document.getElementById('quake');
  const backdrop  = document.getElementById('qt-backdrop');
  const heroContent = document.getElementById('hero-content');
  const hotkeyHint = document.getElementById('hotkey-hint');
  const toggleFab = document.getElementById('toggle-fab');
  const tryBtn    = document.getElementById('try-btn');
  const pinBtn    = document.getElementById('qt-pin-btn');
  const scrollHint = document.getElementById('scroll-hint');

  const demoScript = window.MQ_DEMO;
  const shell = window.MQ_SHELL;

  /* ═══════════════════════════════════════════════
     UNIFIED STATE
     ═══════════════════════════════════════════════ */

  const state = {
    visible: true,
    pinned: false,
    tabs: [{ id: 0, title: '~/Projects' }],
    activeTabId: 0,
    nextTabId: 1,
    nextPaneId: 1,
  };

  // Pane tree per tab: tabId -> PaneNode
  const paneTrees = new Map();
  const activePanePerTab = new Map();
  paneTrees.set(0, { type: 'leaf', id: 'p0' });
  activePanePerTab.set(0, 'p0');

  // Pane instances: paneId -> { terminal, fitAddon, shellState, el }
  const paneInstances = new Map();
  let focusedPaneId = 'p0';

  let mode = 'demo';
  let interactiveOpen = false;
  let demoCompleted = false;

  function collectLeaves(node) {
    if (node.type === 'leaf') return [node.id];
    return [...collectLeaves(node.children[0]), ...collectLeaves(node.children[1])];
  }

  // Context object passed to shell.handleCmd and demo.onComplete
  // ── Demo split visual ──
  let demoSplitActive = false;

  function showDemoSplit() {
    if (demoSplitActive) return;
    demoSplitActive = true;
    qtBody.classList.add('split');

    const divider = document.createElement('div');
    divider.className = 'qt-divider qt-divider-h';
    divider.id = 'qt-demo-divider';

    const rightPane = document.createElement('div');
    rightPane.className = 'qt-demo-right';
    rightPane.id = 'qt-demo-right';
    rightPane.innerHTML =
      '<div class="qt-line" style="opacity:1;height:auto"><span class="qt-prompt">~</span> <span class="qt-cursor blink"></span></div>';

    qtBody.appendChild(divider);
    qtBody.appendChild(rightPane);
    requestAnimationFrame(() => { rightPane.classList.add('visible'); });
  }

  function fillDemoSplit() {
    const right = document.getElementById('qt-demo-right');
    if (!right) return;
    right.innerHTML =
      '<div class="qt-line" style="opacity:1;height:auto"><span class="qt-prompt">~</span> python3 -m http.server 8080</div>' +
      '<div class="qt-line" style="opacity:1;height:auto;color:#30d158">Serving HTTP on :: port 8080 (http://[::]:8080/) ...</div>' +
      '<div class="qt-line" style="opacity:1;height:auto;color:#8e8e93">127.0.0.1 - [07/Mar/2026] "GET / HTTP/1.1" 200 -</div>' +
      '<div class="qt-line" style="opacity:1;height:auto;color:#8e8e93">127.0.0.1 - [07/Mar/2026] "GET /favicon.ico HTTP/1.1" 404 -</div>';
  }

  function unfillDemoSplit() {
    const right = document.getElementById('qt-demo-right');
    if (!right) return;
    right.innerHTML =
      '<div class="qt-line" style="opacity:1;height:auto"><span class="qt-prompt">~</span> <span class="qt-cursor blink"></span></div>';
  }

  function killDemoSplit() {
    const right = document.getElementById('qt-demo-right');
    if (!right) return;
    right.innerHTML =
      '<div class="qt-line" style="opacity:1;height:auto"><span class="qt-prompt">~</span> python3 -m http.server 8080</div>' +
      '<div class="qt-line" style="opacity:1;height:auto;color:#30d158">Serving HTTP on :: port 8080 (http://[::]:8080/) ...</div>' +
      '<div class="qt-line" style="opacity:1;height:auto;color:#8e8e93">127.0.0.1 - [07/Mar/2026] "GET / HTTP/1.1" 200 -</div>' +
      '<div class="qt-line" style="opacity:1;height:auto;color:#ff6b6b">^C</div>' +
      '<div class="qt-line" style="opacity:1;height:auto"><span class="qt-prompt">~</span> <span class="qt-cursor blink"></span></div>';
  }

  function hideDemoSplit() {
    if (!demoSplitActive) return;
    demoSplitActive = false;
    const divider = document.getElementById('qt-demo-divider');
    const right = document.getElementById('qt-demo-right');
    if (divider) divider.remove();
    if (right) right.remove();
    qtBody.classList.remove('split');
  }

  function getCtx() {
    return {
      state, paneTrees, activePanePerTab, paneInstances,
      collectLeaves, addNewTab, closeTab, splitPane, closePane,
      pinBtn, backdrop,
      get interactiveOpen() { return interactiveOpen; },
      toggleInteractive, renderTabs, renderPanes, showDemoSplit, fillDemoSplit, unfillDemoSplit, killDemoSplit, hideDemoSplit,
    };
  }

  setTimeout(() => { hotkeyHint.style.opacity = '1'; scrollHint.style.opacity = '1'; }, 2000);

  /* ═══════════════════════════════════════════════
     SCROLL-DRIVEN DEMO
     ═══════════════════════════════════════════════ */

  const items = [];
  demoScript.forEach((step, si) => {
    if (!step.skipPrompt) items.push({ type: 'cmd', text: step.cmd, step: si, promptChar: step.promptChar });
    step.out.forEach(o => {
      if (typeof o === 'object' && o.html !== undefined) items.push({ type: 'out', html: o.html, cls: o.cls, step: si });
      else items.push({ type: 'out', html: o, step: si });
    });
  });
  items.push({ type: 'prompt' });

  // Wrap demo lines in a left container for split support
  const demoLeft = document.createElement('div');
  demoLeft.className = 'qt-demo-left';
  qtBody.appendChild(demoLeft);

  const lineEls = [];
  items.forEach(item => {
    const div = document.createElement('div');
    div.className = 'qt-line';
    div.style.opacity = '0'; div.style.height = '0'; div.style.overflow = 'hidden';
    if (item.type === 'cmd') {
      const pc = item.promptChar || '~';
      div.innerHTML = '<span class="qt-prompt">' + pc + '</span> <span class="qt-cmd"></span><span class="qt-cursor"></span>';
      div._cmdText = item.text;
    } else if (item.type === 'out') {
      div.innerHTML = item.html;
      if (item.cls) div.classList.add(item.cls);
    } else {
      div.innerHTML = '<span class="qt-prompt">~</span> <span class="qt-cursor blink"></span>';
    }
    div._item = item; demoLeft.appendChild(div); lineEls.push(div);
  });

  const completedSteps = new Set();

  // Precompute the last output line index per step for onComplete triggering
  const stepLastOutIdx = {};
  demoScript.forEach((step, si) => {
    if (!step.onComplete) return;
    const lastOut = lineEls.filter(el => el._item.step === si && el._item.type === 'out');
    if (lastOut.length) stepLastOutIdx[si] = lineEls.indexOf(lastOut[lastOut.length - 1]);
  });

  function updateTerminal(progress) {
    const total = lineEls.length;
    const rawIdx = progress * total;
    for (let i = 0; i < total; i++) {
      const el = lineEls[i], item = el._item;
      if (i < rawIdx) {
        el.style.opacity = '1'; el.style.height = 'auto';
        if (item.type === 'cmd') {
          const chars = Math.floor(Math.min(1, rawIdx - i) * el._cmdText.length);
          const cmdEl = el.querySelector('.qt-cmd'), cur = el.querySelector('.qt-cursor');
          if (chars < el._cmdText.length) { cmdEl.textContent = el._cmdText.slice(0, chars); cur.style.display = ''; cur.classList.remove('blink'); }
          else { cmdEl.textContent = el._cmdText; cur.style.display = 'none'; }
        }
      } else { el.style.opacity = '0'; el.style.height = '0'; }
    }

    // Fire onComplete / undo based on scroll direction
    const ctx = getCtx();
    demoScript.forEach((step, si) => {
      if (!step.onComplete) return;
      const idx = stepLastOutIdx[si];
      if (idx === undefined) return;
      const shouldBeActive = idx < rawIdx;
      const wasActive = completedSteps.has(si);
      if (shouldBeActive && !wasActive) {
        completedSteps.add(si);
        step.onComplete(ctx);
      } else if (!shouldBeActive && wasActive) {
        completedSteps.delete(si);
        if (step.onRevert) step.onRevert(ctx);
      }
    });

    demoLeft.scrollTop = demoLeft.scrollHeight;
  }

  // ── Entrance animations ──
  gsap.from('.hero-title', { opacity: 0, y: 30, duration: 1, ease: 'power3.out' });
  gsap.from('.hero-subtitle', { opacity: 0, y: 20, duration: 1, delay: .15 });
  gsap.from('.hero-description', { opacity: 0, y: 20, duration: 1, delay: .3 });
  gsap.from('.cta', { opacity: 0, y: 20, duration: 1, delay: .45 });

  // ── Scroll timeline ──
  ScrollTrigger.create({
    trigger: '.hero-sequence',
    start: 'top top',
    end: 'bottom bottom',
    scrub: 0.3,
    onUpdate: (self) => {
      if (interactiveOpen) return;
      const p = self.progress;

      // Once demo completed, don't re-show terminal on scroll back
      if (demoCompleted && p > 0.02) {
        quake.style.transform = 'translateY(-110%)';
        return;
      }

      // Reset when scrolled all the way back to top
      if (p <= 0.02 && demoCompleted) {
        demoCompleted = false;
        completedSteps.clear();
        hideDemoSplit();
        state.tabs = [{ id: 0, title: '~/Projects' }];
        state.activeTabId = 0;
        state.nextTabId = 1;
        state.visible = true;
        state.pinned = false;
        renderTabs();
      }

      if (p > 0.02) { hotkeyHint.style.opacity = '0'; scrollHint.style.opacity = '0'; }

      // Hero content fade
      if (p < 0.10) { heroContent.style.opacity = '1'; heroContent.style.transform = 'translateY(0)'; heroContent.style.pointerEvents = ''; }
      else if (p < 0.22) { const f = (p - 0.10) / 0.12; heroContent.style.opacity = String(1 - f); heroContent.style.transform = 'translateY(' + (-f * 50) + 'px)'; heroContent.style.pointerEvents = 'none'; }
      else { heroContent.style.opacity = '0'; heroContent.style.pointerEvents = 'none'; }

      // Keep demo mode during scroll
      if (mode !== 'demo') switchMode('demo');

      // Terminal drop/retract
      quake.classList.remove('animating');
      if (p < 0.10) { quake.style.transform = 'translateY(-110%)'; }
      else if (p < 0.22) { const d = (p - 0.10) / 0.12; quake.style.transform = 'translateY(' + (-110 + 110 * (1 - Math.pow(1 - d, 3))) + '%)'; }
      else if (p < 0.82) { quake.style.transform = 'translateY(0)'; }
      else {
        const r = (p - 0.82) / 0.18;
        quake.style.transform = 'translateY(' + (-110 * r * r) + '%)';
        if (p > 0.95) demoCompleted = true;
      }

      // Typing progress
      if (p >= 0.22 && p <= 0.82) updateTerminal((p - 0.22) / 0.60);
    }
  });

  // Show FAB after scrolling past hero
  ScrollTrigger.create({
    trigger: '#features',
    start: 'top 80%',
    onEnter: () => toggleFab.classList.add('visible'),
    onLeaveBack: () => { if (!interactiveOpen) toggleFab.classList.remove('visible'); }
  });

  // Section reveals
  gsap.utils.toArray('.card').forEach((c, i) => { gsap.from(c, { scrollTrigger: { trigger: c, start: 'top 85%' }, y: 60, opacity: 0, duration: 0.8, delay: i * 0.1 }); });
  gsap.utils.toArray('.faq-item').forEach((t, i) => { gsap.from(t, { scrollTrigger: { trigger: '.faq-grid', start: 'top 80%' }, y: 20, opacity: 0, duration: 0.5, delay: i * 0.05 }); });
  gsap.from('.install-code', { scrollTrigger: { trigger: '.install-code', start: 'top 80%' }, y: 30, opacity: 0, duration: 0.8 });

  /* ═══════════════════════════════════════════════
     MODE SWITCHING (demo ↔ interactive)
     ═══════════════════════════════════════════════ */

  function switchMode(newMode) {
    if (newMode === mode) return;
    mode = newMode;
    if (mode === 'demo') {
      qtBody.style.display = '';
      qtXterm.style.display = 'none';
    } else {
      qtBody.style.display = 'none';
      qtXterm.style.display = 'flex';
      renderTabs();
      renderPanes();
    }
  }

  /* ═══════════════════════════════════════════════
     INTERACTIVE TOGGLE (Option+Space / button)
     ═══════════════════════════════════════════════ */

  function toggleInteractive() {
    if (interactiveOpen) {
      interactiveOpen = false;
      quake.classList.add('animating');
      quake.style.transform = 'translateY(-110%)';
      backdrop.classList.remove('visible');
    } else {
      interactiveOpen = true;
      switchMode('interactive');
      quake.classList.add('animating');
      quake.style.transform = 'translateY(0)';
      if (!state.pinned) backdrop.classList.add('visible');
      toggleFab.classList.add('visible');
      setTimeout(() => { fitAllPanes(); focusPane(focusedPaneId); }, 400);
    }
  }

  document.addEventListener('keydown', (e) => {
    if (e.altKey && e.code === 'Space') { e.preventDefault(); toggleInteractive(); }
    if (e.code === 'Escape' && interactiveOpen) { toggleInteractive(); }

    // Cmd+T — new tab
    if (e.metaKey && e.key === 't' && interactiveOpen) {
      e.preventDefault();
      addNewTab();
    }

    // Cmd+W — close tab
    if (e.metaKey && e.key === 'w' && interactiveOpen) {
      e.preventDefault();
      if (state.tabs.length > 1) closeTab(state.activeTabId);
    }

    // Cmd+1-9 — switch tabs
    if (e.metaKey && !e.shiftKey && !e.altKey && e.key >= '1' && e.key <= '9' && interactiveOpen) {
      e.preventDefault();
      const idx = parseInt(e.key) - 1;
      if (idx < state.tabs.length) {
        const tab = state.tabs[idx];
        if (state.activeTabId !== tab.id) {
          state.activeTabId = tab.id;
          focusedPaneId = activePanePerTab.get(tab.id) || collectLeaves(paneTrees.get(tab.id))[0];
          renderTabs();
          renderPanes();
        }
      }
    }
  });

  toggleFab.addEventListener('click', toggleInteractive);
  tryBtn.addEventListener('click', toggleInteractive);
  backdrop.addEventListener('click', () => { if (!state.pinned) toggleInteractive(); });

  /* ═══════════════════════════════════════════════
     TAB BAR
     ═══════════════════════════════════════════════ */

  let dragTabId = null;

  function destroyTabPanes(tabId) {
    const tree = paneTrees.get(tabId);
    if (!tree) return;
    collectLeaves(tree).forEach(id => {
      const inst = paneInstances.get(id);
      if (inst) { inst.terminal.dispose(); paneInstances.delete(id); }
    });
  }

  function closeTab(tabId) {
    if (state.tabs.length <= 1) return;
    destroyTabPanes(tabId);
    state.tabs = state.tabs.filter(t => t.id !== tabId);
    paneTrees.delete(tabId);
    activePanePerTab.delete(tabId);
    if (state.activeTabId === tabId) {
      state.activeTabId = state.tabs[state.tabs.length - 1].id;
      focusedPaneId = activePanePerTab.get(state.activeTabId) || collectLeaves(paneTrees.get(state.activeTabId))[0];
    }
    renderTabs();
    if (mode === 'interactive') renderPanes();
  }

  function startRename(tab, titleSpan) {
    const input = document.createElement('input');
    input.type = 'text'; input.className = 'qt-tab-title-input';
    input.value = tab.title; input.maxLength = 24;
    titleSpan.replaceWith(input);
    input.focus(); input.select();
    function finish() { const val = input.value.trim(); if (val) tab.title = val; renderTabs(); }
    input.addEventListener('blur', finish);
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') { e.preventDefault(); input.blur(); }
      if (e.key === 'Escape') { input.value = tab.title; input.blur(); }
      e.stopPropagation();
    });
  }

  function renderTabs() {
    qtTabs.innerHTML = '';
    state.tabs.forEach(tab => {
      const el = document.createElement('div');
      el.className = 'qt-tab' + (tab.id === state.activeTabId ? ' active' : '');
      el.dataset.id = String(tab.id);

      const dot = document.createElement('span'); dot.className = 'qt-tab-dot';
      const titleSpan = document.createElement('span'); titleSpan.textContent = tab.title;
      const closeBtn = document.createElement('span'); closeBtn.className = 'qt-tab-close'; closeBtn.innerHTML = '&times;';
      el.append(dot, titleSpan, closeBtn);

      let clickTimer = null;
      el.addEventListener('click', (e) => {
        if (e.target === closeBtn || mode !== 'interactive') return;
        if (clickTimer) clearTimeout(clickTimer);
        clickTimer = setTimeout(() => {
          if (state.activeTabId !== tab.id) {
            state.activeTabId = tab.id;
            focusedPaneId = activePanePerTab.get(tab.id) || collectLeaves(paneTrees.get(tab.id))[0];
            renderTabs();
            renderPanes();
          }
        }, 250);
      });

      el.addEventListener('dblclick', (e) => {
        if (e.target === closeBtn || mode !== 'interactive') return;
        e.preventDefault(); e.stopPropagation();
        if (clickTimer) { clearTimeout(clickTimer); clickTimer = null; }
        state.activeTabId = tab.id;
        qtTabs.querySelectorAll('.qt-tab').forEach(t => t.classList.remove('active'));
        el.classList.add('active');
        startRename(tab, titleSpan);
      });

      el.addEventListener('mousedown', (e) => {
        if (e.button === 1 && mode === 'interactive') { e.preventDefault(); closeTab(tab.id); }
      });

      closeBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        if (mode === 'interactive') closeTab(tab.id);
      });

      // Drag & drop reorder
      el.draggable = true;
      el.addEventListener('dragstart', (e) => {
        if (mode !== 'interactive') { e.preventDefault(); return; }
        dragTabId = tab.id; el.classList.add('dragging');
        e.dataTransfer.effectAllowed = 'move'; e.dataTransfer.setData('text/plain', String(tab.id));
      });
      el.addEventListener('dragend', () => { el.classList.remove('dragging'); dragTabId = null; qtTabs.querySelectorAll('.qt-tab').forEach(t => t.classList.remove('drag-over')); });
      el.addEventListener('dragover', (e) => { e.preventDefault(); e.dataTransfer.dropEffect = 'move'; if (tab.id !== dragTabId) el.classList.add('drag-over'); });
      el.addEventListener('dragleave', () => { el.classList.remove('drag-over'); });
      el.addEventListener('drop', (e) => {
        e.preventDefault(); el.classList.remove('drag-over');
        if (dragTabId === null || dragTabId === tab.id) return;
        const fromIdx = state.tabs.findIndex(t => t.id === dragTabId);
        const toIdx = state.tabs.findIndex(t => t.id === tab.id);
        if (fromIdx < 0 || toIdx < 0) return;
        const [moved] = state.tabs.splice(fromIdx, 1);
        state.tabs.splice(toIdx, 0, moved);
        renderTabs();
      });

      qtTabs.appendChild(el);
    });
  }

  function addNewTab(title) {
    const tab = { id: state.nextTabId++, title: title || '~' };
    state.tabs.push(tab);
    const paneId = 'p' + state.nextPaneId++;
    paneTrees.set(tab.id, { type: 'leaf', id: paneId });
    activePanePerTab.set(tab.id, paneId);
    state.activeTabId = tab.id;
    focusedPaneId = paneId;
    renderTabs();
    if (mode === 'interactive') renderPanes();
    return tab;
  }

  document.getElementById('qt-add-tab').addEventListener('click', () => { if (mode === 'interactive') addNewTab(); });
  qtTabs.addEventListener('dblclick', (e) => { if (e.target === qtTabs && mode === 'interactive') addNewTab(); });

  // Pin button
  pinBtn.addEventListener('click', () => {
    state.pinned = !state.pinned;
    pinBtn.classList.toggle('pinned', state.pinned);
    if (state.pinned && interactiveOpen) backdrop.classList.remove('visible');
    else if (!state.pinned && interactiveOpen) backdrop.classList.add('visible');
  });

  // Initial render
  renderTabs();

  /* ═══════════════════════════════════════════════
     PANE MANAGEMENT & XTERM.JS
     ═══════════════════════════════════════════════ */

  const xtermTheme = {
    background: '#0d0d0d', foreground: '#c8c8c8',
    cursor: '#00e5bf', cursorAccent: '#0d0d0d',
    selectionBackground: 'rgba(0,229,191,0.3)',
    black: '#1a1a1a', red: '#ff6b6b', green: '#30d158',
    yellow: '#ff9f0a', blue: '#00b4d8', magenta: '#bf5af2',
    cyan: '#00e5bf', white: '#c8c8c8',
    brightBlack: '#636366', brightRed: '#ff6b6b', brightGreen: '#30d158',
    brightYellow: '#ff9f0a', brightBlue: '#00b4d8', brightMagenta: '#bf5af2',
    brightCyan: '#00e5bf', brightWhite: '#ffffff',
  };

  function renderPanes() {
    if (typeof Terminal === 'undefined') return;
    const tree = paneTrees.get(state.activeTabId);
    if (!tree) return;

    qtXterm.innerHTML = '';
    qtXterm.style.display = 'flex';
    qtXterm.style.flexDirection = 'row';

    const hasSiblings = tree.type === 'split';
    renderPaneTree(tree, qtXterm, hasSiblings);

    requestAnimationFrame(() => {
      requestAnimationFrame(() => { fitAllPanes(); focusPane(focusedPaneId); });
    });
  }

  function renderPaneTree(node, container, hasSiblings) {
    if (node.type === 'leaf') {
      const paneEl = document.createElement('div');
      paneEl.className = 'qt-pane' + (node.id === focusedPaneId ? ' focused' : '') + (hasSiblings ? ' has-siblings' : '');
      paneEl.dataset.paneId = node.id;
      paneEl.addEventListener('mousedown', () => { focusPaneById(node.id); });
      container.appendChild(paneEl);

      if (!paneInstances.has(node.id)) {
        createPaneInstance(node.id, paneEl);
      } else {
        const inst = paneInstances.get(node.id);
        paneEl.appendChild(inst.el);
      }
      return;
    }

    // Split node
    const wrapper = document.createElement('div');
    wrapper.style.cssText = 'display:flex;flex:1;min-width:0;min-height:0;flex-direction:' + (node.dir === 'h' ? 'row' : 'column');

    const leftC = document.createElement('div');
    leftC.style.cssText = 'display:flex;min-width:0;min-height:0;overflow:hidden;flex:' + (node.sizes ? node.sizes[0] : 50) + '%';

    const divider = document.createElement('div');
    divider.className = 'qt-divider qt-divider-' + node.dir;

    const rightC = document.createElement('div');
    rightC.style.cssText = 'display:flex;min-width:0;min-height:0;overflow:hidden;flex:' + (node.sizes ? node.sizes[1] : 50) + '%';

    wrapper.append(leftC, divider, rightC);
    container.appendChild(wrapper);

    renderPaneTree(node.children[0], leftC, true);
    renderPaneTree(node.children[1], rightC, true);

    setupDividerDrag(divider, node, leftC, rightC);
  }

  function createPaneInstance(paneId, parentEl) {
    const termContainer = document.createElement('div');
    termContainer.style.cssText = 'width:100%;height:100%';

    const terminal = new Terminal({
      theme: xtermTheme,
      fontFamily: '"SF Mono", Menlo, "Courier New", monospace',
      fontSize: 14, cursorBlink: true, cursorStyle: 'block', allowProposedApi: true,
    });

    let fa = null;
    if (typeof FitAddon !== 'undefined') {
      fa = new FitAddon.FitAddon();
      terminal.loadAddon(fa);
    }

    parentEl.appendChild(termContainer);
    terminal.open(termContainer);

    const shellState = { cmdBuf: '', hist: [], histIdx: -1 };
    const inst = { terminal, fitAddon: fa, shellState, el: termContainer };
    paneInstances.set(paneId, inst);

    const P = '\x1b[36m~ \x1b[0m';
    function wp() { terminal.write(P); }

    terminal.writeln('\x1b[36mhakuke\x1b[0m v0.1.0 \x1b[90m\u2014 interactive API emulator\x1b[0m');
    terminal.writeln('\x1b[90mType \x1b[37mhelp\x1b[90m for available commands. Press \x1b[37mOption+Space\x1b[90m to close.\x1b[0m');
    terminal.writeln('');
    wp();

    // Tab completion
    function tabComplete(buf) {
      const matches = shell.completions.filter(c => c.startsWith(buf) && c !== buf);
      if (matches.length === 1) return matches[0];
      if (matches.length > 1) {
        let prefix = matches[0];
        for (let i = 1; i < matches.length; i++) { while (!matches[i].startsWith(prefix)) prefix = prefix.slice(0, -1); }
        if (prefix.length > buf.length) return prefix;
        terminal.writeln('');
        matches.forEach(m => terminal.write('  \x1b[36m' + m + '\x1b[0m'));
        terminal.writeln('');
        wp(); terminal.write(buf);
        return null;
      }
      return null;
    }

    terminal.attachCustomKeyEventHandler((e) => {
      // Let browser/app handle Cmd+key combos
      if (e.metaKey && (e.key === 'v' || e.key === 'c' || e.key === 't' || e.key === 'w')) return false;
      if (e.metaKey && e.key >= '1' && e.key <= '9') return false;
      return true;
    });

    terminal.onData((data) => {
      if (data.length > 1 && !data.startsWith('\x1b')) {
        const clean = data.split('\n')[0].replace(/[\x00-\x1f]/g, '');
        shellState.cmdBuf += clean;
        terminal.write(clean);
      }
    });

    terminal.onKey(({ key, domEvent }) => {
      const code = domEvent.keyCode, ctrl = domEvent.ctrlKey, meta = domEvent.metaKey;
      if (domEvent.altKey && code === 32) return;
      if (meta) return;

      if (code === 9) {
        domEvent.preventDefault();
        const result = tabComplete(shellState.cmdBuf);
        if (result) { terminal.write('\x1b[2K\r'); wp(); shellState.cmdBuf = result; terminal.write(shellState.cmdBuf); }
        return;
      }

      if (code === 13) {
        terminal.writeln('');
        const cmd = shellState.cmdBuf.trim();
        if (cmd) { shellState.hist.push(cmd); shellState.histIdx = shellState.hist.length; shell.handleCmd(cmd, terminal, paneId, getCtx()); }
        shellState.cmdBuf = ''; wp();
      } else if (code === 8 || code === 127) {
        if (shellState.cmdBuf.length > 0) { shellState.cmdBuf = shellState.cmdBuf.slice(0, -1); terminal.write('\b \b'); }
      } else if (code === 38) {
        if (shellState.histIdx > 0) { terminal.write('\x1b[2K\r'); wp(); shellState.histIdx--; shellState.cmdBuf = shellState.hist[shellState.histIdx]; terminal.write(shellState.cmdBuf); }
      } else if (code === 40) {
        terminal.write('\x1b[2K\r'); wp();
        if (shellState.histIdx < shellState.hist.length - 1) { shellState.histIdx++; shellState.cmdBuf = shellState.hist[shellState.histIdx]; terminal.write(shellState.cmdBuf); }
        else { shellState.histIdx = shellState.hist.length; shellState.cmdBuf = ''; }
      } else if (ctrl && domEvent.key === 'c') {
        terminal.writeln('^C'); shellState.cmdBuf = ''; wp();
      } else if (ctrl && domEvent.key === 'l') {
        terminal.clear(); wp();
      } else if (!ctrl && !meta && key.length === 1) {
        shellState.cmdBuf += key; terminal.write(key);
      }
    });

    if (fa) setTimeout(() => fa.fit(), 50);
  }

  function focusPaneById(paneId) {
    if (focusedPaneId === paneId) return;
    focusedPaneId = paneId;
    activePanePerTab.set(state.activeTabId, paneId);
    qtXterm.querySelectorAll('.qt-pane').forEach(el => {
      el.classList.toggle('focused', el.dataset.paneId === paneId);
    });
    focusPane(paneId);
  }

  function focusPane(paneId) {
    const inst = paneInstances.get(paneId);
    if (inst) inst.terminal.focus();
  }

  function fitAllPanes() {
    paneInstances.forEach(inst => { if (inst.fitAddon) try { inst.fitAddon.fit(); } catch(e) {} });
  }

  function setupDividerDrag(divider, node, leftEl, rightEl) {
    divider.addEventListener('mousedown', (e) => {
      e.preventDefault();
      divider.classList.add('dragging');
      const isH = node.dir === 'h';
      const startPos = isH ? e.clientX : e.clientY;
      const total = isH ? leftEl.parentElement.offsetWidth : leftEl.parentElement.offsetHeight;
      const startLeft = parseFloat(leftEl.style.flex) || 50;
      const startRight = parseFloat(rightEl.style.flex) || 50;

      function onMove(e2) {
        const delta = (isH ? e2.clientX : e2.clientY) - startPos;
        const pctDelta = (delta / total) * 100;
        const newLeft = Math.max(10, Math.min(90, startLeft + pctDelta));
        const newRight = startLeft + startRight - newLeft;
        leftEl.style.flex = newLeft + '%';
        rightEl.style.flex = newRight + '%';
        node.sizes = [newLeft, newRight];
        fitAllPanes();
      }

      function onUp() {
        divider.classList.remove('dragging');
        document.removeEventListener('mousemove', onMove);
        document.removeEventListener('mouseup', onUp);
      }

      document.addEventListener('mousemove', onMove);
      document.addEventListener('mouseup', onUp);
    });
  }

  function splitPane(paneId, direction) {
    const tabId = state.activeTabId;
    let tree = paneTrees.get(tabId);
    if (!tree) return null;

    const newPaneId = 'p' + state.nextPaneId++;

    function doSplit(node) {
      if (node.type === 'leaf' && node.id === paneId) {
        return {
          type: 'split', dir: direction,
          children: [{ type: 'leaf', id: node.id }, { type: 'leaf', id: newPaneId }],
          sizes: [50, 50]
        };
      }
      if (node.type === 'split') {
        return { ...node, children: [doSplit(node.children[0]), doSplit(node.children[1])] };
      }
      return node;
    }

    tree = doSplit(tree);
    paneTrees.set(tabId, tree);
    focusedPaneId = newPaneId;
    activePanePerTab.set(tabId, newPaneId);
    renderPanes();
    return newPaneId;
  }

  function closePane(paneId) {
    const tabId = state.activeTabId;
    let tree = paneTrees.get(tabId);
    if (!tree || tree.type === 'leaf') return;

    function removeLeaf(node) {
      if (node.type === 'leaf') return node;
      if (node.children[0].type === 'leaf' && node.children[0].id === paneId) return node.children[1];
      if (node.children[1].type === 'leaf' && node.children[1].id === paneId) return node.children[0];
      return { ...node, children: [removeLeaf(node.children[0]), removeLeaf(node.children[1])] };
    }

    const inst = paneInstances.get(paneId);
    if (inst) { inst.terminal.dispose(); paneInstances.delete(paneId); }

    tree = removeLeaf(tree);
    paneTrees.set(tabId, tree);
    const leaves = collectLeaves(tree);
    focusedPaneId = leaves[0];
    activePanePerTab.set(tabId, focusedPaneId);
    renderPanes();
  }

  window.addEventListener('resize', () => { if (mode === 'interactive') fitAllPanes(); });
});
