package com.arabnews.arab_news_reels

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

class NewsWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (widgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, widgetId)
        }
    }

    companion object {
        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            widgetId: Int
        ) {
            val data = HomeWidgetPlugin.getData(context)

            val headline = data.getString("widget_headline", "جارٍ تحميل الأخبار…") ?: "جارٍ تحميل الأخبار…"
            val source   = data.getString("widget_source", "كل دقيقة") ?: "كل دقيقة"
            val timeAgo  = data.getString("widget_time", "") ?: ""

            val views = RemoteViews(context.packageName, R.layout.news_widget)
            views.setTextViewText(R.id.widget_headline, headline)
            views.setTextViewText(R.id.widget_source, source)
            views.setTextViewText(R.id.widget_time, timeAgo)

            // Tap widget → open app
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context, 0, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_headline, pendingIntent)

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
