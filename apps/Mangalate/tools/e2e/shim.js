// Giả lập API `browser` của Safari Web Extension cho trang thử: runtime.sendMessage đi tới
// tools/e2e/server.py (đóng vai background.js + appex), storage là bộ nhớ trong trang.
(() => {
  "use strict";
  const store = { "mangalate:sites": [location.hostname], consentAccepted: true };
  const listeners = [];

  async function post(message) {
    const response = await fetch("/bg", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(message),
    });
    return response.json();
  }

  function pick(keys) {
    if (keys === null || keys === undefined) return { ...store };
    if (typeof keys === "string") return keys in store ? { [keys]: store[keys] } : {};
    if (Array.isArray(keys)) return Object.fromEntries(keys.filter((key) => key in store).map((key) => [key, store[key]]));
    return Object.fromEntries(Object.entries(keys).map(([key, fallback]) => [key, key in store ? store[key] : fallback]));
  }

  globalThis.browser = {
    runtime: {
      sendMessage: (message) => post(message),
      onMessage: { addListener: (listener) => listeners.push(listener) },
    },
    storage: {
      local: {
        get: async (keys) => pick(keys),
        set: async (items) => { Object.assign(store, items); },
        remove: async (keys) => { for (const key of [].concat(keys)) delete store[key]; },
      },
      onChanged: { addListener: () => {} },
    },
  };

  let blocks = null;
  globalThis.__mangalateBlocks = (value) => { blocks = value; };

  globalThis.__harness = {
    store,
    blocks: () => blocks,
    send: (message) => Promise.all(listeners.map((listener) => listener(message))),
    fabText: () => {
      const host = document.getElementById("mangalate-ui");
      const fab = host && host.shadowRoot && host.shadowRoot.querySelector(".fab");
      return fab && !fab.hidden ? fab.textContent : "";
    },
    panelText: () => {
      const host = document.getElementById("mangalate-ui");
      const panel = host && host.shadowRoot && host.shadowRoot.querySelector(".panel");
      return panel && !panel.hidden ? panel.textContent : "";
    },
    clickFab: () => {
      document.getElementById("mangalate-ui").shadowRoot.querySelector(".fab").click();
    },
  };
})();
