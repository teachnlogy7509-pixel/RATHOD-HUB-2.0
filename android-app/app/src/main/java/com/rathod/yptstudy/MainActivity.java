package com.rathod.yptstudy;
import android.app.*;import android.os.*;import android.webkit.*;import android.graphics.Color;
public class MainActivity extends Activity { private WebView web;
 public void onCreate(Bundle b){super.onCreate(b);getWindow().setStatusBarColor(Color.rgb(18,9,10));web=new WebView(this);setContentView(web);WebSettings s=web.getSettings();s.setJavaScriptEnabled(true);s.setDomStorageEnabled(true);s.setMediaPlaybackRequiresUserGesture(false);web.setWebViewClient(new WebViewClient());web.loadUrl("https://teachnlogy7509-pixel.github.io/RATHOD-HUB-2.0/");}
 @Override public void onBackPressed(){if(web.canGoBack())web.goBack();else super.onBackPressed();}
}
