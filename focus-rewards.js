(()=>{
'use strict';
const $=s=>document.querySelector(s),$$=s=>[...document.querySelectorAll(s)];
const KEY={sessions:'rh_ypt_sessions',claimed:'rh_ypt_claimedAvatars',selected:'rh_ypt_selectedAvatar',theme:'rh_ypt_amoled'};
const AVATARS=[
 {id:'starter',hours:0,name:'Focus Rookie',emoji:'🎓',tone:'violet',tag:'STARTER'},
 {id:'scholar',hours:5,name:'NEET Scholar',emoji:'🧠',tone:'blue',tag:'5 HOURS'},
 {id:'botanist',hours:10,name:'Bio Guardian',emoji:'🌿',tone:'green',tag:'10 HOURS'},
 {id:'phoenix',hours:20,name:'Focus Phoenix',emoji:'🔥',tone:'red',tag:'20 HOURS'},
 {id:'knight',hours:35,name:'NEET Knight',emoji:'🛡️',tone:'gold',tag:'35 HOURS'},
 {id:'legend',hours:50,name:'Rathod Legend',emoji:'👑',tone:'cosmic',tag:'50 HOURS'}
];
const read=(k,d)=>{try{return JSON.parse(localStorage.getItem(k))??d}catch{return d}};
const write=(k,v)=>localStorage.setItem(k,JSON.stringify(v));
function weekStart(){const d=new Date();d.setHours(0,0,0,0);d.setDate(d.getDate()-((d.getDay()+6)%7));return d}
function weeklySeconds(){const start=weekStart();return read(KEY.sessions,[]).filter(x=>new Date(x.started_at||x.date)>=start).reduce((n,x)=>n+Number(x.seconds||x.duration_seconds||0),0)}
function format(sec){const h=Math.floor(sec/3600),m=Math.floor(sec%3600/60);return `${h}h ${m}m`}
function claimed(){return new Set(read(KEY.claimed,['starter']))}
function selected(){return read(KEY.selected,'starter')}
function avatar(id){return AVATARS.find(x=>x.id===id)||AVATARS[0]}
function render(){const grid=$('#avatarRewardGrid');if(!grid)return;const sec=weeklySeconds(),hours=sec/3600,owned=claimed(),current=avatar(selected()),next=AVATARS.find(x=>x.hours>hours&&!owned.has(x.id));$('#rewardHours').textContent=format(sec);$('#rewardHeroAvatar').className=`reward-hero-avatar ${current.tone}`;$('#rewardHeroAvatar').innerHTML=`<span>${current.emoji}</span>`;$('#rewardNextText').textContent=next?`${next.name} के लिए ${Math.max(0,next.hours-hours).toFixed(1)} hours और`:'इस हफ्ते का highest reward unlock हो गया!';const prev=next?Math.max(0,...AVATARS.filter(x=>x.hours<next.hours).map(x=>x.hours)):0,pct=next?Math.min(100,(hours-prev)/(next.hours-prev)*100):100;$('#rewardProgressBar').style.width=pct+'%';grid.innerHTML=AVATARS.map(a=>{const has=owned.has(a.id),ready=hours>=a.hours,isSelected=a.id===current.id;return `<article class="avatar-reward-card ${a.tone} ${has?'owned':''} ${ready?'ready':''}"><span class="avatar-tag">${a.tag}</span><div class="avatar-3d"><i></i><b>${a.emoji}</b></div><h3>${a.name}</h3><p>${a.hours?`${a.hours} weekly focus hours`:'Free starter avatar'}</p><button data-avatar-action="${a.id}" ${!ready&&!has?'disabled':''}>${isSelected?'✓ Equipped':has?'Use avatar':ready?'Claim free':'🔒 Keep studying'}</button></article>`}).join('');applyProfileAvatar()}
function act(id){const a=avatar(id),owned=claimed(),hours=weeklySeconds()/3600;if(!owned.has(id)){if(hours<a.hours)return;owned.add(id);write(KEY.claimed,[...owned]);toast(`${a.name} claimed permanently ✓`)}write(KEY.selected,id);render();toast(`${a.name} equipped`)}
function toast(text){const el=$('#toast');if(!el)return;el.textContent=text;el.classList.add('show');clearTimeout(toast.t);toast.t=setTimeout(()=>el.classList.remove('show'),2600)}
function applyProfileAvatar(){const top=$('#topAvatar'),a=avatar(selected());if(top&&!top.querySelector(`[data-reward-avatar="${a.id}"]`)){top.innerHTML=`<span class="profile-reward-avatar ${a.tone}" data-reward-avatar="${a.id}">${a.emoji}</span>`;top.classList.add('has-reward-avatar')}}
let installPrompt=null;
function setOnline(){const b=$('#networkBadge');if(!b)return;const online=navigator.onLine;b.textContent=online?'● ONLINE':'● OFFLINE · TIMER SAFE';b.classList.toggle('offline',!online)}
function setTheme(on){document.body.classList.toggle('amoled',on);write(KEY.theme,on);const b=$('#themeToggle');if(b)b.textContent=on?'☀ Use classic theme':'◐ AMOLED dark mode';document.querySelector('meta[name="theme-color"]')?.setAttribute('content',on?'#000000':'#14151a')}
function boot(){setTheme(read(KEY.theme,false));setOnline();render();const install=$('#installAppBtn');window.addEventListener('beforeinstallprompt',e=>{e.preventDefault();installPrompt=e;install?.classList.remove('hidden')});install?.addEventListener('click',async()=>{if(!installPrompt)return toast('Chrome menu से Add to Home screen चुनें');installPrompt.prompt();await installPrompt.userChoice;installPrompt=null;install.classList.add('hidden')});$('#themeToggle')?.addEventListener('click',()=>setTheme(!document.body.classList.contains('amoled')));document.addEventListener('click',e=>{const b=e.target.closest('[data-avatar-action]');if(b)act(b.dataset.avatarAction);if(e.target.closest('[data-view="rewards"]'))setTimeout(render,50)});window.addEventListener('online',()=>{setOnline();toast('Back online · pending study sync started')});window.addEventListener('offline',()=>{setOnline();toast('Offline mode · timer and sessions device पर safe हैं')});const top=$('#topAvatar');if(top)new MutationObserver(applyProfileAvatar).observe(top,{childList:true,subtree:true,characterData:true});setInterval(()=>{if($('[data-page="rewards"]')?.classList.contains('active'))render()},15000);window.addEventListener('appinstalled',()=>{install?.classList.add('hidden');toast('YPT by Rathod installed ✓')})}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
