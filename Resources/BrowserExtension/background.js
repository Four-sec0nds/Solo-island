const activeTabs = new Map();
chrome.runtime.onMessage.addListener((message, sender, reply) => {
  const host = (() => { try { return new URL(sender.url || '').hostname; } catch { return ''; } })();
  if (!['claude.ai','www.claude.ai','chatgpt.com','www.chatgpt.com'].includes(host) || message.host !== host) return false;
  if (sender.tab?.id !== undefined) {
    if (['start','working'].includes(message.state)) activeTabs.set(sender.tab.id, message);
    else activeTabs.delete(sender.tab.id);
  }
  chrome.runtime.sendNativeMessage('app.solo.island', message, result => {
    reply(chrome.runtime.lastError ? {ok:false} : result);
  });
  return true;
});

chrome.tabs.onRemoved.addListener(tabID => {
  const last = activeTabs.get(tabID); activeTabs.delete(tabID);
  if (last) chrome.runtime.sendNativeMessage('app.solo.island', {...last, state:'interrupted'}, () => { void chrome.runtime.lastError; });
});
