const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const file = fs.readFileSync(path.join(__dirname,'../../Sources/IslandApp/WebPlayerScript.swift'),'utf8');
const source = file.match(/static let source = #"""\n([\s\S]*?)\n    """#/)[1];
function fixture({elements=[],metadata=null,selectors={}}={}) {
 const messages=[],handlers={};
 const context={console,Number,String,Array,Object,setInterval:()=>{},
  document:{querySelectorAll:()=>elements,querySelector:s=>selectors[s]??null,addEventListener:()=>{}},
  navigator:{mediaSession:{metadata,playbackState:'none',setActionHandler:(k,h)=>{handlers[k]=h}}},
  window:{webkit:{messageHandlers:{soloPlayer:{postMessage:p=>messages.push(p)}}}}
 };
 vm.createContext(context);vm.runInContext(source,context);
 return {context,bridge:context.window.__soloIsland,messages,handlers};
}
test('empty and login pages do not become tracks or expose form data',()=>{
 const f=fixture();assert.equal(f.bridge.snapshot().title,'');assert.equal(f.bridge.snapshot().playing,false);
 assert.deepEqual(Object.keys(f.bridge.snapshot()).sort(),['artist','artworkURL','duration','elapsedTime','playbackRate','playing','title']);
});
test('active HTML5 media wins and non-finite stream duration is omitted',async()=>{
 const paused={paused:true,currentTime:30,duration:100};
 const active={paused:false,ended:false,currentTime:12,duration:Infinity,playbackRate:1,pause(){this.paused=true},async play(){this.paused=false}};
 const f=fixture({elements:[paused,active],metadata:{title:'Трек',artist:'Артист',artwork:[{src:'https://cover.test/a.png'}]}});
 assert.equal(f.bridge.snapshot().title,'Трек');assert.equal(f.bridge.snapshot().duration,null);assert.equal(f.bridge.snapshot().elapsedTime,12);
 assert.equal(await f.bridge.command('toggle-play-pause'),'ok');assert.equal(active.paused,true);
 assert.equal(await f.bridge.command('toggle-play-pause'),'ok');assert.equal(active.paused,false);
});
test('media session next and seek handlers receive structured action details',async()=>{
 const f=fixture();let next=0,seek;
 f.context.navigator.mediaSession.setActionHandler('nexttrack',()=>next++);
 f.context.navigator.mediaSession.setActionHandler('seekto',p=>seek=p.seekTime);
 assert.equal(await f.bridge.command('next-track'),'ok');assert.equal(next,1);
 assert.equal(await f.bridge.command('seek',42),'ok');assert.equal(seek,42);
 assert.equal(await f.bridge.command('seek',-1),'unavailable');
});
test('native HTML5 seek clamps to duration and unsupported controls fail explicitly',async()=>{
 const media={paused:true,currentTime:0,duration:120,playbackRate:1};const f=fixture({elements:[media]});
 assert.equal(await f.bridge.command('seek',999),'ok');assert.equal(media.currentTime,120);
 assert.equal(await f.bridge.command('next-track'),'unavailable');
});
test('site-specific next button is used only when enabled',async()=>{
 let clicks=0;const button={disabled:false,getAttribute:()=>null,click:()=>clicks++};
 const f=fixture({selectors:{'[data-testid="control-button-skip-forward"]':button}});
 assert.equal(await f.bridge.command('next-track'),'ok');assert.equal(clicks,1);
 button.disabled=true;assert.equal(await f.bridge.command('next-track'),'unavailable');assert.equal(clicks,1);
});
