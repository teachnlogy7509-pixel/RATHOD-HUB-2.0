package com.rathod.yptstudy;
import android.app.*;import android.os.*;import android.provider.Settings;import android.content.*;import android.net.Uri;import android.webkit.*;import android.graphics.Color;
public class MainActivity extends Activity {
 private WebView web;
 @Override public void onCreate(Bundle b){super.onCreate(b);getWindow().setStatusBarColor(Color.rgb(18,9,10));web=new WebView(this);setContentView(web);WebSettings s=web.getSettings();s.setJavaScriptEnabled(true);s.setDomStorageEnabled(true);s.setDatabaseEnabled(true);s.setCacheMode(WebSettings.LOAD_CACHE_ELSE_NETWORK);s.setMediaPlaybackRequiresUserGesture(false);web.addJavascriptInterface(new FocusBridge(),"AndroidFocus");web.setWebViewClient(new WebViewClient(){@Override public boolean shouldOverrideUrlLoading(WebView v,WebResourceRequest r){Uri u=r.getUrl();String host=u.getHost();if(host!=null&&(host.equals("t.me")||u.toString().endsWith(".apk"))){startActivity(new Intent(Intent.ACTION_VIEW,u));return true;}return false;}});web.loadUrl("file:///android_asset/index.html");}
 public class FocusBridge {
  @JavascriptInterface public void setFocusShield(boolean enabled){getSharedPreferences("focus",MODE_PRIVATE).edit().putBoolean("shield",enabled).apply();}
  @JavascriptInterface public void openAccessibilitySettings(){runOnUiThread(()->startActivity(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)));}
  @JavascriptInterface public boolean isFocusShieldEnabled(){return getSharedPreferences("focus",MODE_PRIVATE).getBoolean("shield",false);}
 }
 @Override public void onBackPressed(){if(web.canGoBack())web.goBack();else super.onBackPressed();}
}
