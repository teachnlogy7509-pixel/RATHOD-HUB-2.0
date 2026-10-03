(() => {
  const URL = "https://oicluhfdvaroqvhwfwyp.supabase.co";
  const KEY = "sb_publishable_iXAoOGZ0YppBP0Y1kJf02Q_E323DzKA";
  let client;
  const $ = (s) => document.querySelector(s);
  const toast = (text) => { const n = $("#toast"); if (n) { n.textContent = text; n.classList.add("show"); setTimeout(() => n.classList.remove("show"), 3000); } };
  function panel() {
    if ($("#gyaanResetPanel")) return $("#gyaanResetPanel");
    const form = $("#authForm"); if (!form) return null;
    const box = document.createElement("div"); box.id = "gyaanResetPanel"; box.style.cssText = "display:none;margin-top:12px;padding:12px;border:1px solid #cbd5e1;border-radius:10px;background:#f8fafc";
    box.innerHTML = `<b style="display:block;font-size:12px;margin-bottom:8px">Forgot Password · OTP</b><input id="gyaanResetEmail" type="email" placeholder="Registered email" style="width:100%;padding:9px;border:1px solid #cbd5e1;border-radius:7px;margin-bottom:7px"><button type="button" id="gyaanSendReset" class="btn" style="width:100%;background:#334155">Send reset code</button><div id="gyaanResetStep" style="display:none;margin-top:8px"><input id="gyaanResetCode" inputmode="numeric" autocomplete="one-time-code" maxlength="8" placeholder="6-digit code" style="width:100%;padding:9px;border:1px solid #cbd5e1;border-radius:7px;margin-bottom:7px"><button type="button" id="gyaanVerifyReset" class="btn" style="width:100%;background:#258b68">Verify code</button><div id="gyaanNewPassword" style="display:none;margin-top:8px"><input id="gyaanNewPass" type="password" minlength="6" placeholder="New password" style="width:100%;padding:9px;border:1px solid #cbd5e1;border-radius:7px;margin-bottom:7px"><input id="gyaanNewPass2" type="password" minlength="6" placeholder="Confirm new password" style="width:100%;padding:9px;border:1px solid #cbd5e1;border-radius:7px;margin-bottom:7px"><button type="button" id="gyaanSavePass" class="btn" style="width:100%;background:#ef2b2b">Update password</button></div></div><small id="gyaanResetStatus" style="display:block;margin-top:7px;color:#475569"></small>`;
    form.appendChild(box); return box;
  }
  async function signup(event) {
    event.preventDefault(); event.stopImmediatePropagation();
    const email = $("#email")?.value.trim().toLowerCase(), password = $("#password")?.value || "", name = $("#name")?.value.trim() || email?.split("@")[0] || "Learner";
    if (!email || password.length < 6) return toast("Valid email और 6+ character password डालें.");
    const button = $("#signup"); if (button) { button.disabled = true; button.textContent = "Creating account…"; }
    try {
      const response = await fetch(`${URL}/functions/v1/gyaan-signup`, { method: "POST", headers: { apikey: KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email, password, name }) });
      const result = await response.json().catch(() => ({})); if (!response.ok) throw new Error(result.error || "Account creation failed");
      const login = await client.auth.signInWithPassword({ email, password }); if (login.error) throw login.error;
      toast("Account created — no verification code required ✓"); setTimeout(() => location.reload(), 700);
    } catch (error) { toast(error.message || "Account creation failed"); } finally { if (button) { button.disabled = false; button.textContent = "Create account"; } }
  }
  async function sendCode() {
    const email = ($( "#gyaanResetEmail")?.value || $("#email")?.value || "").trim().toLowerCase(); const status = $("#gyaanResetStatus");
    if (!email) { if (status) status.textContent = "Registered email डालें."; return; }
    $("#gyaanResetEmail").value = email; const result = await client.auth.resetPasswordForEmail(email); if (result.error) { if (status) status.textContent = result.error.message; return; }
    $("#gyaanResetStep").style.display = "block"; if (status) status.textContent = "Reset code email पर भेज दिया गया. Spam folder भी check करें.";
  }
  async function verifyCode() {
    const email = $("#gyaanResetEmail").value.trim().toLowerCase(), code = $("#gyaanResetCode").value.trim(), status = $("#gyaanResetStatus");
    if (!/^\d{6,8}$/.test(code)) { if (status) status.textContent = "6 या 8 digit code डालें."; return; }
    const result = await client.auth.verifyOtp({ email, token: code, type: "recovery" }); if (result.error) { if (status) status.textContent = result.error.message; return; }
    $("#gyaanNewPassword").style.display = "block"; $("#gyaanVerifyReset").style.display = "none"; if (status) status.textContent = "Code verified. नया password सेट करें.";
  }
  async function savePassword() {
    const a = $("#gyaanNewPass").value, b = $("#gyaanNewPass2").value, status = $("#gyaanResetStatus");
    if (a.length < 6 || a !== b) { if (status) status.textContent = "Password 6+ characters का और दोनों समान होना चाहिए."; return; }
    const result = await client.auth.updateUser({ password: a }); if (result.error) { if (status) status.textContent = result.error.message; return; }
    toast("Password updated successfully ✓"); setTimeout(() => location.reload(), 700);
  }
  function bind() {
    const signupButton = $("#signup"); if (signupButton && !signupButton.dataset.gyaanAuthFix) { signupButton.dataset.gyaanAuthFix = "1"; signupButton.addEventListener("click", signup, true); }
    const oldForgot = $("#rhccForgotPassword"); if (oldForgot) oldForgot.style.display = "none";
    const box = panel(); if (!box || box.dataset.bound) return;
    box.dataset.bound = "1"; $("#gyaanSendReset").addEventListener("click", sendCode); $("#gyaanVerifyReset").addEventListener("click", verifyCode); $("#gyaanSavePass").addEventListener("click", savePassword);
    const forgot = document.createElement("button"); forgot.type = "button"; forgot.id = "gyaanForgotButton"; forgot.className = "btn"; forgot.style.cssText = "width:100%;margin-top:8px;background:#64748b"; forgot.textContent = "Forgot password · Send OTP"; forgot.addEventListener("click", (e) => { e.preventDefault(); box.style.display = box.style.display === "none" ? "block" : "none"; }); formInsert(forgot);
  }
  function formInsert(button) { const form = $("#authForm"); const signupButton = $("#signup"); if (form && signupButton && !$("#gyaanForgotButton")) signupButton.insertAdjacentElement("afterend", button); }
  async function init() { const m = await import("https://esm.sh/@supabase/supabase-js@2"); client = m.createClient(URL, KEY); setInterval(bind, 500); bind(); }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", () => setTimeout(init, 500), { once: true }); else setTimeout(init, 500);
})();
