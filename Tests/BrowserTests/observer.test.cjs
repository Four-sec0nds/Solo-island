const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../../Resources/BrowserExtension/observer.js'),'utf8');
function fixture(host='chatgpt.com') {
 let busy=false,now=1000;const messages=[],listeners={};
 const element={hidden:false,getAttribute:()=>null,getClientRects:()=>[{}]};
 const location={hostname:host,pathname:'/c/fixture'};
 const document={documentElement:{},querySelectorAll:s=>busy&&s==='[data-testid="stop-button"]'?[element]:[],addEventListener:(n,f)=>listeners[n]=f};
 const window={webkit:{messageHandlers:{soloAgent:{postMessage:m=>messages.push(JSON.parse(JSON.stringify(m)))}}},addEventListener:(n,f)=>listeners[n]=f};window.top=window;
 const context={window,document,location,Date:{now:()=>now},crypto:{randomUUID:()=> 'A25F8B42-7C90-4DA8-83B7-4C4033A70210'},MutationObserver:class{observe(){}},setInterval:()=>{},setTimeout:()=>{},Array};
 vm.createContext(context);vm.runInContext(source,context);
 return {messages,listeners,window,location,setBusy:v=>busy=v,advance:v=>now+=v,check:()=>window.__soloAgentObserver?.check()};
}
test('real streaming controls start and finish a web turn without reading content',()=>{
 const f=fixture();f.check();assert.equal(f.messages.length,0);
 f.setBusy(true);f.check();assert.equal(f.messages[0].state,'start');
 f.advance(16000);f.check();assert.equal(f.messages[1].state,'working');
 f.setBusy(false);f.check();assert.equal(f.messages[2].state,'finished');
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
