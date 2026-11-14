(() => {
  if (window.__soloAgentStatus) return;
  const visible = element => !element.hidden && element.getAttribute('aria-hidden') !== 'true' && element.getClientRects().length > 0;
  const normal = text => String(text || '').replace(/\s+/g,' ').trim();
  const duration = text => {
    text = normal(text).replace(/^[\s:·•–-]*(?:for\s+)?/i,'').replace(/[\s…›»>]+$/g,'');
    if (/^\d{1,3}:\d{2}(?::\d{2})?$/.test(text)) {
      const parts=text.split(':').map(Number);if(parts.slice(1).some(x=>x>59))return;
      return parts.reduce((a,b)=>a*60+b,0);
    }
    let seconds=0,found=false;
    const rest=text.replace(/(\d+(?:[.,]\d+)?)\s*(час(?:а|ов)?|ч|hours?|hrs?|h|мин(?:ут(?:а|ы)?)?|minutes?|mins?|m|сек(?:унд(?:а|ы)?)?|с|seconds?|secs?|s)(?![a-zа-я])/gi,(_,n,u)=>{
      const unit=u.toLowerCase();seconds+=Number(n.replace(',','.'))*(/^(?:ч|h)/.test(unit)?3600:/^(?:м|m)/.test(unit)?60:1);found=true;return '';
    }).replace(/[\s,·]+/g,'');
    if(found && !rest && Number.isFinite(seconds) && seconds<=2678400)return seconds;
  };
  const parse = text => {
    text=normal(text);if(!text || text.length>240)return;
    let match=text.match(/^(?:Выполнено\s*за|Завершено\s*за|Worked\s+for|Completed\s+(?:in|after)|Finished\s+in)\s*(.+)$/i);
    if(match){const elapsedSeconds=duration(match[1]);if(elapsedSeconds!==undefined)return {state:'finished',elapsedSeconds};return;}
    match=text.match(/^(Работаю|Работает|Выполняется|Выполняю|В работе|Думаю|Думает|Публикация|Working|Running|Thinking|Publishing|In progress|Queued|В очереди)([\s\S]*)$/i);
    if(match){
      const tail=normal(match[2]).replace(/^[\s….:·•–-]+|[\s…]+$/g,'');
      const elapsedSeconds=tail?duration(tail):undefined;
      if(!tail || elapsedSeconds!==undefined)return {state:'working',elapsedSeconds,persistent:!/^(?:Thinking|Думаю|Думает)$/i.test(match[1])};
    }
    if(/^(?:Task completed|Work completed|Задача завершена|Работа завершена)$/i.test(text))return {state:'finished'};
    if(/^(?:Stopped|Cancelled|Canceled|Остановлено|Прервано)(?:[\s…]*)$/i.test(text))return {state:'interrupted'};
  };
  const read = () => {
    const result={cloud:/\/codex(?:\/|$)/.test(location.pathname || '')};
    // Read only UI status controls and composer placeholders, never message bodies.
    const placeholders=document.querySelectorAll('textarea[placeholder], [contenteditable][data-placeholder], [contenteditable][aria-label], [data-placeholder]');
    for(const node of placeholders){
      const label=node.getAttribute('placeholder') || node.getAttribute('data-placeholder') || node.getAttribute('aria-label') || '';
      if(/(?:ask|request)\s+(?:for\s+)?follow[- ]up\s+changes|запросите\s+внесение\s+дополнительных\s+изменений/i.test(label))result.cloud=true;
    }
    const controls=document.querySelectorAll('button, [role="button"], summary, [role="status"], [data-testid="task-status"], [data-testid="task-status-display"], [data-testid="turn-status"], [data-testid="agent-turn-status"], [data-testid="work-summary"]');
    let index=0;
    for(const node of controls){
      index++;
      if(!visible(node) || node.closest?.('.markdown, .prose, [data-message-author-role="user"], [contenteditable="true"]'))continue;
      const status=parse(node.getAttribute('aria-label')) || parse(node.innerText || node.textContent);
      if(!status)continue;
      const turn=node.closest?.('[data-message-id], [data-turn-id], [data-testid^="conversation-turn-"]');
      const scope=turn?.getAttribute('data-message-id') || turn?.getAttribute('data-turn-id') || turn?.getAttribute('data-testid') || 'slot:'+index;
      result[status.state]={...status,key:scope+':'+status.state+':'+(status.elapsedSeconds ?? '')};
    }
    return result;
  };
  window.__soloAgentStatus={read,parse,duration};
})();
