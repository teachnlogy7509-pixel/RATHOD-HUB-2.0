(()=>{
'use strict';
const $=s=>document.querySelector(s),esc=s=>String(s??'').replace(/[&<>"']/g,x=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[x]));
const cash=p=>new Intl.NumberFormat('en-IN',{style:'currency',currency:'INR',minimumFractionDigits:2}).format(Number(p||0)/100);
const dateTime=t=>new Date(t).toLocaleString('en-IN',{timeZone:'Asia/Kolkata',day:'numeric',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'});
const shortDate=t=>new Date(t+'T12:00:00+05:30').toLocaleDateString('en-IN',{timeZone:'Asia/Kolkata',weekday:'short',day:'numeric',month:'short'});
const pendingKey='rh_ypt_pending_referral';
let activeUser=null,generation=0,data=null,ready=false,loading=false,queue=Promise.resolve(),transactions=[],hasMore=false,historyLoading=false,referralApplying=false;
let liveAckAt=0,liveAckSeconds=0,liveTracking=false,trackingProblem='';
let status='Sign in to earn study and referral rewards.',statusKind='guest',monitor;
try{monitor=sessionStorage.getItem('rh_ypt_wallet_monitor');if(!monitor){monitor=crypto.randomUUID();sessionStorage.setItem('rh_ypt_wallet_monitor',monitor)}}catch{monitor=crypto.randomUUID()}
try{const ref=new URL(location.href).searchParams.get('ref');if(ref&&/^[a-f\d]{12}$/i.test(ref))localStorage.setItem(pendingKey,ref.toUpperCase())}catch{}
function inviteLink(){if(!ready||!data?.referral_code)return '';const url=new URL(location.pathname,location.origin);url.searchParams.set('ref',data.referral_code);return url.href}
function user(){return window.rhWalletApp?.user?.()||null}
function client(){return window.rhWalletApp?.db?.()||null}
function missing(e){return ['PGRST202','42P01','42883'].includes(e?.code)||/could not find the function|schema cache|does not exist/i.test(e?.message||'')}
function errorText(e){return e?.message||'Wallet connection failed. Please refresh when online.'}
async function rpc(name,args={}){const db=client();if(!db||!user())throw Error('Sign in to use Wallet.');const r=await db.rpc(name,args);if(r.error)throw r.error;return r.data}
function kindLabel(kind){return ({admin_credit:'Admin credit',study:'Study reward',referral_inviter:'Referral · invited a new learner',referral_joiner:'Referral · new signup bonus'})[kind]||'Reward credit'}
function row(t){return `<article class="wallet-transaction"><div class="wallet-transaction-top"><b>${esc(kindLabel(t.kind))}</b><strong>+${cash(t.amount_paise)}</strong></div><p>${esc(dateTime(t.earned_at))}</p><small>Expires ${esc(dateTime(t.expires_at))}${t.status==='expired'?' · Expired':''}</small></article>`}
function renderHistory(){
 if($('#walletWeekTotal'))$('#walletWeekTotal').textContent=ready?cash(data.week_earned_paise):'₹—';
 if($('#walletDailyRows'))$('#walletDailyRows').innerHTML=ready?(data.seven_day_earnings||[]).map(d=>`<div class="wallet-daily-row"><span>${esc(shortDate(d.date))}</span><strong>${cash(d.amount_paise)}</strong></div>`).join(''):'<p class="wallet-history-empty">Sign in and connect Wallet to see your real 7-day total.</p>';
 if($('#walletTransactions'))$('#walletTransactions').innerHTML=transactions.length?transactions.map(row).join(''):`<p class="wallet-history-empty">${ready?'No earnings in the last 7 days. Start a focus session or invite a new learner.':'Your earning history will appear here after Wallet is enabled.'}</p>`;
 $('#walletLoadMore')?.classList.toggle('hidden',!ready||!hasMore);
}
// Smooth display only: monetary credit is still granted exclusively by Supabase.
// Show seconds so a small amount of study is visibly updating toward 8 hours.
function paintProgress(){
 const ackAge=liveAckAt?Math.max(0,(performance.now()-liveAckAt)/1000):0;
 const projecting=ready&&liveTracking&&navigator.onLine&&window.rhWalletApp?.running?.()&&user()?.id===activeUser;
 let progress=Number(data?.progress_seconds||0);
 if(projecting)progress=Math.min(28799,liveAckSeconds+Math.min(45,Math.floor(ackAge)));
 const bar=$('#walletStudyProgress'),text=$('#walletStudyProgressText');
 if(bar){bar.value=ready?progress:0;bar.setAttribute('aria-valuetext',ready?`${Math.floor(progress/3600)} hours ${Math.floor(progress%3600/60)} minutes ${Math.floor(progress%60)} seconds of 8 hours`:'Sign in to earn rewards.');bar.title=projecting?'Live display estimate. Rewards and balance update only after server confirmation.':'Server-confirmed reward study progress.'}
 if(text){text.textContent=ready?`${Math.floor(progress/3600)}h ${Math.floor(progress%3600/60)}m ${Math.floor(progress%60)}s / 8h${!navigator.onLine?' · Offline':trackingProblem?' · Paused':projecting&&ackAge>45?' · Syncing…':''}`:'Sign in to start earning.';text.title=trackingProblem||(projecting?'The moving seconds are a live display estimate, not extra wallet credits.':'Server-confirmed study seconds.')}
}
function render(){
 const today=ready?cash(data.today_earned_paise):'₹—';
 if($('#walletTopToday'))$('#walletTopToday').textContent=ready?new Intl.NumberFormat('en-IN',{minimumFractionDigits:0,maximumFractionDigits:2}).format(Number(data.today_earned_paise||0)/100):'—';
 if($('#walletGridToday'))$('#walletGridToday').textContent=today;
 if($('#walletAvailable'))$('#walletAvailable').textContent=ready?cash(data.available_paise):'₹—';
 if($('#walletToday'))$('#walletToday').textContent=today;
 const st=$('#walletStatus');if(st){st.classList.toggle('ready',ready);st.classList.toggle('hidden',ready);st.innerHTML=esc(status)+(statusKind==='guest'?' <button class="text-btn" id="walletLogin">Sign in →</button>':'');$('#walletLogin')?.addEventListener('click',()=>window.rhWalletApp?.login?.())}
 paintProgress();
 if($('#walletExpiryNote'))$('#walletExpiryNote').textContent=ready&&data.expiring_7d_paise>0?`${cash(data.expiring_7d_paise)} expiring soon`:'6 months per credit';
 const link=inviteLink();if($('#walletReferralLink'))$('#walletReferralLink').value=link;
 if($('#walletCopyLink'))$('#walletCopyLink').disabled=!link;if($('#walletShareLink'))$('#walletShareLink').disabled=!link;
 if($('#walletReferralCount'))$('#walletReferralCount').textContent=`${ready?data.referrals_count:0} successful referrals`;
 $('#walletReferralForm')?.classList.toggle('hidden',!ready||!data.can_claim_referral);
 renderHistory();
}
function accept(snapshot,gen=generation){if(gen!==generation||!user()||user().id!==activeUser||!snapshot)return false;
 // A slow Store/refresh response must not roll back a newer focus or balance result.
 if(data){const incoming=Date.parse(snapshot.server_time),current=Date.parse(data.server_time);if(Number.isFinite(incoming)&&Number.isFinite(current)&&incoming<current)return false;if(Number(snapshot.study_seconds||0)<Number(data.study_seconds||0))return false}
 data=snapshot;if(liveTracking){liveAckSeconds=Number(snapshot.progress_seconds||0);liveAckAt=performance.now();} ready=true;statusKind='ready';status='Wallet connected · Rewards use online, logged-in focus time · India time';transactions=[...(data.transactions||[])];hasMore=transactions.length===50;render();return true}
async function refresh(){
 if(loading)return;if(!user()){ready=false;data=null;statusKind='guest';status='Sign in to earn study and referral rewards.';render();return}
 const gen=generation;loading=true;status='Refreshing Wallet…';render();
 try{const snapshot=await rpc('ypt_wallet_snapshot');if(!accept(snapshot,gen))return;await applyPendingReferral();if(window.rhWalletApp?.running?.())focus('start')}
 catch(e){if(gen!==generation)return;ready=false;data=null;transactions=[];statusKind=missing(e)?'pending':'error';status=missing(e)?'Wallet setup pending · Admin must run supabase/ypt_wallet.sql in the Rathod Hub project. No earning has been credited yet.':errorText(e);render()}
 finally{if(gen===generation)loading=false}
}
async function claim(code){
 if(referralApplying)return;referralApplying=true;const gen=generation;const message=$('#walletReferralStatus');if(message)message.textContent='Checking referral…';
 try{const snapshot=await rpc('ypt_wallet_claim_referral',{p_code:String(code).trim().toUpperCase()});if(!accept(snapshot,gen))return;localStorage.removeItem(pendingKey);if(message)message.textContent=snapshot.claim_status==='credited_both'?'₹10 credited to you and ₹10 to your referrer.':'This account has already received its referral reward.'}
 catch(e){if(gen!==generation)return;if(message)message.textContent=errorText(e);if(!missing(e)&&!/network|fetch|connection|confirm.*email/i.test(errorText(e)))try{localStorage.removeItem(pendingKey)}catch{}}
 finally{if(gen===generation)referralApplying=false}
}
async function applyPendingReferral(){let code=data?.pending_referral_code;try{code=code||localStorage.getItem(pendingKey)}catch{}if(code&&ready)await claim(code)}
function onAuth(u){const id=u?.id||null;if(id===activeUser){if(id&&!loading&&!ready)refresh();return}activeUser=id;generation++;liveTracking=false;liveAckAt=0;liveAckSeconds=0;trackingProblem='';loading=false;referralApplying=false;historyLoading=false;data=null;ready=false;transactions=[];hasMore=false;statusKind=id?'loading':'guest';status=id?'Wallet loading…':'Sign in to earn study and referral rewards.';render();if(id)refresh()}
function focus(action){
 if(action==='pause'||action==='finish'){liveTracking=false;paintProgress()}
 const gen=generation,uid=activeUser;
 queue=queue.catch(()=>{}).then(async()=>{
  if(!ready||!uid||uid!==activeUser||gen!==generation||!navigator.onLine)return;
  try{const snapshot=await rpc('ypt_wallet_focus',{p_action:action,p_monitor:monitor});if(gen===generation){if(accept(snapshot,gen)){trackingProblem='';liveTracking=(action==='start'||action==='tick')&&!!window.rhWalletApp?.running?.();liveAckAt=performance.now();liveAckSeconds=Number(data.progress_seconds||0);paintProgress()}}}
  catch(e){if(gen!==generation)return;liveTracking=false;trackingProblem=errorText(e);const st=$('#walletStudyProgressText');if(st)st.textContent='Reward tracking paused: '+errorText(e);if(missing(e)){ready=false;statusKind='pending';status='Wallet setup pending · Run the wallet SQL to enable rewards.';render()}}
 });return queue;
}
async function loadMore(){
 if(!ready||historyLoading||!transactions.length)return;historyLoading=true;const gen=generation,button=$('#walletLoadMore'),last=transactions.at(-1);button.disabled=true;
 try{const rows=await rpc('ypt_wallet_history',{p_before:last.earned_at,p_before_id:last.id});if(gen!==generation)return;const seen=new Set(transactions.map(t=>t.id));transactions.push(...rows.filter(t=>!seen.has(t.id)));hasMore=rows.length===50;renderHistory()}
 catch(e){if($('#walletHistoryStatus'))$('#walletHistoryStatus').textContent=errorText(e)}finally{historyLoading=false;button.disabled=false}
}
function tab(which){for(const part of ['summary','history']){$(`[data-wallet-tab="${part}"]`)?.classList.toggle('active',part===which);$(`[data-wallet-tab="${part}"]`)?.setAttribute('aria-selected',String(part===which));$(part==='summary'?'#walletSummary':'#walletHistory')?.classList.toggle('hidden',part!==which)}if(which==='history')refresh()}
function open(which='summary'){window.rhWalletApp?.navigate?.('wallet');tab(which)}
async function copyLink(){const link=inviteLink();if(!link)return;try{await navigator.clipboard.writeText(link);$('#walletReferralStatus').textContent='Your personal referral link copied.'}catch{const details=$('.wallet-link-details');if(details)details.open=true;$('#walletReferralLink').select();$('#walletReferralStatus').textContent='Link selected. Use Copy to share it.'}}
async function shareLink(){const url=inviteLink();if(!url)return;if(navigator.share)try{await navigator.share({title:'Study with me on Rathod Hub',text:'Join with my link. New signups: ₹10 reward credits for both of us.',url});return}catch(e){if(e.name==='AbortError')return}await copyLink()}
function context(){return {type:'app_reward_credits_not_bank_cash',backendStatus:statusKind,
 rules:{study:'Each completed 8 cumulative hours of server-counted, logged-in online focus earns ₹5. No offline or old-session conversion.',referral:'Unique link per user; successful eligible new signup credits ₹10 to both inviter and new user, once. The invite link must be used before account creation; confirm email if required. No self or duplicate referral.',expiry:'Every earning expires separately 6 calendar months after credit. Available balance excludes expired credits.',header:'Top rupee count is today’s earnings, NOT total available balance.',history:'7 calendar days: today and previous 6 days, Asia/Kolkata. Includes both study and referral credits.',store:'Reward Store: Analog Timer ₹20; Study Report PDF ₹50. One-time account unlocks paid in unexpired wallet credits. Report downloads cover 7 days or a selected month of the signed-in user’s cloud-saved study/planner records. Purchases require server setup and explicit confirmation; see store status. No cash withdrawal.'},
 balance:ready?{available_paise:data.available_paise,today_earned_paise:data.today_earned_paise,seven_day_earned_paise:data.week_earned_paise,server_time:data.server_time}:null,
 store:window.rhStore?.context?.()||{status:'loading'},aiPermissions:'Read and explain only. AI cannot credit money, alter ledger, withdraw cash, or purchase without user confirmation.'}}
window.rhWallet={onAuth,refresh,focus,open,context,acceptSnapshot:accept,signupReferral:()=>{try{return localStorage.getItem(pendingKey)||null}catch{return null}}};
function boot(){render();$('#walletRefresh')?.addEventListener('click',refresh);$('#walletCopyLink')?.addEventListener('click',copyLink);$('#walletShareLink')?.addEventListener('click',shareLink);$('#walletLoadMore')?.addEventListener('click',loadMore);document.querySelectorAll('[data-wallet-tab]').forEach(b=>b.addEventListener('click',()=>tab(b.dataset.walletTab)));$('#walletReferralForm')?.addEventListener('submit',e=>{e.preventDefault();claim($('#walletReferralCode').value)});
 let n=0;const timer=setInterval(()=>{if(window.rhWalletApp){clearInterval(timer);onAuth(user())}else if(++n>100)clearInterval(timer)},100);
 setInterval(paintProgress,1000);
 setInterval(()=>{if(window.rhWalletApp?.running?.()&&ready&&navigator.onLine)focus('tick')},20000);
 setInterval(()=>{if(ready&&!document.hidden)refresh()},60000);
 window.addEventListener('online',refresh);window.addEventListener('offline',()=>{liveTracking=false;paintProgress()});document.addEventListener('visibilitychange',()=>{if(document.hidden&&ready&&window.rhWalletApp?.running?.())focus('tick');if(!document.hidden&&user())refresh()});window.addEventListener('rathod-view-changed',e=>{if(e.detail?.view==='wallet'){window.scrollTo({top:0,behavior:'instant'});const view=$('[data-page=wallet]');if(view)view.scrollTop=0;refresh()}});
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);else boot();
})();
