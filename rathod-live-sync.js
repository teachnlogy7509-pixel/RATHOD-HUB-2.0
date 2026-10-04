(()=>{
'use strict';
const SOURCE='rh_ypt_sessions',QUEUE='rathod_hub_focus_bridge_v1';
const read=(k,d)=>{try{return JSON.parse(localStorage.getItem(k))??d}catch{return d}};
const write=(k,v)=>localStorage.setItem(k,JSON.stringify(v));
function normalize(s){return{id:s.id||('ypt_'+String(s.started_at||s.date||Date.now()).replace(/\W/g,'')+'_'+Number(s.seconds||0)),date:s.date||String(s.started_at||new Date().toISOString()).slice(0,10),seconds:Math.max(0,Math.round(Number(s.seconds||s.duration_seconds||0))),subject:s.subject||'Other',at:s.started_at||s.created_at||new Date().toISOString(),source:'RATHOD-HUB-2.0'}}
function mainUid(){for(let i=0;i<localStorage.length;i++){const k=localStorage.key(i)||'';if(!k.includes('sb-fezyljxjbgefaqroxorl-auth-token'))continue;const v=read(k,null);const id=v?.user?.id||v?.currentSession?.user?.id;if(id)return id}return ''}
function mergeIntoMain(rows,uid){if(!uid)return;const key=`rathod_focus_v2_${uid}_stats`,stats=read(key,{sessions:[],goalHours:4}),map=new Map((stats.sessions||[]).map(x=>[x.id,x]));rows.forEach(x=>map.set(x.id,x));stats.sessions=[...map.values()];write(key,stats)}
function mirror(){const source=read(SOURCE,[]).map(normalize).filter(x=>x.seconds>=5),queue=read(QUEUE,[]),map=new Map(queue.map(x=>[x.id,x]));source.forEach(x=>map.set(x.id,{...map.get(x.id),...x}));const rows=[...map.values()].slice(-5000);write(QUEUE,rows);mergeIntoMain(rows,mainUid());window.dispatchEvent(new CustomEvent('rathod-focus-bridge',{detail:{count:rows.length}}))}
let last='';function check(){const now=localStorage.getItem(SOURCE)||'';if(now===last)return;last=now;mirror()}
window.addEventListener('storage',e=>{if(e.key===SOURCE)check()});window.addEventListener('online',mirror);document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible')mirror()});setInterval(check,2500);if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',mirror);else mirror();
})();
