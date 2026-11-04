const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../../Resources/BrowserExtension/observer.js'),'utf8');
function fixture(host='chatgpt.com', options={}) {
 let busy=false,now=1000;const messages=[],listeners={};
 const element={hidden:false,getAttribute:()=>null,getClientRects:()=>[{}]};
 const location={hostname:host,pathname:'/c/fixture',href:'https://'+host+'/c/fixture',origin:'https://'+host};
 const document={documentElement:{},querySelectorAll:s=>busy&&s===(options.selector || '[data-testid="stop-button"]')?[element]:[],addEventListener:(n,f)=>listeners[n]=f};
 const window={fetch:options.fetch,XMLHttpRequest:options.XHR,webkit:{messageHandlers:{soloAgent:{postMessage:m=>messages.push(JSON.parse(JSON.stringify(m)))}}},addEventListener:(n,f)=>listeners[n]=f};window.top=window;
 const context={window,document,location,Date:{now:()=>now},crypto:{randomUUID:()=> 'A25F8B42-7C90-4DA8-83B7-4C4033A70210'},MutationObserver:class{observe(){}},setInterval:()=>{},setTimeout:()=>{},Array,URL,Uint8Array,Reflect,Promise,Proxy,Set,Map,WeakMap,Symbol};
 vm.createContext(context);vm.runInContext(source,context);
 return {messages,listeners,window,location,setBusy:v=>busy=v,advance:v=>now+=v,check:()=>window.__soloAgentObserver?.check()};
}
test('real streaming controls start and finish a web turn without reading content',()=>{
 const f=fixture();f.check();assert.equal(f.messages.length,0);
 f.setBusy(true);f.check();assert.equal(f.messages[0].state,'start');
 f.advance(16000);f.check();assert.equal(f.messages[1].state,'working');
 f.setBusy(false);f.check();f.advance(1000);f.check();assert.equal(f.messages[2].state,'finished');
 for(const message of f.messages)assert.deepEqual(Object.keys(message).sort(),['host','provider','session','state']);
});
test('unsupported sites and login forms do not become tasks',()=>{
 const bad=fixture('auth.openai.com');assert.equal(bad.window.__soloAgentObserver,undefined);
 const f=fixture();f.listeners.submit({target:{querySelector:s=>s==='input[type="password"]'?{}:null}});assert.equal(f.messages.length,0);
});
test('a submitted prompt that never starts times out instead of running forever',()=>{
 const f=fixture('claude.ai');f.listeners.submit({target:{querySelector:s=>s.includes('textarea')?{}:null}});
 assert.equal(f.messages[0].provider,'claude');assert.equal(f.messages[0].state,'start');
 f.advance(16000);f.check();assert.equal(f.messages.at(-1).state,'interrupted');
});
test('closing the page interrupts a running turn',()=>{
 const f=fixture();f.setBusy(true);f.check();f.listeners.pagehide();assert.equal(f.messages.at(-1).state,'interrupted');
});

test('Stop streaming and Claude controls are detected without submit events',()=>{
 for(const [host,selector] of [['chatgpt.com','button[aria-label="Stop streaming" i]'],['claude.ai','button[aria-label="Stop response" i]']]){
  const f=fixture(host,{selector});f.setBusy(true);f.check();assert.equal(f.messages[0].state,'start');
  f.setBusy(false);f.check();f.advance(1000);f.check();assert.equal(f.messages.at(-1).state,'finished');
 }
});
test('brief DOM replacements do not restart the elapsed session',()=>{
 const f=fixture();f.setBusy(true);f.check();const id=f.messages[0].session;
 f.setBusy(false);f.check();f.advance(500);f.setBusy(true);f.check();
 assert.equal(f.messages.length,1);assert.equal(f.messages[0].session,id);
});
test('the real fetch reader tracks both providers and preserves response and chunks without reading prompts',async()=>{
 for(const host of ['chatgpt.com','claude.ai']){
  let controller;const chunk=new Uint8Array([1,2,3]);
  const response=new Response(new ReadableStream({start(c){controller=c}}));
  const f=fixture(host,{fetch:async()=>response});
  const url=host==='claude.ai'?'https://claude.ai/api/organizations/org/chat_conversations/conversation/completion':'https://chatgpt.com/backend-api/f/conversation';
  const init={method:'POST',get body(){throw Error('prompt must not be read')}};
  const received=await f.window.fetch(url,init);assert.equal(received,response);
  assert.equal(f.messages[0].state,'start');const reader=received.body.getReader();
  controller.enqueue(chunk);assert.equal((await reader.read()).value,chunk);
  f.location.pathname='/c/new';f.advance(16000);f.check();assert.equal(f.messages.at(-1).state,'working');
  controller.close();assert.equal((await reader.read()).done,true);
  f.advance(1000);f.check();assert.equal(f.messages.at(-1).state,'finished');
 }
});
test('native fetch errors interrupt the timer and retain the original error',async()=>{
 const error=new Error('network');const f=fixture('chatgpt.com',{fetch:async()=>{throw error}});
 await assert.rejects(f.window.fetch('https://chatgpt.com/backend-api/f/conversation',{method:'POST'}),value=>value===error);
 assert.deepEqual(f.messages.map(v=>v.state),['start','interrupted']);
});
test('normal requests and other hosts never become work sessions',async()=>{
 const response=new Response('ok');const f=fixture('chatgpt.com',{fetch:async()=>response});
 for(const url of ['https://chatgpt.com/backend-api/me','https://other.test/backend-api/f/conversation'])assert.equal(await f.window.fetch(url,{method:'POST'}),response);
 assert.equal(f.messages.length,0);
});
test('cloud tasks use actual task status metadata without reading messages or prompting fields',async()=>{
 let state='in_progress';const item={id:'task_test',task_status_display:{latest_turn_status_display:{get turn_status(){return state}}},get prompt(){throw Error('private')},get messages(){throw Error('private')}};
 const body={items:[item]};const response={ok:true,json:async()=>body};
 const f=fixture('chatgpt.com',{fetch:async()=>response});
 const url='https://chatgpt.com/backend-api/wham/tasks';
 assert.equal(await(await f.window.fetch(url)).json(),body);assert.equal(f.messages[0].state,'start');
 f.advance(16000);f.check();assert.equal(f.messages[1].state,'working');
 state='completed';await(await f.window.fetch(url)).json();assert.equal(f.messages[2].state,'finished');
 await(await f.window.fetch(url)).json();assert.equal(f.messages.length,3);
});
test('stream cancellation keeps the native consumer result and stops activity',async()=>{
 const response=new Response(new ReadableStream({cancel:()=>{}}));const f=fixture('chatgpt.com',{fetch:async()=>response});
 const reader=(await f.window.fetch('https://chatgpt.com/backend-api/f/conversation',{method:'POST'})).body.getReader();
 assert.equal(await reader.cancel(),undefined);assert.equal(f.messages.at(-1).state,'interrupted');
});
test('async iteration preserves chunks and reports stream completion',async()=>{
 const chunk=new Uint8Array([7,8]);const response=new Response(new ReadableStream({start(c){c.enqueue(chunk);c.close()}}));
 const f=fixture('chatgpt.com',{fetch:async()=>response});const received=await f.window.fetch('https://chatgpt.com/backend-api/f/conversation',{method:'POST'});
 const chunks=[];for await(const value of received.body)chunks.push(value);assert.equal(chunks[0],chunk);
 f.advance(1000);f.check();assert.equal(f.messages.at(-1).state,'finished');
});
test('XHR lifecycle finishes after response and retains all original call arguments',()=>{
 class XHR{constructor(){this.listeners={};this.status=200}open(...args){this.opened=args}send(...args){this.sent=args}addEventListener(n,f){this.listeners[n]=f}}
 const f=fixture('claude.ai',{XHR});const xhr=new f.window.XMLHttpRequest();const body={private:'unchanged'};
 const url='https://claude.ai/api/organizations/org/chat_conversations/chat/completion';xhr.open('POST',url,true);xhr.send(body);
 assert.deepEqual(xhr.opened,['POST',url,true]);assert.equal(xhr.sent[0],body);assert.equal(f.messages[0].state,'start');
 xhr.listeners.loadend();f.advance(1000);f.check();assert.equal(f.messages.at(-1).state,'finished');
});
test('stale cloud metadata does not fabricate heartbeats forever',async()=>{
 const response={ok:true,json:async()=>({id:'task_test',current_assistant_turn:{turn_status:'in_progress'}})};
 const f=fixture('chatgpt.com',{fetch:async()=>response});await(await f.window.fetch('https://chatgpt.com/backend-api/wham/tasks/task_test')).json();
 f.advance(91000);f.check();assert.deepEqual(f.messages.map(v=>v.state),['start']);
});
test('suspended windows stop heartbeats and resume new requests when reopened',async()=>{
 let response=new Response(new ReadableStream({start(c){c.close()}}));const f=fixture('chatgpt.com',{fetch:async()=>response});
 await f.window.fetch('https://chatgpt.com/backend-api/f/conversation',{method:'POST'});
 f.window.__soloAgentObserver.suspend();const count=f.messages.length;
 f.advance(16000);f.check();await f.window.fetch('https://chatgpt.com/backend-api/f/conversation',{method:'POST'});assert.equal(f.messages.length,count);
 f.window.__soloAgentObserver.resume();response=new Response(new ReadableStream({start(c){c.close()}}));
 await f.window.fetch('https://chatgpt.com/backend-api/f/conversation',{method:'POST'});assert.equal(f.messages.at(-1).state,'start');
});
