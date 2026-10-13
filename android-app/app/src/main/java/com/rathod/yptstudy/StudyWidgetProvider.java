package com.rathod.yptstudy;
import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.content.Intent;
import android.content.ComponentName;
import android.content.SharedPreferences;
import android.widget.RemoteViews;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

public class StudyWidgetProvider extends AppWidgetProvider {
 public static final String OPEN_TIMER="com.rathod.yptstudy.OPEN_TIMER";
 @Override public void onUpdate(Context context,AppWidgetManager manager,int[] ids){for(int id:ids)update(context,manager,id);}
 public static void updateAll(Context context){AppWidgetManager manager=AppWidgetManager.getInstance(context);for(int id:manager.getAppWidgetIds(new ComponentName(context,StudyWidgetProvider.class)))update(context,manager,id);}
 private static void update(Context context,AppWidgetManager manager,int id){
  SharedPreferences p=context.getSharedPreferences("study_widget",Context.MODE_PRIVATE);
  boolean signed=p.getBoolean("signed_in",false);long seconds=signed?Math.max(0,p.getLong("today_seconds",0)):0;
  RemoteViews views=new RemoteViews(context.getPackageName(),R.layout.study_widget);
  views.setTextViewText(R.id.widget_time,signed?String.format(Locale.ROOT,"%dh %02dm",seconds/3600,(seconds%3600)/60):"Welcome");
  views.setTextViewText(R.id.widget_task,signed?p.getString("next_task","Open app to focus"):"Sign in to see your study summary");
  long updated=p.getLong("updated_at",0);
  views.setTextViewText(R.id.widget_status,updated>0?"Updated "+new SimpleDateFormat("dd MMM HH:mm",Locale.ROOT).format(new Date(updated))+" · Tap to focus":"Tap to open YPT");
  Intent open=new Intent(context,MainActivity.class).setAction(OPEN_TIMER).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP|Intent.FLAG_ACTIVITY_CLEAR_TOP);
  PendingIntent click=PendingIntent.getActivity(context,41,open,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
  views.setOnClickPendingIntent(R.id.study_widget_root,click);manager.updateAppWidget(id,views);
 }
}
