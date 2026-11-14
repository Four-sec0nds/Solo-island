(() => {
  let host = location.hostname, origin = location.origin;
  if (!host && ['about:', 'blob:'].includes(location.protocol)) {
    try { host = window.parent.location.hostname; origin = window.parent.location.origin; } catch {}
  }
  const provider = ['claude.ai','www.claude.ai'].includes(host) ? 'claude'
    : ['chatgpt.com','www.chatgpt.com'].includes(host) ? 'codex' : null;
  if (!provider) return;
  window.addEventListener('message', message => {
    if (message.source !== window || message.origin !== origin || message.data?.source !== 'solo-island-agent') return;
    const event = message.data.event;
    if (!event || !['host','provider','session','state'].every(key => Object.hasOwn(event,key))
        || Object.keys(event).some(key => !['host','provider','session','state','elapsedSeconds'].includes(key))
        || (Object.hasOwn(event,'elapsedSeconds') && (typeof event.elapsedSeconds !== 'number' || !Number.isFinite(event.elapsedSeconds) || event.elapsedSeconds < 0 || event.elapsedSeconds > 2678400))
        || event.host !== host || event.provider !== provider
        || typeof event.session !== 'string' || !/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(event.session)
        || !['start','working','finished','interrupted'].includes(event.state)) return;
    chrome.runtime.sendMessage(event, () => { void chrome.runtime.lastError; });
  });
})();
