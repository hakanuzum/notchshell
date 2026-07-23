/* ═══════════════════════════════════════════════
   SCROLL DEMO SCRIPT
   Each step: { cmd, out[], onComplete?(ctx), onRevert?(ctx), promptChar?, skipPrompt? }
   onComplete fires when step scrolls into view.
   onRevert fires when scrolling back past the step.
   ═══════════════════════════════════════════════ */

window.MQ_DEMO = [
  // 1. Create a new tab for dev server
  {
    cmd: "hakuke new-tab server",
    out: [
      '<span class="qt-ok">Created tab</span> <span class="qt-jk">"server"</span> <span class="qt-out">(2 tabs open)</span>'
    ],
    onComplete: (ctx) => {
      if (!ctx.state.tabs.find(t => t.title === 'server')) {
        const tab = { id: ctx.state.nextTabId++, title: 'server' };
        ctx.state.tabs.push(tab);
        const pid = 'p' + ctx.state.nextPaneId++;
        ctx.paneTrees.set(tab.id, { type: 'leaf', id: pid });
        ctx.activePanePerTab.set(tab.id, pid);
        ctx.state.activeTabId = tab.id;
        ctx.renderTabs();
      }
    },
    onRevert: (ctx) => {
      const serverTab = ctx.state.tabs.find(t => t.title === 'server');
      if (serverTab) {
        ctx.state.tabs = ctx.state.tabs.filter(t => t.id !== serverTab.id);
        ctx.paneTrees.delete(serverTab.id);
        ctx.activePanePerTab.delete(serverTab.id);
        ctx.state.activeTabId = ctx.state.tabs[0].id;
        ctx.renderTabs();
      }
    }
  },

  // 2. Launch Claude — shows banner
  {
    cmd: "claude",
    out: [
      '',
      { html: '<span style="color:#C2654A"> \u2590\u259B\u2588\u2588\u2588\u259C\u258C</span>   <span style="color:#fff;font-weight:bold">Claude Code</span> <span class="qt-out">v2.1.71</span>', cls: 'qt-claude' },
      { html: '<span style="color:#C2654A">\u259D\u259C\u2588\u2588\u2588\u2588\u2588\u259B\u2598</span>  <span class="qt-out">Opus 4.6 with high effort \u00b7 Claude Max</span>', cls: 'qt-claude' },
      { html: '<span style="color:#C2654A">  \u2598\u2598 \u259D\u259D</span>    <span class="qt-out">~/Projects/hakuke</span>', cls: 'qt-claude' },
      '',
    ]
  },

  // 3. Type prompt in Claude — Claude splits
  {
    cmd: "start a python dev server on port 8080 in hakuke",
    promptChar: '>',
    out: [
      '',
      '<span class="qt-out">  I\'ll split the terminal and start a Python dev server in the right pane.</span>',
      '',
      '<span style="color:#636366">  Tool use</span>',
      '<span style="color:#636366">     <span class="qt-jk">hakuke</span> - <span style="color:#fff">split</span>(direction: <span class="qt-js">"h"</span>) <span style="color:#636366">(MCP)</span></span>',
      '<span style="color:#636366">     Split current pane horizontally.</span>',
    ],
    onComplete: (ctx) => {
      ctx.showDemoSplit();
    },
    onRevert: (ctx) => {
      ctx.hideDemoSplit();
    }
  },

  // 4. Claude executes in the split pane (continuation, no prompt)
  {
    cmd: '',
    skipPrompt: true,
    out: [
      '',
      '<span style="color:#636366">  Tool use</span>',
      '<span style="color:#636366">     <span class="qt-jk">hakuke</span> - <span style="color:#fff">execute</span>(command: <span class="qt-js">"python3 -m http.server 8080"</span>) <span style="color:#636366">(MCP)</span></span>',
      '<span style="color:#636366">     Execute a shell command in a terminal tab. Sends text and presses Enter.</span>',
      '',
      '<span class="qt-ok">  \u2713 Done. Server is running on port 8080.</span>',
    ],
    onComplete: (ctx) => {
      ctx.fillDemoSplit();
    },
    onRevert: (ctx) => {
      ctx.unfillDemoSplit();
    }
  },

  // 5. Send Ctrl+C to stop the server, then close tab
  {
    cmd: '',
    skipPrompt: true,
    out: [
      '',
      '<span style="color:#636366">  Tool use</span>',
      '<span style="color:#636366">     <span class="qt-jk">hakuke</span> - <span style="color:#fff">control_char</span>(char: <span class="qt-js">"c"</span>) <span style="color:#636366">(MCP)</span></span>',
      '<span style="color:#636366">     Send Ctrl+C to stop the running process.</span>',
      '',
      '<span class="qt-ok">  ^C sent.</span> <span class="qt-out">Server stopped.</span>',
      '',
      '<span style="color:#636366">  Tool use</span>',
      '<span style="color:#636366">     <span class="qt-jk">hakuke</span> - <span style="color:#fff">close_session</span>(tab: <span class="qt-js">"server"</span>) <span style="color:#636366">(MCP)</span></span>',
      '<span style="color:#636366">     Close a terminal tab.</span>',
      '',
      '<span class="qt-ok">  Tab closed.</span> <span class="qt-out">1 tab remaining.</span>',
    ],
    onComplete: (ctx) => {
      ctx.killDemoSplit();
      setTimeout(() => {
        ctx.hideDemoSplit();
        const serverTab = ctx.state.tabs.find(t => t.title === 'server');
        if (serverTab) {
          ctx.state.tabs = ctx.state.tabs.filter(t => t.id !== serverTab.id);
          ctx.paneTrees.delete(serverTab.id);
          ctx.activePanePerTab.delete(serverTab.id);
          ctx.state.activeTabId = ctx.state.tabs[0].id;
          ctx.renderTabs();
        }
      }, 400);
    },
    onRevert: (ctx) => {
      // Re-add server tab and show filled split
      if (!ctx.state.tabs.find(t => t.title === 'server')) {
        const tab = { id: ctx.state.nextTabId++, title: 'server' };
        ctx.state.tabs.push(tab);
        const pid = 'p' + ctx.state.nextPaneId++;
        ctx.paneTrees.set(tab.id, { type: 'leaf', id: pid });
        ctx.activePanePerTab.set(tab.id, pid);
        ctx.state.activeTabId = tab.id;
        ctx.renderTabs();
      }
      ctx.showDemoSplit();
      ctx.fillDemoSplit();
    }
  },

  // 6. Hide terminal (end of demo)
  {
    cmd: "hakuke hide",
    out: [
      '<span class="qt-ok">Terminal hidden.</span> <span class="qt-out">Press Option+Space to show.</span>'
    ]
  }
];
