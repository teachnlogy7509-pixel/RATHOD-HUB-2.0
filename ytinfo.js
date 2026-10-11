(()=>{
'use strict';
const API='https://rathod-ytinfo.rathod-hub-ai.workers.dev/';
const $=s=>document.querySelector(s);
const esc=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
function toast(m){const t=$('#toast');if(!t)return;t.textContent=m;t.classList.add('show');clearTimeout(toast.t);toast.t=setTimeout(()=>t.classList.remove('show'),1800)}
async function copy(text,label){
  try{await navigator.clipboard.writeText(text)}catch{const a=document.createElement('textarea');a.value=text;a.style.cssText='position:fixed;opacity:0;top:0';document.body.appendChild(a);a.select();try{document.execCommand('copy')}catch{}a.remove()}
  toast((label||'Copy')+' ho gaya ✅');
}
let data=null;
function chips(list,prefix){return list.map((t,i)=>`<button type="button" class="yi-chip" data-copy-tag="${i}" data-kind="${prefix}">${prefix==='h'?'#':''}${esc(t)}</button>`).join('')}
function render(){
  const box=$('#ytInfoResult');if(!box||!data)return;
  const h=data.hashtags||[],k=(data.keywords||[]).filter(x=>!h.some(y=>y.toLowerCase()===x.toLowerCase()));
  box.innerHTML=`
  <article class="yi-card"><div class="yi-head"><b>🎬 Title</b><button type="button" class="yi-copy" data-copy="title">Copy</button></div><p class="yi-text">${esc(data.title)}</p>${data.author?`<small class="yi-sub">Channel: ${esc(data.author)}</small>`:''}</article>
  <article class="yi-card"><div class="yi-head"><b>📝 Description</b><button type="button" class="yi-copy" data-copy="desc">Copy</button></div>${data.description?`<pre class="yi-text yi-desc">${esc(data.description)}</pre>`:'<p class="yi-sub">Is video ka description nahi mila.</p>'}</article>
  <article class="yi-card"><div class="yi-head"><b>#️⃣ Hashtags <em>${h.length}</em></b>${h.length?'<button type="button" class="yi-copy" data-copy="hall">Copy all</button>':''}</div>${h.length?`<div class="yi-chips">${chips(h,'h')}</div><small class="yi-sub">Kisi hashtag par tap karo – wo akela copy ho jayega.</small>`:'<p class="yi-sub">Description me koi #hashtag nahi hai.</p>'}</article>
  ${k.length?`<article class="yi-card"><div class="yi-head"><b>🏷️ Video tags <em>${k.length}</em></b><button type="button" class="yi-copy" data-copy="kall">Copy all</button></div><div class="yi-chips">${chips(k,'k')}</div><small class="yi-sub">Ek-ek tag par tap karke copy karo.</small></article>`:''}
  ${data.partial?'<p class="yi-warn">⚠ Sirf title mil paya (YouTube ne baaki info nahi di). Thodi der baad dobara try karo.</p>':''}`;
  const kw=k;
  box.querySelectorAll('[data-copy]').forEach(b=>b.onclick=()=>{const t=b.dataset.copy;
    if(t==='title')copy(data.title,'Title');else if(t==='desc')copy(data.description,'Description');
    else if(t==='hall')copy(h.map(x=>'#'+x).join(' '),'Saare hashtags');else copy(kw.join(', '),'Saare tags')});
  box.querySelectorAll('[data-copy-tag]').forEach(b=>b.onclick=()=>{const i=+b.dataset.copyTag,isH=b.dataset.kind==='h',v=isH?'#'+h[i]:kw[i];copy(v,v);b.classList.add('done');setTimeout(()=>b.classList.remove('done'),900)});
}
async function go(e){
  e.preventDefault();const inp=$('#ytInfoUrl'),st=$('#ytInfoStatus'),btn=$('#ytInfoBtn'),url=inp.value.trim();if(!url)return;
  st.textContent='Info la raha hoon…';btn.disabled=true;$('#ytInfoResult').innerHTML='';
  try{const r=await fetch(API+'?url='+encodeURIComponent(url)),d=await r.json();if(!r.ok||d.error)throw Error(d.error||'Info nahi mili');data=d;st.textContent='';render()}
  catch(err){data=null;st.textContent='❌ '+(err.message==='Failed to fetch'?'Internet check karo aur dobara try karo':err.message)}
  btn.disabled=false;
}
async function paste(){try{const t=await navigator.clipboard.readText();if(t){$('#ytInfoUrl').value=t.trim();$('#ytInfoForm').requestSubmit()}}catch{toast('Link yaha manually paste karo')}}
function boot(){$('#ytInfoForm')?.addEventListener('submit',go);$('#ytInfoPaste')?.addEventListener('click',paste);$('#ytInfoClear')?.addEventListener('click',()=>{$('#ytInfoUrl').value='';$('#ytInfoResult').innerHTML='';$('#ytInfoStatus').textContent='';data=null})}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
