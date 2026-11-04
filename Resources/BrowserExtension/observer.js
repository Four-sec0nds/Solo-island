(() => {
  if (window.__soloAgentObserver || window.top !== window) return;
  const host = location.hostname;
  const provider = ['claude.ai', 'www.claude.ai'].includes(host) ? 'claude'
    : ['chatgpt.com', 'www.chatgpt.com'].includes(host) ? 'codex' : null;
  if (!provider) return;
  let session = crypto.randomUUID(), busy = false, seenBusy = false, pendingUntil = 0;
  let route = location.pathname, lastHeartbeat = 0;
  const visible = element => !!element && !element.hidden && element.getAttribute('aria-hidden') !== 'true'
    && element.getClientRects().length > 0;
  const isBusy = () => [
    '[data-testid="stop-button"]', 'button[aria-label="Stop generating"]',
    'button[aria-label="Stop response"]', 'button[aria-label="Stop Response"]',
    'button[aria-label="Остановить генерацию"]', 'button[aria-label="Остановить ответ"]',
    '[data-is-streaming="true"]', '[data-task-status="running"]', '[data-task-status="in_progress"]'
  ].some(selector => Array.from(document.querySelectorAll(selector)).some(visible));
  const send = state => {
    const payload = {provider, host, session, state};
    if (window.webkit?.messageHandlers?.soloAgent) window.webkit.messageHandlers.soloAgent.postMessage(payload);
    else if (typeof chrome !== 'undefined' && chrome.runtime?.id) {
      chrome.runtime.sendMessage(payload, () => { void chrome.runtime.lastError; });
    }
  };
  const start = () => {
    if (busy) return;
    session = crypto.randomUUID(); busy = true; seenBusy = false;
    pendingUntil = Date.now() + 15000; lastHeartbeat = Date.now(); send('start');
  };
  const check = () => {
    if (route !== location.pathname) {
      if (busy) send('interrupted');
      busy = false; seenBusy = false; route = location.pathname;
    }
    const streaming = isBusy();
    if (streaming && !busy) start();
    if (streaming) seenBusy = true;
    if (busy && !streaming && (seenBusy || Date.now() > pendingUntil)) {
      send(seenBusy ? 'finished' : 'interrupted'); busy = false; seenBusy = false;
    }
    if (busy && Date.now() - lastHeartbeat > 15000) { lastHeartbeat = Date.now(); send('working'); }
  };
  document.addEventListener('submit', event => {
    const form = event.target;
    if (form?.querySelector?.('textarea, [contenteditable="true"]') && !form.querySelector('input[type="password"]')) start();
  }, true);
  document.addEventListener('click', event => {
    const button = event.target.closest?.('button');
    if (button?.matches('[data-testid="send-button"], button[aria-label="Send message"], button[aria-label="Send Message"], button[aria-label="Отправить сообщение"]') && !button.disabled) start();
  }, true);
  window.addEventListener('pagehide', () => { if (busy) send('interrupted'); busy = false; });
  let scheduled = false;
  const schedule = () => {
    if (scheduled) return; scheduled = true;
    setTimeout(() => { scheduled = false; check(); }, 180);
  };
  new MutationObserver(schedule).observe(document.documentElement, {subtree:true, childList:true, attributes:true, attributeFilter:['aria-label','aria-hidden','data-is-streaming','data-task-status','disabled']});
  setInterval(check, 1000);
  window.__soloAgentObserver = {check};
  check();
})();
