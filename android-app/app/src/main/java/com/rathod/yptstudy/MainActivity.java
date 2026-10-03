package com.rathod.yptstudy;

import android.app.*;
import android.os.*;
import android.provider.Settings;
import android.content.*;
import android.net.Uri;
import android.webkit.*;
import android.graphics.Color;
import android.content.pm.PackageManager;
import java.util.ArrayList;
import androidx.webkit.WebViewAssetLoader;
import androidx.webkit.WebViewClientCompat;

public class MainActivity extends Activity {
 private WebView web;
 private WebViewAssetLoader assetLoader;
 private static final String HOME="https://appassets.androidplatform.net/assets/index.html";
 @Override public void onCreate(Bundle b){
  super.onCreate(b);
  getWindow().setStatusBarColor(Color.rgb(18,9,10));
  web=new WebView(this); setContentView(web);
  assetLoader=new WebViewAssetLoader.Builder().addPathHandler("/assets/",new WebViewAssetLoader.AssetsPathHandler(this)).build();
  WebSettings s=web.getSettings();
  s.setJavaScriptEnabled(true); s.setDomStorageEnabled(true); s.setDatabaseEnabled(true);
  s.setCacheMode(WebSettings.LOAD_DEFAULT); s.setMediaPlaybackRequiresUserGesture(false);
  s.setAllowFileAccess(false); s.setAllowContentAccess(false);
  web.setBackgroundColor(Color.rgb(8,8,8));
  web.addJavascriptInterface(new FocusBridge(),"AndroidFocus");
  web.setWebChromeClient(new WebChromeClient(){
   @Override public void onPermissionRequest(PermissionRequest r){runOnUiThread(()->{ArrayList<String> allowed=new ArrayList<>();for(String resource:r.getResources())if(PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(resource)&&hasRecordAudioPermission())allowed.add(resource);if(allowed.isEmpty())r.deny();else r.grant(allowed.toArray(new String[0]));});}
  });
  web.setWebViewClient(new WebViewClientCompat(){
   @Override public WebResourceResponse shouldInterceptRequest(WebView view,WebResourceRequest request){return assetLoader.shouldInterceptRequest(request.getUrl());}
   @Override public boolean shouldOverrideUrlLoading(WebView v,WebResourceRequest r){Uri u=r.getUrl();String host=u.getHost();String raw=u.toString();if(host!=null&&(host.equals("t.me")||host.equals("telegram.me")||raw.endsWith(".apk"))){openExternal(u);return true;}return false;}
  });
  web.loadUrl(HOME);
 }
 private void openExternal(Uri u){try{startActivity(new Intent(Intent.ACTION_VIEW,u));}catch(Exception ignored){}}
 private boolean hasRecordAudioPermission(){return Build.VERSION.SDK_INT<23||checkSelfPermission(android.Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED;}
 public class FocusBridge {
  @JavascriptInterface public void setFocusShield(boolean enabled){getSharedPreferences("focus",MODE_PRIVATE).edit().putBoolean("shield",enabled).apply();}
  @JavascriptInterface public void openAccessibilitySettings(){runOnUiThread(()->startActivity(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)));}
  @JavascriptInterface public boolean isFocusShieldEnabled(){return getSharedPreferences("focus",MODE_PRIVATE).getBoolean("shield",false);}
  @JavascriptInterface public int getBlockedAttempts(){return getSharedPreferences("focus",MODE_PRIVATE).getInt("blockedAttempts",0);}
  @JavascriptInterface public void resetBlockedAttempts(){getSharedPreferences("focus",MODE_PRIVATE).edit().putInt("blockedAttempts",0).apply();}
  @JavascriptInterface public boolean isShieldServiceActive(){String enabled=Settings.Secure.getString(getContentResolver(),Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);return enabled!=null&&enabled.contains(getPackageName())&&enabled.contains("FocusShieldService");}
  @JavascriptInterface public boolean hasAudioPermission(){return hasRecordAudioPermission();}
  @JavascriptInterface public void requestAudioPermission(){runOnUiThread(()->{if(Build.VERSION.SDK_INT>=23&&!hasRecordAudioPermission())requestPermissions(new String[]{android.Manifest.permission.RECORD_AUDIO},42);});}
  @JavascriptInterface public void openPwApp(){runOnUiThread(()->{try{Intent i=getPackageManager().getLaunchIntentForPackage("xyz.penpencil.physicswala");if(i!=null)startActivity(i);else openExternal(Uri.parse("https://www.pw.live/"));}catch(Exception e){openExternal(Uri.parse("https://www.pw.live/"));}});}
 }
 @Override public void onBackPressed(){if(web.canGoBack())web.goBack();else super.onBackPressed();}
}
