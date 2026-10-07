const COMMUNITY_SUPABASE={url:'https://oeacgchzyilgqzaqxssh.supabase.co',key:'sb_publishable_boL9uWFxb1hcOx7o9nb9Rw_OERUARlv'};
const REACTIONS=['👍','❤️','🔥','🎉','💡','👏'];
const $=s=>document.querySelector(s),$$=s=>[...document.querySelectorAll(s)];
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const initials=n=>String(n||'VIP').trim().split(/\s+/).map(x=>x[0]).join('').slice(0,2).toUpperCase();
function avatarReference(value){const v=String(value||'').trim();if(/^rathod-avatar:[a-z0-9-]+$/i.test(v)||/^data:image\/webp;base64,[A-Za-z0-9+/]+={0,2}$/.test(v))return v;try{const u=new URL(v,location.href);return u.protocol==='https:'?u.href:''}catch{return ''}}
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
function renderCommentTree(postId,parentId=null,depth=0){
  return comments.filter(c=>c.post_id===postId&&(c.parent_comment_id||null)===parentId).map(c=>{
    const children=renderCommentTree(postId,c.id,depth+1),replying=replyTarget===c.id;
    return `<div class="community-comment" style="--reply-depth:${Math.min(depth,5)}"><div class="comment-line">${personAvatar(c.display_name,c.user_id,'',avatarUrls[c.user_id])}<div><b>${esc(c.display_name)}</b><small>${when(c.created_at)}</small><p>${esc(c.body)}</p><button class="comment-reply" data-reply-comment="${c.id}" data-reply-post="${postId}">↳ Reply</button></div></div>${replying?`<form class="inline-reply-form" data-comment-form="${postId}" data-parent="${c.id}"><input required maxlength="600" placeholder="Reply to ${esc(c.display_name)}…"><button>Send</button></form>`:''}${children?`<div class="comment-children">${children}</div>`:''}</div>`
  }).join('')
}
function renderCommunity(){
  const feed=$('#communityFeed');if(!feed)return;
  if(!posts.length){feed.innerHTML='<div class="empty-real community-empty"><b>No posts yet</b>VIP Community में पहला study update आप share करें।</div>';return}
  feed.innerHTML=posts.map(p=>{
    const mine=reactions.find(r=>r.post_id===p.id&&r.user_id===user?.id)?.reaction_type;
    const buttons=REACTIONS.map(icon=>{const count=reactions.filter(r=>r.post_id===p.id&&r.reaction_type===icon).length;return `<button class="reaction-btn ${mine===icon?'active':''}" data-react-post="${p.id}" data-reaction="${icon}"><span>${icon}</span><b>${count||''}</b></button>`}).join('');
    const postComments=comments.filter(c=>c.post_id===p.id).length;
    return `<article class="community-post"><header>${personAvatar(p.display_name,p.user_id,'community-avatar',avatarUrls[p.user_id])}<div><b>${esc(p.display_name)}</b><small>VIP MEMBER · ${when(p.created_at)}</small></div><span class="vip-chip">VIP</span></header><p class="post-body">${esc(p.body)}</p><div class="reaction-row">${buttons}</div><div class="comments-head"><b>💬 ${postComments} ${postComments===1?'comment':'comments'}</b><span>Replies stay inside this post</span></div><div class="comment-tree">${renderCommentTree(p.id)}</div><form class="new-comment-form" data-comment-form="${p.id}" data-parent=""><input required maxlength="600" placeholder="Write a comment…"><button>Post</button></form></article>`
  }).join('');
  $$('[data-react-post]').forEach(b=>b.onclick=()=>reactToPost(b.dataset.reactPost,b.dataset.reaction));
  $$('[data-reply-comment]').forEach(b=>b.onclick=()=>{replyTarget=replyTarget===b.dataset.replyComment?null:b.dataset.replyComment;renderCommunity();if(replyTarget)$(`[data-parent="${replyTarget}"] input`)?.focus()});
  $$('[data-comment-form]').forEach(f=>f.onsubmit=sendComment);
}
window.addEventListener('rathod-avatar-equipped',event=>{if(user?.id&&event.detail?.avatarUrl)avatarUrls[user.id]=event.detail.avatarUrl;renderCommunity()});
window.addEventListener('rathod-view-changed',event=>{if(event.detail?.view==='community')loadCommunity()});
setInterval(()=>{if(document.querySelector('[data-page="community"]')?.classList.contains('active'))refreshCommunityAvatarUrls().then(renderCommunity)},60000);
async function reactToPost(postId,type){
  if(!user)return notify('Login required');
  const current=reactions.find(r=>r.post_id===postId&&r.user_id===user.id),snapshot=[...reactions];
  reactions=reactions.filter(r=>!(r.post_id===postId&&r.user_id===user.id));if(current?.reaction_type!==type)reactions.push({post_id:postId,user_id:user.id,reaction_type:type});renderCommunity();
  const result=current?.reaction_type===type?await client.from('ypt_community_reactions').delete().eq('post_id',postId).eq('user_id',user.id):await client.from('ypt_community_reactions').upsert({post_id:postId,user_id:user.id,reaction_type:type},{onConflict:'post_id,user_id'});
  if(result.error){reactions=snapshot;renderCommunity();notify(result.error.message)}
}
async function sendComment(e){
  e.preventDefault();if(!user)return notify('Login required');const form=e.currentTarget,input=form.querySelector('input'),body=input.value.trim();if(!body)return;
  input.disabled=true;const row={post_id:form.dataset.commentForm,user_id:user.id,display_name:name,body,parent_comment_id:form.dataset.parent||null};const {error}=await client.from('ypt_community_comments').insert(row);input.disabled=false;
  if(error)return notify(error.message);input.value='';replyTarget=null;await loadCommunity();
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
  const open=()=>{if(!user)return $('#authDialog')?.showModal();$('#communityPostDialog').showModal()};$('#newCommunityPost').onclick=open;$('#newCommunityPostSide').onclick=open;$('#communityPostForm').onsubmit=publishPost;
  client.channel('ypt-vip-community').on('postgres_changes',{event:'*',schema:'public',table:'ypt_community_posts'},scheduleReload).on('postgres_changes',{event:'*',schema:'public',table:'ypt_community_comments'},scheduleReload).on('postgres_changes',{event:'*',schema:'public',table:'ypt_community_reactions'},scheduleReload).subscribe();
  await loadCommunity();
}
initCommunity();
