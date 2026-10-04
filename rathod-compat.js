(()=>{
'use strict';
const $=s=>document.querySelector(s);
let deferred=window.__rathodInstallPrompt||null;
function toast(msg){const t=$('#toast');if(t){t.textContent=msg;t.classList.add('show');setTimeout(()=>t.classList.remove('show'),2800)}}
function installed(){return matchMedia('(display-mode: standalone)').matches||navigator.standalone===true}
function showInstallHelp(){let text='Chrome में ⋮ menu खोलें और “Install app” या “Add to Home screen” चुनें।';if(/iPad|iPhone|iPod/.test(navigator.userAgent))text='Safari में Share बटन दबाएँ, फिर “Add to Home Screen” चुनें।';if(/FBAN|FBAV|Instagram|Telegram/i.test(navigator.userAgent))text='यह page Chrome में खोलें, फिर Install app चुनें।';let d=$('#pwaHelpDialog');if(!d){d=document.createElement('dialog');d.id='pwaHelpDialog';d.className='pwa-help-dialog';d.innerHTML='<form method="dialog"><b>📲 Phone में app install करें</b><p id="pwaHelpText"></p><ol><li>Chrome में app खोलें</li><li>ऊपर ⋮ menu दबाएँ</li><li>Install app / Add to Home screen चुनें</li></ol><button class="primary">समझ गया</button></form>';document.body.appendChild(d)}$('#pwaHelpText').textContent=text;d.showModal()}
async function install(){if(installed())return toast('App पहले से installed है ✓');deferred=deferred||window.__rathodInstallPrompt;if(deferred){deferred.prompt();const result=await deferred.userChoice;deferred=null;window.__rathodInstallPrompt=null;if(result.outcome==='accepted')toast('YPT app install हो रहा है ✓');else showInstallHelp()}else showInstallHelp()}
window.addEventListener('beforeinstallprompt',e=>{e.preventDefault();deferred=e;window.__rathodInstallPrompt=e;window.dispatchEvent(new CustomEvent('rathod-install-ready',{detail:e}));$('#installAppBtn')?.classList.remove('hidden')});
window.addEventListener('appinstalled',()=>{$('#installAppBtn')?.classList.add('hidden');toast('YPT by Rathod installed ✓')});
function boot(){const b=$('#installAppBtn');if(b){b.classList.toggle('hidden',installed());b.onclick=install}if(!installed()&&b)b.classList.remove('hidden');if('serviceWorker'in navigator){navigator.serviceWorker.register('./sw.js',{updateViaCache:'none'}).then(r=>r.update()).catch(()=>{});navigator.serviceWorker.addEventListener('controllerchange',()=>{if(sessionStorage.getItem('rh_sw_reloaded'))return;sessionStorage.setItem('rh_sw_reloaded','1');location.reload()})}}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot);else boot();
})();
