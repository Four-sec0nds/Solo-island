(() => {
  if (window.__soloAgentObserver || window.top !== window) return;
  const host = location.hostname;
  const provider = ['claude.ai', 'www.claude.ai'].includes(host) ? 'claude'
    : ['chatgpt.com', 'www.chatgpt.com'].includes(host) ? 'codex' : null;
  if (!provider) return;
  const uuid = () => {
    if (typeof crypto.randomUUID === 'function') return crypto.randomUUID();
    const bytes = crypto.getRandomValues(new Uint8Array(16)); bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
    const h = Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
    return `${h.slice(0,8)}-${h.slice(8,12)}-${h.slice(12,16)}-${h.slice(16,20)}-${h.slice(20)}`;
  };
  let session = '', busy = false, seenBusy = false, pendingUntil = 0, quietSince = null, lastHeartbeat = 0, suspended = false;
  const requests = new Set(), tasks = new Map();
  const send = (state, id = session) => {
    const payload = {provider, host, session: id, state};
    try {
      if (window.webkit?.messageHandlers?.soloAgent) window.webkit.messageHandlers.soloAgent.postMessage(payload);
      else if (typeof chrome !== 'undefined' && chrome.runtime?.id) {
        chrome.runtime.sendMessage(payload, () => { void chrome.runtime.lastError; });
      } else window.postMessage({source: 'solo-island-agent', event: payload}, location.origin);
    } catch { /* A disconnected bridge must never break the site's request. */ }
  };
  const visible = element => !!element && !element.hidden && element.getAttribute('aria-hidden') !== 'true'
    && element.getClientRects().length > 0;
  const busySelectors = [
    '[data-testid="stop-button"]', '[data-testid="stop-generation-button"]', '[data-testid="stop-response-button"]',
    'button[aria-label="Stop streaming" i]', 'button[aria-label="Stop generating" i]',
    'button[aria-label="Stop response" i]', 'button[aria-label="Stop" i]',
    'button[aria-label="Остановить генерацию"]', 'button[aria-label="Остановить ответ"]',
    '[data-is-streaming="true"]', '[data-task-status="running"]', '[data-task-status="in_progress"]'
  ];
  const isBusy = () => busySelectors.some(selector => Array.from(document.querySelectorAll(selector)).some(visible));
  const start = () => {
    if (busy || suspended) return;
    session = uuid(); busy = true; seenBusy = false; quietSince = null;
    pendingUntil = Date.now() + 15000; lastHeartbeat = Date.now(); send('start');
  };
  const finish = state => {
    if (!busy) return;
    send(state); busy = false; seenBusy = false; quietSince = null; requests.clear();
  };
  const check = () => {
    if (suspended) return;
    const streaming = isBusy();
    if (streaming && !busy) start();
    if (streaming || requests.size) { seenBusy = true; quietSince = null; }
    if (busy && !streaming && !requests.size) {
      if (seenBusy) {
        if (quietSince === null) quietSince = Date.now();
        if (Date.now() - quietSince >= 900) finish('finished');
      } else if (Date.now() > pendingUntil) finish('interrupted');
    }
    if (busy && Date.now() - lastHeartbeat >= 15000) { lastHeartbeat = Date.now(); send('working'); }
    for (const task of tasks.values()) {
      if (task.active && Date.now() - task.observedAt < 90000 && Date.now() - task.heartbeat >= 15000) {
        send('working', task.session); task.heartbeat = Date.now();
      }
    }
  };
  // Inspect request routing and lifecycle only. Never inspect request bodies,
  // cookies, headers, response chunks, prompts or generated text.
  const classify = (input, init) => {
    try {
      const url = new URL(typeof input === 'string' || input instanceof URL ? input : input.url, location.href);
      if (url.hostname !== host) return null;
      const method = String(init?.method ?? input?.method ?? 'GET').toUpperCase();
      const path = url.pathname;
      if (provider === 'claude' && method === 'POST' && /^\/api\/organizations\/[^/]+\/chat_conversations\/[^/]+\/(?:completion|retry_completion)$/.test(path)) return {kind: 'stream'};
      if (provider === 'codex' && method === 'POST' && /^\/backend-api\/(?:f\/)?conversation(?:\/(?:resume|continue))?$/.test(path)) return {kind: 'stream'};
      if (provider === 'codex' && /^\/backend-api\/wham\/tasks(?:\/[^/]+)?\/?$/.test(path)) {
        return {kind: 'task', id: path.match(/\/tasks\/([^/]+)\/?$/)?.[1], created: method === 'POST' && /\/tasks\/?$/.test(path)};
      }
    } catch {}
    return null;
  };
  const taskMetadata = (value, route) => {
    if (suspended || !value || typeof value !== 'object') return;
    const items = Array.isArray(value.items) ? value.items.slice(0, 100) : [value];
    for (const item of items) {
      const task = item?.task ?? item;
      const id = task?.id ?? task?.task_id ?? route.id;
      if (typeof id !== 'string' || id.length > 512) continue;
      const display = task?.task_status_display ?? item?.task_status_display;
      const state = task?.current_assistant_turn?.turn_status ?? item?.current_assistant_turn?.turn_status
        ?? display?.latest_turn_status_display?.turn_status ?? display?.state
        ?? (route.created ? 'pending' : null);
      const active = ['pending', 'in_progress', 'running'].includes(state);
      const completed = ['completed', 'ready', 'applied'].includes(state);
      const interrupted = ['failed', 'cancelled', 'canceled', 'error'].includes(state);
      let record = tasks.get(id);
      if (active) {
        if (!record?.active) {
          if (tasks.size >= 128 && !record) {
            const old = Array.from(tasks).find(([,v]) => !v.active);
            if (old) tasks.delete(old[0]); else continue;
          }
          record = {session: uuid(), active: true, heartbeat: Date.now(), observedAt: Date.now()};
          tasks.set(id, record); send('start', record.session);
        }
        record.observedAt = Date.now();
      } else if (record?.active && (completed || interrupted)) {
        record.active = false; send(completed ? 'finished' : 'interrupted', record.session);
      }
    }
  };
  const endRequest = (token, failed = false) => {
    if (token.done) return; token.done = true;
    if (token.session !== session) return;
    requests.delete(token);
    if (failed && !requests.size && !isBusy()) finish('interrupted'); else check();
  };
  const watchMethod = (object, name, success, failure) => {
    if (typeof object?.[name] !== 'function') return;
    const original = object[name];
    Object.defineProperty(object, name, {configurable: true, writable: true, value: function(...args) {
      let result;
      try { result = Reflect.apply(original, this, args); }
      catch (error) { failure(); throw error; }
      return Promise.resolve(result).then(value => { try { success(value); } catch {} return value; }, error => { failure(); throw error; });
    }});
  };
  const watchResponse = (response, route, token) => {
    const success = value => { if (route.kind === 'task') taskMetadata(value, route); else endRequest(token); };
    const failed = () => { if (token) endRequest(token, true); };
    try {
      // Observe only parsed task status fields in objects the site itself reads.
      // Return the original object/response/chunks to the site's own consumer.
      for (const method of route.kind === 'task' ? ['json'] : ['json','text','arrayBuffer','blob','formData','bytes']) {
        watchMethod(response, method, success, failed);
      }
      if (route.kind === 'stream') {
        if (!response.body) { endRequest(token); return response; }
        const body = response.body, original = body.getReader;
        if (typeof original === 'function') Object.defineProperty(body, 'getReader', {configurable: true, value: function(...args) {
          const reader = Reflect.apply(original, this, args);
          watchMethod(reader, 'read', value => { if (value.done) endRequest(token); }, failed);
          watchMethod(reader, 'cancel', () => endRequest(token, true), failed);
          return reader;
        }});
        const iterator = body[Symbol.asyncIterator];
        if (typeof iterator === 'function') Object.defineProperty(body, Symbol.asyncIterator, {configurable: true, value: function(...args) {
          const result = Reflect.apply(iterator, this, args);
          watchMethod(result, 'next', value => { if (value.done) endRequest(token); }, failed);
          watchMethod(result, 'return', () => endRequest(token, true), failed);
          return result;
        }});
      }
      const clone = response.clone;
      if (typeof clone === 'function') Object.defineProperty(response, 'clone', {configurable: true, value: function(...args) {
        return watchResponse(Reflect.apply(clone, this, args), route, token);
      }});
    } catch { if (token) endRequest(token, true); }
    return response;
  };
  if (typeof window.fetch === 'function') {
    window.fetch = new Proxy(window.fetch, {apply(target, receiver, args) {
      const route = classify(args[0], args[1]);
      if (!route || suspended) return Reflect.apply(target, receiver, args);
      let token;
      if (route.kind === 'stream') { start(); token = {session, done: false}; requests.add(token); seenBusy = true; }
      try {
        return Reflect.apply(target, receiver, args).then(response => {
          if (!response.ok) { if (token) endRequest(token, true); return response; }
          return watchResponse(response, route, token);
        }, error => { if (token) endRequest(token, true); throw error; });
      } catch (error) { if (token) endRequest(token, true); throw error; }
    }});
  }
  const XHR = window.XMLHttpRequest;
  if (XHR?.prototype) {
    const routes = new WeakMap(), open = XHR.prototype.open, sendRequest = XHR.prototype.send;
    XHR.prototype.open = function(method, url, ...rest) { routes.set(this, classify(url, {method})); return Reflect.apply(open, this, [method, url, ...rest]); };
    XHR.prototype.send = function(...args) {
      const route = routes.get(this);
      let token;
      if (!suspended && route?.kind === 'stream') {
        start(); token = {session, done:false}; requests.add(token); seenBusy = true;
        this.addEventListener('loadend', () => endRequest(token, this.status < 200 || this.status >= 400), {once:true});
      }
      try { return Reflect.apply(sendRequest, this, args); }
      catch (error) { if (token) endRequest(token, true); throw error; }
    };
  }
  document.addEventListener('submit', event => {
    const form = event.target;
    if (form?.querySelector?.('textarea, [contenteditable="true"]') && !form.querySelector('input[type="password"]')) start();
  }, true);
  document.addEventListener('click', event => {
    const button = event.target?.closest?.('button');
    if (button?.matches('[data-testid="send-button"], button[aria-label="Send message" i], button[aria-label="Send prompt" i], button[aria-label="Отправить сообщение"]') && !button.disabled) start();
  }, true);
  const suspend = () => {
    finish('interrupted');
    for (const task of tasks.values()) if (task.active) { task.active = false; send('interrupted', task.session); }
    suspended = true;
  };
  window.addEventListener('pagehide', suspend);
  window.addEventListener('pageshow', () => { suspended = false; check(); });
  let scheduled = false;
  const schedule = () => { if (!scheduled) { scheduled = true; setTimeout(() => { scheduled = false; check(); }, 180); } };
  const observe = () => {
    if (document.documentElement) new MutationObserver(schedule).observe(document.documentElement,
      {subtree:true, childList:true, attributes:true, attributeFilter:['aria-label','aria-hidden','data-is-streaming','data-task-status','disabled']});
  };
  if (document.documentElement) observe(); else document.addEventListener('DOMContentLoaded', observe, {once:true});
  setInterval(check, 1000);
  window.__soloAgentObserver = {installed: true, check, suspend, resume: () => { suspended = false; check(); }};
  check();
})();
