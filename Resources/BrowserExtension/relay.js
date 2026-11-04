(() => {
  const host = location.hostname;
  const provider = ['claude.ai','www.claude.ai'].includes(host) ? 'claude'
    : ['chatgpt.com','www.chatgpt.com'].includes(host) ? 'codex' : null;
  if (!provider || window.top !== window) return;
  window.addEventListener('message', message => {
    if (message.source !== window || message.origin !== location.origin || message.data?.source !== 'solo-island-agent') return;
    const event = message.data.event;
    if (!event || Object.keys(event).sort().join(',') !== 'host,provider,session,state'
        || event.host !== host || event.provider !== provider
        || typeof event.session !== 'string' || !/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(event.session)
        || !['start','working','finished','interrupted'].includes(event.state)) return;
    chrome.runtime.sendMessage(event, () => { void chrome.runtime.lastError; });
  });
})();
