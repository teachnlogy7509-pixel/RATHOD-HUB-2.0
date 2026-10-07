(()=>{
'use strict';
const ENDPOINT='https://rathod-ai-api.rathod-hub-ai.workers.dev/chat';
const HEALTH='https://rathod-ai-api.rathod-hub-ai.workers.dev/';
const IMAGE_ENDPOINT='https://rathod-image-api.rathod-hub-ai.workers.dev/image';
const SUPABASE_DEFAULT={url:'https://oeacgchzyilgqzaqxssh.supabase.co',key:'sb_publishable_boL9uWFxb1hcOx7o9nb9Rw_OERUARlv'};
let imageClient=null;
const KEY='rh2_rathod_ai_history_v1';
const $=s=>document.querySelector(s);
let sending=false,history=[],imageDbPromise=null;
const imageUrls=new Map();
let pendingPhotos=[],photoBusy=false,visionReady=false;
const esc=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
function load(){try{history=JSON.parse(localStorage.getItem(KEY)||'[]');if(!Array.isArray(history))history=[]}catch{history=[]}if(!history.length)history=[{role:'assistant',content:'नमस्ते! मैं Rathod AI हूँ 😊\nWriting, coding, translation, study, planning या images—जो चाहिए बताइए। App में task जोड़ना, daily goal बदलना और focus timer चलाना भी कह सकते हैं।',time:Date.now(),welcome:true}];render();restoreImages()}
function save(){try{localStorage.setItem(KEY,JSON.stringify(history.slice(-500).map(x=>{const y={...x};delete y.image;if(y.photos)y.photos=y.photos.map(p=>({imageId:p.imageId,name:p.name}));return y})))}catch{history=history.slice(-150);localStorage.setItem(KEY,JSON.stringify(history))}}
function render(){const root=$('#rathodAiMessages');if(!root)return;root.innerHTML=history.map((m,i)=>`<article class="rh-ai-message ${m.role}"><div class="rh-ai-avatar">${m.role==='assistant'?'R':'●'}</div><div><small>${m.role==='assistant'?'RATHOD AI':'YOU'}</small><div class="rh-ai-content">${formatText(m.content)}</div>${(m.photos||[]).map(p=>p.image?`<img class="rh-ai-question-photo" src="${esc(p.image)}" alt="Uploaded question photo">`:`<small>📷 ${esc(p.name||'Question photo')}</small>`).join('')}${(m.actions||[]).length?`<div class="rh-ai-actions">${m.actions.map((a,j)=>`<button type="button" data-ai-apply="${i}:${j}" ${a.applied?'disabled':''}>${a.applied?'✅ Applied':'Apply: '+esc(actionLabel(a))}</button>`).join('')}<small>Permissions दोबारा जाँची जाएँगी। कोई secret unlock code AI को नहीं मिलता।</small></div>`:''}${m.image?`<div class="rh-ai-generated"><img src="${esc(m.image)}" alt="Rathod AI generated image"><a href="${esc(m.image)}" download="rathod-ai-image.png">⬇ Download image</a></div>`:''}${m.provider?`<em>${esc(m.provider)}</em>`:''}</div></article>`).join('');root.querySelectorAll('[data-ai-apply]').forEach(b=>b.onclick=()=>applyAction(b.dataset.aiApply,b));root.scrollTop=root.scrollHeight;$('#rathodAiMemoryCount').textContent=`${history.filter(x=>!x.welcome).length} messages remembered`}
function add(role,content,extra={}){history.push({role,content,time:Date.now(),...extra});save();render()}
function setBusy(on){sending=on;if($('#rathodAiAttach'))$('#rathodAiAttach').disabled=on;if($('#rathodAiPhoto'))$('#rathodAiPhoto').disabled=on;const b=$('#rathodAiSend'),input=$('#rathodAiInput');if(b){b.disabled=on;b.innerHTML=on?'<i></i> सोच रहा हूँ…':'भेजें ➤'}if(input)input.disabled=on;$('#rathodAiTyping')?.classList.toggle('hidden',!on)}
function formatText(text){return String(text||'').split(/(```[\s\S]*?```)/g).map(part=>part.startsWith('```')?'<pre><code>'+esc(part.replace(/^```[^\n]*\n?/,'').replace(/```$/,''))+'</code></pre>':'<div>'+esc(part).replace(/^#{1,4}\s+(.+)$/gm,'<strong>$1</strong>').replace(/\*\*([^*\n]+)\*\*/g,'<strong>$1</strong>').replace(/`([^`\n]+)`/g,'<code>$1</code>').replace(/\n/g,'<br>')+'</div>').join('')}
const actionNames={add_task:'Add task',set_goal:'Change goal',start_timer:'Start timer',pause_timer:'Pause timer',finish_timer:'Save session',set_subject:'Change subject',set_mode:'Change timer mode',set_pomodoro:'Pomodoro settings',navigate:'Open page',save_note:'Save private note',join_voice:'Join voice room',leave_voice:'Leave voice room',set_mic:'Change microphone',set_theme:'Change theme',open_blocker_settings:'Open blocker permission settings'};
function actionLabel(a){return (actionNames[a.type]||'Unsupported action')+(a.subject?' · '+a.subject:'')+(a.view?' · '+a.view:'')}
async function applyAction(key,button){if(sending)return;const [i,j]=key.split(':').map(Number),a=history[i]?.actions?.[j];if(!a||a.applied||!actionNames[a.type])return;button.disabled=true;setBusy(true);try{if(!window.rhAIApp)throw Error('App controls loading…');const result=await window.rhAIApp.execute(a);a.applied=true;save();add('assistant',result,{provider:'Rathod App · permission checked'})}catch(e){add('assistant',e.message,{error:true})}finally{setBusy(false);render()}}
function photoPreview(){const root=$('#rathodAiAttachments');if(!root)return;root.innerHTML=pendingPhotos.map((p,i)=>`<div><img src="${esc(p.preview)}" alt="Question photo preview"><span>${esc(p.name)}</span><button type="button" data-remove-photo="${i}" aria-label="Remove photo">×</button></div>`).join('');root.querySelectorAll('[data-remove-photo]').forEach(b=>b.onclick=()=>{const [p]=pendingPhotos.splice(Number(b.dataset.removePhoto),1);if(p)URL.revokeObjectURL(p.preview);photoPreview()});root.classList.toggle('hidden',!pendingPhotos.length)}
async function photoFile(file){
  if(!/^(image\/(?:png|jpeg|webp))$/.test(file.type))throw Error('JPG, PNG या WebP photo चुनें। HEIC/GIF को पहले JPG में बदलें।');
  if(file.size>10*1024*1024)throw Error('Photo 10 MB से छोटी रखें।');
  const bmp=await createImageBitmap(file),scale=Math.min(1,2200/Math.max(bmp.width,bmp.height)),canvas=document.createElement('canvas');canvas.width=Math.round(bmp.width*scale);canvas.height=Math.round(bmp.height*scale);const ctx=canvas.getContext('2d');ctx.fillStyle='#fff';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(bmp,0,0,canvas.width,canvas.height);bmp.close();
  let blob=await new Promise(r=>canvas.toBlob(r,'image/jpeg',.86));if(!blob)throw Error('Photo पढ़ने में error।');
  if(blob.size>1500000)blob=await new Promise(r=>canvas.toBlob(r,'image/jpeg',.65));if(!blob||blob.size>1500000)throw Error('Photo बहुत बड़ी है; crop करके फिर upload करें।');
  const dataUrl=await new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(r.result);r.onerror=reject;r.readAsDataURL(blob)});
  return {name:file.name||'Pasted question',mimeType:'image/jpeg',data:dataUrl.split(',')[1],blob,preview:URL.createObjectURL(blob)};
}
async function choosePhotos(files){if(sending||photoBusy)return;photoBusy=true;const status=$('#rathodAiPhotoStatus');if(status)status.textContent='Photo तैयार हो रही है…';try{for(const f of files){if(pendingPhotos.length>=2)throw Error('एक message में maximum 2 photos रखें।');pendingPhotos.push(await photoFile(f))}photoPreview();if(status)status.textContent=visionReady?'Photo AI को answer के लिए भेजी जाएगी। Sensitive/private details crop कर दें।':'Photo तैयार है। Live vision backend अभी pending है; publish के बाद इसे पढ़ सकेगा।'}catch(e){photoPreview();if(status)status.textContent=e.message}finally{photoBusy=false;if($('#rathodAiPhoto'))$('#rathodAiPhoto').value=''}}
function imageIntent(text){
  const q=String(text||'').trim();
  if(/(?:कैसे|kaise|how\s+to|can\s+you|क्या तुम).{0,60}(?:image|photo|picture|चित्र|फोटो|तस्वीर)/i.test(q)&&!/(?:मेरे लिए|mere liye|for me|please|अभी|abhi)/i.test(q))return false;
  if(/^(?:don't|do not|मत|नहीं)\b/i.test(q)||/(?:image|photo|picture|चित्र|फोटो|तस्वीर).{0,30}(?:mat banao|नहीं बनाना|मत बना)/i.test(q))return false;
  const noun='(?:image|photo|picture|poster|logo|thumbnail|wallpaper|illustration|sketch|diagram|चित्र|फोटो|तस्वीर|पोस्टर|लोगो|वॉलपेपर|इमेज|डायग्राम)';
  const verb='(?:bana(?:o|do|na)?|banade|generate|creat(?:e|ing)|draw|make|design|बना|बनाओ|बनादो|खींच|बनाना|तैयार कर)';
  return new RegExp(noun+'.{0,140}'+verb+'|'+verb+'.{0,140}'+noun,'i').test(q)||/^(?:\/image\s+|draw\s+|sketch\s+|चित्र बनाओ\s+|फोटो बनाओ\s+)/i.test(q);
}
function appAction(text){
  const q=String(text||'').trim();
  if(/(?:कैसे|kaise|how\s+(?:to|can|do)|what|क्या होता|समझाओ|explain|code|script|example)/i.test(q))return null;
  if(/(?:theme|dark mode|amoled|थीम|डार्क)/i.test(q)&&/(?:on|enable|चालू)/i.test(q))return {type:'set_theme',enabled:true};
  if(/(?:theme|dark mode|amoled|थीम|डार्क)/i.test(q)&&/(?:off|disable|बंद)/i.test(q))return {type:'set_theme',enabled:false};
  if(/pomodoro|पोमोडोरो/i.test(q)&&/(?:on|start|enable|चालू|शुरू)/i.test(q)&&!/[0-9]/.test(q))return {type:'set_mode',mode:'pomodoro'};
  if(/pomodoro|पोमोडोरो/i.test(q)&&/(?:off|disable|बंद)/i.test(q))return {type:'set_mode',mode:'stopwatch'};
  if(/(?:timer|session|टाइमर|सेशन)/i.test(q)&&/(?:finish|save|समाप्त|सेव)/i.test(q))return {type:'finish_timer'};
  if(/(?:mic|microphone|माइक|माइक्रोफोन)/i.test(q)&&/(?:off|mute|बंद)/i.test(q)&&!/unmute/i.test(q))return {type:'set_mic',enabled:false};
  if(/(?:mic|microphone|माइक|माइक्रोफोन)/i.test(q)&&/(?:on|unmute|चालू)/i.test(q))return {type:'set_mic',enabled:true};
  if(/(?:voice|वॉइस|वॉयस)/i.test(q)&&/(?:leave|off|छोड़|बंद)/i.test(q))return {type:'leave_voice'};
  if(/(?:blocker|ब्लॉकर)/i.test(q)&&/(?:on|enable|settings|चालू|सेटिंग)/i.test(q))return {type:'open_blocker_settings'};
  const subject=[['Physics',/(?:physics|फिजिक्स|भौतिक)/i],['Chemistry',/(?:chemistry|केमिस्ट्री|रसायन)/i],['Biology',/(?:biology|बायोलॉजी|जीव|botany|zoology)/i],['Revision',/(?:revision|रिविजन)/i],['Mock Test',/(?:mock test|मॉक टेस्ट)/i]].find(x=>x[1].test(q))?.[0];
  const goal=q.match(/(?:goal|लक्ष्य|टारगेट|target).{0,40}?(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|घंटे?|घंटा)/i)||q.match(/(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|घंटे?|घंटा).{0,40}?(?:goal|लक्ष्य|टारगेट|target)/i);
  if(goal&&/(?:set|kar do|kardo|कर दो|करो|रख|बदल|change|कर दें)/i.test(q))return {type:'set_goal',hours:Number(goal[1])};
  if(/(?:timer|focus|टाइमर|फोकस)/i.test(q)&&/(?:pause|रोक दो|रोकें|रुको|पॉज)/i.test(q))return {type:'pause_timer'};
  if(/(?:timer|focus|टाइमर|फोकस)/i.test(q)&&/(?:start|resume|chalao|shuru|चला|शुरू|चालू)/i.test(q))return {type:'start_timer',subject};
  if(/(?:task|todo|to-do|टास्क|कार्य)/i.test(q)&&/(?:add|jod|जोड़|जोड)/i.test(q)){
    let content=q.replace(/^(?:please\s+|कृपया\s+|mere liye\s+|मेरे लिए\s+)/i,'');
    content=content.replace(/^(?:(?:add|जोड़ो|जोड़ दें)\s+(?:a\s+)?(?:task|todo|to-do|टास्क|कार्य)\s*:?\s*|(?:task|todo|to-do|टास्क|कार्य)\s+(?:add\s+(?:kar\s*do|kardo)?|जोड़ो|जोड़ दें)\s*:?\s*)/i,'');
    content=content.replace(/\s*(?:(?:ka|ki|का|की)\s+)?(?:task|todo|to-do|टास्क|कार्य)\s+(?:add\s*(?:kar\s*do|kardo|karo)?|जोड़\s*(?:दो|दें)|जोड\s*दो)[.!।]*$/i,'').trim();
    if(content&&content!==q)return {type:'add_task',text:content,subject};
  }
  if(/(?:open|खोलो|खोल दो|खोलें|khol|dikhao|दिखाओ)/i.test(q)){
    const views=[['quality',/focus quality|फोकस क्वालिटी/],['insights',/insights|इनसाइट्स/],['admin',/admin panel|admin page|एडमिन पैनल/],['planner',/planner|प्लानर/],['timer',/timer|टाइमर/],['notesvault',/notes vault|नोट्स/],['diary',/diary|डायरी/],['analytics',/analytics|एनालिटिक्स/],['calendar',/calendar|कैलेंडर/],['history',/history|हिस्ट्री/],['leaderboard',/leaderboard|लीडरबोर्ड/],['dashboard',/dashboard|home|होम/],['groups',/groups|ग्रुप/]];
    const view=views.find(x=>x[1].test(q.toLowerCase()))?.[0];if(view)return {type:'navigate',view};
  }
  return null;
}
async function fetchTimed(url,options={},ms=95000){const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),ms);try{return await fetch(url,{...options,signal:controller.signal})}catch(e){if(e.name==='AbortError')throw new Error('AI ने ज्यादा समय लिया। थोड़ी देर बाद फिर भेजें।');throw e}finally{clearTimeout(timer)}}
async function sessionForImage(refresh=false){
  if(window.rhAIApp)return window.rhAIApp.session(refresh);
  const c=supabaseClient();if(!c)return null;
  const r=refresh?await c.auth.refreshSession():await c.auth.getSession();if(r.error)throw r.error;return r.data?.session||null;
}
async function requestImage(prompt){
  let session=await sessionForImage();if(!session){$('#authDialog')?.showModal();throw new Error('Image बनाने के लिए पहले इसी app में Login करें।')}
  const post=token=>fetchTimed(IMAGE_ENDPOINT,{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`},body:JSON.stringify({prompt})});
  let r=await post(session.access_token);
  if(r.status===401){session=await sessionForImage(true);if(session)r=await post(session.access_token)}
  const type=(r.headers.get('content-type')||'').toLowerCase();
  if(!r.ok){const d=type.includes('json')?await r.json().catch(()=>({})):{};throw new Error(d.error||`Image service error (${r.status})`)}
  let blob,remaining,provider;
  if(type.startsWith('image/')){blob=await r.blob();remaining=r.headers.get('X-Images-Remaining');provider=r.headers.get('X-Image-Provider')}
  else if(type.includes('json')){const d=await r.json();if(!d.image)throw new Error(d.error||'Image service ने image नहीं भेजी।');const raw=atob(d.image.replace(/^data:image\/[^;]+;base64,/,''));blob=new Blob([Uint8Array.from(raw,c=>c.charCodeAt(0))],{type:d.mimeType||'image/png'});remaining=d.remaining;provider=d.provider}
  else throw new Error('Image response सही format में नहीं आया। फिर कोशिश करें।');
  if(!blob.size||!/^image\/(?:png|jpeg|webp)/i.test(blob.type))throw new Error('Image file खाली या invalid है। फिर कोशिश करें।');
  return {blob,image:URL.createObjectURL(blob),remaining:remaining==null?null:Number(remaining),provider:provider||'Rathod AI Image'};
}
function imageDb(){if(!window.indexedDB)return Promise.resolve(null);if(!imageDbPromise)imageDbPromise=new Promise(resolve=>{const r=indexedDB.open('rh2-ai-images',1);r.onupgradeneeded=()=>r.result.createObjectStore('images');r.onsuccess=()=>resolve(r.result);r.onerror=()=>resolve(null);r.onblocked=()=>resolve(null)});return imageDbPromise}
async function storeImage(id,blob){try{const db=await imageDb();if(!db)return false;return await new Promise(resolve=>{const tx=db.transaction('images','readwrite');tx.objectStore('images').put(blob,id);tx.oncomplete=()=>resolve(true);tx.onerror=()=>resolve(false)})}catch{return false}}
async function clearImages(){for(const url of imageUrls.values())URL.revokeObjectURL(url);imageUrls.clear();try{const db=await imageDb();if(db)db.transaction('images','readwrite').objectStore('images').clear()}catch{}}
async function restoreImages(){try{const db=await imageDb();if(!db)return;const rows=[];for(const m of history){if(m.imageId&&!m.image)rows.push(m);for(const p of m.photos||[])if(p.imageId&&!p.image)rows.push(p)}await Promise.all(rows.map(m=>new Promise(resolve=>{const r=db.transaction('images').objectStore('images').get(m.imageId);r.onsuccess=()=>{if(r.result){m.image=imageUrls.get(m.imageId)||URL.createObjectURL(r.result);imageUrls.set(m.imageId,m.image)}resolve()};r.onerror=resolve})));if(rows.length)render()}catch{}}

async function send(text){
  text=String(text||'').trim();if(sending||photoBusy||(!text&&!pendingPhotos.length))return;
  const photos=pendingPhotos.slice();if(photos.length&&!visionReady){add('assistant','Photo-reading backend अभी live नहीं है। आपकी photo बिना पढ़े कोई अनुमानित answer नहीं दूँगा।',{error:true});return}
  if(!text)text='इस photo में question पढ़कर step-by-step solve करें। पहले question का text लिखें।';
  setBusy(true);const savedPhotos=[];for(const p of photos){const imageId=crypto.randomUUID(),stored=await storeImage(imageId,p.blob);if(stored)imageUrls.set(imageId,p.preview);savedPhotos.push({image:p.preview,name:p.name,...(stored?{imageId}:{})})}
  add('user',text,savedPhotos.length?{photos:savedPhotos}:{});pendingPhotos=[];photoPreview();if($('#rathodAiPhotoStatus'))$('#rathodAiPhotoStatus').textContent='';$('#rathodAiInput').value='';
  try{
    const action=!photos.length?appAction(text):null;
    if(action&&window.rhAIApp){const result=await window.rhAIApp.execute(action);add('assistant',result,{provider:'Rathod App · verified action'});return}
    if(!navigator.onLine)throw new Error('Internet बंद है। Chat history सुरक्षित है; online होते ही फिर भेजें।');
    if(!photos.length&&imageIntent(text)){
      $('#rathodAiSend').textContent='🎨 Image बन रही है…';const out=await requestImage(text),imageId=crypto.randomUUID();imageUrls.set(imageId,out.image);const stored=await storeImage(imageId,out.blob);
      add('assistant',`आपकी image तैयार है 🎨${out.remaining==null?'':`\nआज ${out.remaining} image बाकी हैं।`}${stored?'':'\nइसे download कर लें; इस browser में image storage उपलब्ध नहीं है।'}`,{image:out.image,...(stored?{imageId}:{}),provider:out.provider});refreshImageLimit();return;
    }
    const messages=history.filter(x=>!x.welcome&&!x.error).slice(-40).map(x=>({role:x.role,content:x.content}));
    const r=await fetchTimed(ENDPOINT,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({messages,images:photos.map(p=>({mimeType:p.mimeType,data:p.data})),appContext:window.rhAIApp?.context?.()||null})});
    const data=await r.json().catch(()=>({}));if(!r.ok)throw new Error(data.error||`Rathod AI error (${r.status})`);
    add('assistant',String(data.text||'जवाब नहीं मिला। फिर कोशिश करें।').trim(),{provider:`${data.provider||'Rathod AI'} · ${data.model||'auto'}`,...(Array.isArray(data.actions)&&!photos.length?{actions:data.actions.filter(a=>a&&actionNames[a.type]).slice(0,5)}:{})});
  }catch(e){add('assistant',e.message||'अभी connection नहीं हो पाया। थोड़ी देर बाद फिर कोशिश करें।',{error:true})}
  finally{setBusy(false);$('#rathodAiInput')?.focus()}
}

async function health(){try{const r=await fetch(HEALTH,{cache:'no-store'}),d=await r.json();visionReady=d.vision===true;const badge=$('#rathodAiStatus');if(!badge)return;if(d.configured){badge.textContent=`● ONLINE · ${d.configured} keys ready`;badge.classList.add('online')}else{badge.textContent='○ API keys pending';badge.classList.remove('online')}}catch{$('#rathodAiStatus').textContent='○ Gateway offline'}}

function supabaseClient(){if(imageClient)return imageClient;let c=SUPABASE_DEFAULT;try{c=JSON.parse(localStorage.getItem('rh_ypt_supabase'))||SUPABASE_DEFAULT}catch{}imageClient=window.supabase?.createClient(c.url||SUPABASE_DEFAULT.url,c.key||SUPABASE_DEFAULT.key);return imageClient}
async function refreshImageLimit(){
  const label=$('#rathodImageLimit');if(!label)return;
  try{const session=await sessionForImage();if(!session){label.textContent='Login · 3/day';return}
  const r=await fetchTimed(IMAGE_ENDPOINT.replace(/\/image$/,'/quota'),{headers:{Authorization:`Bearer ${session.access_token}`}},10000);if(!r.ok)throw Error('quota');const d=await r.json();label.textContent=Number.isFinite(d.remaining)?`${d.remaining} left today`:'3/day'}catch{label.textContent='3/day · checked on generation'}
}
async function generateImage(e){
  e.preventDefault();const status=$('#rathodImageStatus'),button=$('#rathodImageGenerate'),prompt=$('#rathodImagePrompt')?.value.trim();if(!prompt||!button)return;
  button.disabled=true;if(status)status.textContent='🎨 Image बन रही है…';$('#rathodImageResult')?.classList.add('hidden');
  try{const out=await requestImage(prompt);$('#rathodImagePreview').src=out.image;$('#rathodImageDownload').href=out.image;$('#rathodImageResult').classList.remove('hidden');if($('#rathodImageLimit'))$('#rathodImageLimit').textContent=out.remaining==null?'3/day':`${out.remaining} left today`;if(status)status.textContent=`✅ ${out.provider} image तैयार है`}
  catch(err){if(status)status.textContent=err.message||'Image नहीं बन पाई। फिर कोशिश करें।';await refreshImageLimit()}
  finally{button.disabled=false}
}

function boot(){load();health();$('#rathodAiAttach')?.addEventListener('click',()=>$('#rathodAiPhoto')?.click());$('#rathodAiPhoto')?.addEventListener('change',e=>choosePhotos([...e.target.files]));$('#rathodAiInput')?.addEventListener('paste',e=>{const files=[...e.clipboardData.items].filter(x=>x.type.startsWith('image/')).map(x=>x.getAsFile()).filter(Boolean);if(files.length){e.preventDefault();choosePhotos(files)}});$('#rathodAiForm')?.addEventListener('submit',e=>{e.preventDefault();send($('#rathodAiInput').value)});document.querySelectorAll('[data-ai-prompt]').forEach(b=>b.onclick=()=>send(b.dataset.aiPrompt));$('#rathodAiNew')?.addEventListener('click',()=>{if(!confirm('Rathod AI की इस device वाली chat history साफ करें?'))return;history=[];localStorage.removeItem(KEY);clearImages();pendingPhotos=[];photoPreview();if($('#rathodAiPhotoStatus'))$('#rathodAiPhotoStatus').textContent='';load()});$('#rathodAiInput')?.addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.shiftKey){e.preventDefault();$('#rathodAiForm').requestSubmit()}});window.addEventListener('online',health);$('#rathodImageForm')?.addEventListener('submit',generateImage);refreshImageLimit()}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
