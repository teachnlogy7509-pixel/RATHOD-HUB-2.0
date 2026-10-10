const COMMUNITY_SUPABASE={url:'https://oeacgchzyilgqzaqxssh.supabase.co',key:'sb_publishable_boL9uWFxb1hcOx7o9nb9Rw_OERUARlv'};
const REACTIONS=['👍','❤️','🔥','🎉','💡','👏'];
const $=s=>document.querySelector(s),$$=s=>[...document.querySelectorAll(s)];
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const initials=n=>String(n||'VIP').trim().split(/\s+/).map(x=>x[0]).join('').slice(0,2).toUpperCase();
function avatarReference(value){const v=String(value||'').trim();if(!v)return '';if(/^rathod-avatar:[a-z0-9-]+$/i.test(v)||/^data:image\/webp;base64,[A-Za-z0-9+/]+={0,2}$/.test(v))return v;try{const u=new URL(v,location.href);return u.protocol==='https:'?u.href:''}catch{return ''}}
function avatarImage(value){const ref=avatarReference(value);if(ref.startsWith('rathod-avatar:')){const src=window.__rathodAvatarImage?.(ref.slice(14))||'';return /^data:image\/webp;base64,[A-Za-z0-9+/]+={0,2}$/.test(src)?src:''}return ref}
function equippedAvatar(){try{const a=JSON.parse(localStorage.getItem('rh_ypt_equippedAvatar')||'null');return a&&typeof a.src==='string'&&/^data:image\/webp;base64,[A-Za-z0-9+/]+={0,2}$/.test(a.src)?a:null}catch{return null}}
function personAvatar(displayName,userId,className='',profileRef=''){const src=avatarImage(profileRef)||(user?.id&&userId===user.id?equippedAvatar()?.src:'');return `<span class="avatar${className?' '+className:''}${src?' has-reward-avatar':''}">${src?`<img class="profile-anime-avatar" src="${esc(src)}" alt="${esc(displayName)}">`:initials(displayName)}</span>`}

const when=v=>new Date(v).toLocaleString('en-IN',{day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'});
let client,user=null,name='VIP Member',posts=[],comments=[],reactions=[],avatarUrls={},replyTarget=null,reloadTimer=null;

function notify(message){const t=$('#toast');if(t){t.textContent=message;t.classList.add('show');setTimeout(()=>t.classList.remove('show'),2600)}}
function setupError(message){$('#communityStatus').innerHTML=`<div class="community-error"><b>Community setup required</b><span>${esc(message)}</span><small>Admin को Supabase में <code>ypt_community.sql</code> run करना होगा।</small></div>`}
async function refreshSession(){const {data}=await client.auth.getSession();user=data.session?.user||null;name=user?.user_metadata?.full_name||user?.email?.split('@')[0]||'VIP Member'}
async function refreshCommunityAvatarUrls(){if(!client||!user)return;const userIds=[...new Set([...posts,...comments].map(x=>x.user_id).filter(Boolean))];if(!userIds.length){avatarUrls={};return}const {data,error}=await client.from('ypt_profiles').select('id,avatar_url').in('id',userIds);if(!error)avatarUrls=Object.fromEntries((data||[]).map(x=>[x.id,avatarReference(x.avatar_url)]))}
async function loadCommunity(){
  if(!user){$('#communityFeed').innerHTML='<div class="empty-real"><b>Login required</b>VIP Community खोलने के लिए login करें।</div>';return}
  $('#communityStatus').innerHTML='';
  const p=await client.from('ypt_community_posts').select('*').order('created_at',{ascending:false}).limit(50);
  if(p.error){setupError(p.error.message);$('#communityFeed').innerHTML='';return}
  posts=p.data||[];const ids=posts.map(x=>x.id);
  if(!ids.length){comments=[];reactions=[];renderCommunity();return}
  const [c,r]=await Promise.all([client.from('ypt_community_comments').select('*').in('post_id',ids).order('created_at',{ascending:true}),client.from('ypt_community_reactions').select('*').in('post_id',ids)]);
  if(c.error||r.error){setupError(c.error?.message||r.error?.message);return}
  comments=c.data||[];reactions=r.data||[];await refreshCommunityAvatarUrls();renderCommunity();
}
const expanded=new Set();let openPostId=null;
function descCount(id){let n=0;comments.forEach(c=>{if(c.parent_comment_id===id){n+=1+descCount(c.id)}});return n}
function ensureCommentStyle(){if(document.getElementById('ccStyle'))return;const st=document.createElement('style');st.id='ccStyle';st.textContent=`
.post-actions{display:flex;border-top:1px solid #8882;margin-top:10px}.post-actions button{flex:1;background:none;border:0;padding:12px 6px;font-weight:700;font-size:14px;color:inherit;opacity:.8;cursor:pointer}
#ccDialog{padding:0;max-width:560px;width:min(560px,calc(100% - 20px));max-height:92vh;display:flex;flex-direction:column;overflow:hidden}#ccDialog:not([open]){display:none}
.cc-top{display:flex;justify-content:space-between;align-items:center;padding:14px 18px;border-bottom:1px solid #8883;font-weight:800}.cc-top button{background:none;border:0;color:inherit;font-size:24px;cursor:pointer;line-height:1}
.cc-scroll{overflow:auto;padding:14px 18px;flex:1;min-height:200px}.cc-post p{margin:8px 0}.cc-c{margin:12px 0}.cc-c .cc-row{display:flex;gap:10px}.cc-c .cc-box{flex:1;background:#8881;border-radius:12px;padding:8px 12px}.cc-box b{font-size:13px}.cc-box small{margin-left:6px;opacity:.65}.cc-box p{margin:4px 0;word-break:break-word}
.cc-acts{display:flex;gap:14px;margin-top:2px}.cc-acts button{background:none;border:0;padding:2px 0;font-size:12px;font-weight:800;color:inherit;opacity:.75;cursor:pointer}.cc-kids{margin-left:34px;border-left:2px solid #8883;padding-left:10px}
.cc-form{display:flex;flex-direction:column;gap:6px;border-top:1px solid #8883;padding:10px 14px}.cc-form .cc-to{display:flex;justify-content:space-between;font-size:12px;opacity:.8}.cc-form .cc-to button{background:none;border:0;color:inherit;cursor:pointer}.cc-form .cc-in{display:flex;gap:8px}.cc-form input{flex:1;min-width:0;padding:11px 12px;border-radius:12px;border:1px solid #8885;background:transparent;color:inherit;font-size:15px}.cc-form .cc-in button{border:0;border-radius:12px;padding:0 18px;font-weight:800;background:linear-gradient(135deg,#ffd978,#f0b83c);color:#2b1b00;cursor:pointer}
.cc-empty{text-align:center;opacity:.6;padding:30px 0}`;document.head.appendChild(st)}
function renderCommentTree(postId,parentId=null){
  return comments.filter(c=>c.post_id===postId&&(c.parent_comment_id||null)===parentId).map(c=>{
    const n=descCount(c.id),open=expanded.has(c.id);
    return `<div class="cc-c"><div class="cc-row">${personAvatar(c.display_name,c.user_id,'',avatarUrls[c.user_id])}<div class="cc-box"><b>${esc(c.display_name)}</b><small>${when(c.created_at)}</small><p>${esc(c.body)}</p><div class="cc-acts"><button type="button" data-reply-comment="${c.id}">↩ Reply</button>${n?`<button type="button" data-toggle-replies="${c.id}">${open?'Hide replies':`View ${n} ${n===1?'reply':'replies'}`}</button>`:''}</div></div></div>${n&&open?`<div class="cc-kids">${renderCommentTree(postId,c.id)}</div>`:''}</div>`
  }).join('')
}
function renderDialog(){
  const d=document.getElementById('ccDialog');if(!d||!d.open||!openPostId)return;
  const p=posts.find(x=>x.id===openPostId);if(!p){d.close();return}
  const top=comments.filter(c=>c.post_id===p.id).length;
  const sc=d.querySelector('.cc-scroll'),keep=sc?sc.scrollTop:0;
  d.querySelector('.cc-title').textContent=`Comments (${top})`;
  d.querySelector('.cc-scroll').innerHTML=`<div class="cc-post"><b>${esc(p.display_name)}</b> <small style="opacity:.6">${when(p.created_at)}</small><p>${esc(p.body)}</p></div><hr style="border:0;border-top:1px solid #8883">${renderCommentTree(p.id)||'<div class="cc-empty">Abhi koi comment nahi. Pehla comment karo!</div>'}`;
  sc.scrollTop=keep;
  const tgt=replyTarget?comments.find(c=>c.id===replyTarget):null,to=d.querySelector('.cc-to');
  to.style.display=tgt?'flex':'none';to.querySelector('span').textContent=tgt?`Replying to ${tgt.display_name}`:'';
  d.querySelector('.cc-in input').placeholder=tgt?'Write a reply…':'Write a comment…';
  d.querySelectorAll('[data-reply-comment]').forEach(b=>b.onclick=()=>{replyTarget=b.dataset.replyComment;renderDialog();d.querySelector('.cc-in input').focus()});
  d.querySelectorAll('[data-toggle-replies]').forEach(b=>b.onclick=()=>{const id=b.dataset.toggleReplies;expanded.has(id)?expanded.delete(id):expanded.add(id);renderDialog()});
}
function openComments(postId){
  ensureCommentStyle();openPostId=postId;replyTarget=null;let d=document.getElementById('ccDialog');
  if(!d){d=document.createElement('dialog');d.id='ccDialog';d.innerHTML=`<div class="cc-top"><span class="cc-title">Comments</span><button type="button" aria-label="Close">×</button></div><div class="cc-scroll"></div><form class="cc-form"><div class="cc-to" style="display:none"><span></span><button type="button">✕</button></div><div class="cc-in"><input required maxlength="600" placeholder="Write a comment…"><button>Post</button></div></form>`;document.body.appendChild(d);
    d.querySelector('.cc-top button').onclick=()=>d.close();d.addEventListener('close',()=>{openPostId=null;replyTarget=null});
    d.addEventListener('click',e=>{if(e.target===d)d.close()});
    d.querySelector('.cc-to button').onclick=()=>{replyTarget=null;renderDialog()};
    d.querySelector('.cc-form').onsubmit=sendComment}
  if(!d.open)d.showModal();renderDialog();
}
function renderCommunity(){
  const feed=$('#communityFeed');if(!feed)return;
  if(!posts.length){feed.innerHTML='<div class="empty-real community-empty"><b>No posts yet</b>VIP Community में पहला study update आप share करें।</div>';renderDialog();return}
  ensureCommentStyle();
  const html=posts.map(p=>{
    const mine=reactions.find(r=>r.post_id===p.id&&r.user_id===user?.id)?.reaction_type;
    const buttons=REACTIONS.map(icon=>{const count=reactions.filter(r=>r.post_id===p.id&&r.reaction_type===icon).length;return `<button class="reaction-btn ${mine===icon?'active':''}" data-react-post="${p.id}" data-reaction="${icon}"><span>${icon}</span><b>${count||''}</b></button>`}).join('');
    const n=comments.filter(c=>c.post_id===p.id).length;
    return `<article class="community-post"><header>${personAvatar(p.display_name,p.user_id,'community-avatar',avatarUrls[p.user_id])}<div><b>${esc(p.display_name)}</b><small>VIP MEMBER · ${when(p.created_at)}</small></div><span class="vip-chip">VIP</span></header><p class="post-body">${esc(p.body)}</p><div class="reaction-row">${buttons}</div><div class="post-actions"><button type="button" data-open-comments="${p.id}">💬 Comment${n?` (${n})`:''}</button></div></article>`
  }).join('');
  if(feed.__html!==html){feed.innerHTML=html;feed.__html=html;
    $$('[data-react-post]').forEach(b=>b.onclick=()=>reactToPost(b.dataset.reactPost,b.dataset.reaction));
    $$('[data-open-comments]').forEach(b=>b.onclick=()=>openComments(b.dataset.openComments))}
  renderDialog();
}
window.addEventListener('rathod-avatar-equipped',event=>{if(user?.id&&event.detail?.avatarUrl)avatarUrls[user.id]=event.detail.avatarUrl;renderCommunity()});
window.addEventListener('rathod-view-changed',event=>{if(event.detail?.view==='community')loadCommunity()});
setInterval(()=>{if(!document.hidden&&document.querySelector('[data-page="community"]')?.classList.contains('active'))refreshCommunityAvatarUrls().then(renderCommunity)},60000);
async function reactToPost(postId,type){
  if(!user)return notify('Login required');
  const current=reactions.find(r=>r.post_id===postId&&r.user_id===user.id),snapshot=[...reactions];
  reactions=reactions.filter(r=>!(r.post_id===postId&&r.user_id===user.id));if(current?.reaction_type!==type)reactions.push({post_id:postId,user_id:user.id,reaction_type:type});renderCommunity();
  const result=current?.reaction_type===type?await client.from('ypt_community_reactions').delete().eq('post_id',postId).eq('user_id',user.id):await client.from('ypt_community_reactions').upsert({post_id:postId,user_id:user.id,reaction_type:type},{onConflict:'post_id,user_id'});
  if(result.error){reactions=snapshot;renderCommunity();notify(result.error.message)}
}
async function sendComment(e){
  e.preventDefault();if(!user)return notify('Login required');const form=e.currentTarget,input=form.querySelector('input'),body=input.value.trim();if(!body||!openPostId)return;
  const parent=replyTarget||null;input.disabled=true;const row={post_id:openPostId,user_id:user.id,display_name:name,body,parent_comment_id:parent};const {error}=await client.from('ypt_community_comments').insert(row);input.disabled=false;
  if(error)return notify(error.message);input.value='';
  let pid=parent;while(pid){expanded.add(pid);pid=comments.find(c=>c.id===pid)?.parent_comment_id}
  replyTarget=null;await loadCommunity();
}
async function publishPost(e){
  e.preventDefault();if(!user)return notify('Login required');const body=$('#communityPostBody').value.trim();if(!body)return;$('#communityPostStatus').textContent='Publishing…';
  const {error}=await client.from('ypt_community_posts').insert({user_id:user.id,display_name:name,body});if(error){$('#communityPostStatus').textContent=error.message;return}
  e.target.reset();$('#communityPostStatus').textContent='';$('#communityPostDialog').close();await loadCommunity();notify('Post published to VIP Community');
}
function scheduleReload(){clearTimeout(reloadTimer);reloadTimer=setTimeout(loadCommunity,180)}
async function initCommunity(){
  if(!window.supabase||!$('#communityFeed'))return;client=window.supabase.createClient(COMMUNITY_SUPABASE.url,COMMUNITY_SUPABASE.key);await refreshSession();
  client.auth.onAuthStateChange(async()=>{await refreshSession();loadCommunity()});
  const open=()=>{if(!user)return $('#authDialog')?.showModal();$('#communityPostDialog').showModal()};$('#newCommunityPost').onclick=open;const sideBtn=$('#newCommunityPostSide');if(sideBtn)sideBtn.onclick=open;$('#communityPostForm').onsubmit=publishPost;
  client.channel('ypt-vip-community').on('postgres_changes',{event:'*',schema:'public',table:'ypt_community_posts'},scheduleReload).on('postgres_changes',{event:'*',schema:'public',table:'ypt_community_comments'},scheduleReload).on('postgres_changes',{event:'*',schema:'public',table:'ypt_community_reactions'},scheduleReload).subscribe();
  await loadCommunity();
}
initCommunity();
