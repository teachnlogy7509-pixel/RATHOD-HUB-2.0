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
 private byte[] pendingVoiceExport;
 private static final int VOICE_EXPORT_REQUEST=61;
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
  web.loadUrl(HOME+(StudyWidgetProvider.OPEN_TIMER.equals(getIntent().getAction())?"#timer":""));
 }
 private void openExternal(Uri u){try{startActivity(new Intent(Intent.ACTION_VIEW,u));}catch(Exception ignored){}}
 private boolean hasRecordAudioPermission(){return Build.VERSION.SDK_INT<23||checkSelfPermission(android.Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED;}
 @Override protected void onNewIntent(Intent intent){super.onNewIntent(intent);setIntent(intent);if(web!=null&&StudyWidgetProvider.OPEN_TIMER.equals(intent.getAction()))web.evaluateJavascript("if(window.rhWalletApp){window.rhWalletApp.navigate('timer')}",null);}
 @Override protected void onActivityResult(int request,int result,Intent data){
  super.onActivityResult(request,result,data);if(request!=VOICE_EXPORT_REQUEST)return;final byte[] bytes=pendingVoiceExport;pendingVoiceExport=null;
  if(result!=RESULT_OK||data==null||data.getData()==null||bytes==null)return;final Uri target=data.getData();
  new Thread(()->{try(java.io.OutputStream out=getContentResolver().openOutputStream(target,"w")){if(out==null)throw new java.io.IOException("No output stream");out.write(bytes);runOnUiThread(()->android.widget.Toast.makeText(this,"Voice backup saved",android.widget.Toast.LENGTH_SHORT).show());}catch(Exception e){runOnUiThread(()->android.widget.Toast.makeText(this,"Backup could not be saved. Your original recording is unchanged.",android.widget.Toast.LENGTH_LONG).show());}}).start();
 }
 public class FocusBridge {
  @JavascriptInterface public void exportVoiceBackup(String mime,String filename,String encoded){
   if(encoded==null||encoded.length()>14000000||filename==null||!filename.matches("[A-Za-z0-9._-]{1,120}")||!("audio/webm".equals(mime)||"audio/mp4".equals(mime)))return;
   final byte[] bytes;try{bytes=android.util.Base64.decode(encoded,android.util.Base64.DEFAULT);}catch(IllegalArgumentException e){return;}if(bytes.length==0||bytes.length>10*1024*1024)return;
   runOnUiThread(()->{try{if(pendingVoiceExport!=null)return;pendingVoiceExport=bytes;Intent intent=new Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType(mime).putExtra(Intent.EXTRA_TITLE,filename);startActivityForResult(intent,VOICE_EXPORT_REQUEST);}catch(Exception e){pendingVoiceExport=null;android.widget.Toast.makeText(MainActivity.this,"Backup picker unavailable. Original recording is unchanged.",android.widget.Toast.LENGTH_LONG).show();}});
  }

  @JavascriptInterface public void updateStudyWidget(String raw){
   try{if(raw==null||raw.length()>4096)return;org.json.JSONObject data=new org.json.JSONObject(raw);boolean signed=data.optBoolean("signed_in",false);long seconds=signed?Math.max(0,Math.min(864000L,data.optLong("today_seconds",0))):0;String task=signed?data.optString("next_task","Open app to focus"):"Sign in to see your study summary";if(task.length()>160)task=task.substring(0,160);
    android.content.SharedPreferences p=getSharedPreferences("study_widget",MODE_PRIVATE);if(p.getBoolean("signed_in",false)==signed&&p.getLong("today_seconds",0)==seconds&&p.getString("next_task","").equals(task))return;
    p.edit().putBoolean("signed_in",signed).putLong("today_seconds",seconds).putString("next_task",task).putLong("updated_at",System.currentTimeMillis()).apply();StudyWidgetProvider.updateAll(MainActivity.this);
   }catch(Exception ignored){}
  }
  @JavascriptInterface public void requestStudyWidget(){runOnUiThread(()->{android.appwidget.AppWidgetManager manager=android.appwidget.AppWidgetManager.getInstance(MainActivity.this);if(Build.VERSION.SDK_INT>=26&&manager.isRequestPinAppWidgetSupported())manager.requestPinAppWidget(new ComponentName(MainActivity.this,StudyWidgetProvider.class),null,null);else android.widget.Toast.makeText(MainActivity.this,"Long-press home screen → Widgets → YPT Study",android.widget.Toast.LENGTH_LONG).show();});}

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
