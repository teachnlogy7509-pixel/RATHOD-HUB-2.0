package com.rathod.yptstudy;
import android.accessibilityservice.AccessibilityService;import android.view.accessibility.AccessibilityEvent;import android.content.*;import android.widget.Toast;import java.util.*;
public class FocusShieldService extends AccessibilityService {
 private static final Set<String> ALLOWED=new HashSet<>(Arrays.asList(
  "xyz.penpencil.physicswala","com.android.systemui","com.android.settings",
  "com.google.android.permissioncontroller","com.android.permissioncontroller","com.google.android.inputmethod.latin"
 ));
 @Override public void onAccessibilityEvent(AccessibilityEvent event){if(event.getEventType()!=AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED)return;if(!getSharedPreferences("focus",MODE_PRIVATE).getBoolean("shield",false))return;CharSequence p=event.getPackageName();if(p==null)return;String pkg=p.toString();if(pkg.equals(getPackageName())||ALLOWED.contains(pkg)||pkg.contains("launcher"))return;android.content.SharedPreferences prefs=getSharedPreferences("focus",MODE_PRIVATE);prefs.edit().putInt("blockedAttempts",prefs.getInt("blockedAttempts",0)+1).apply();performGlobalAction(GLOBAL_ACTION_HOME);Intent i=new Intent(this,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);startActivity(i);Toast.makeText(this,"Focus Shield: केवल YPT Study और PW allowed हैं",Toast.LENGTH_SHORT).show();}
 @Override public void onInterrupt(){}
}
