package com.glpbuddy.glp_buddy

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.util.TypedValue
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import kotlin.math.min

/**
 * Home-screen widget showing today's stats.
 *
 * Progress is drawn as real rings: RemoteViews cannot host a custom view, so
 * each ring is rendered to a Bitmap here and set on an ImageView. That gives
 * rounded caps and a centred percentage, which a stock ProgressBar cannot do.
 *
 * Layouts are picked to fit the cell (square, wide, tall, large) and every
 * layout declares every view id, hidden where unused, so fill() never targets
 * a missing view.
 */
class GlpalsWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, build(context, appWidgetManager, id, widgetData))
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        appWidgetManager.updateAppWidget(
            appWidgetId,
            build(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context)),
        )
    }

    private fun build(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        data: SharedPreferences,
    ): RemoteViews {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Let the launcher pick the best layout for the current size.
            val map = mapOf(
                SizeF(110f, 110f) to fill(context, R.layout.widget_small, data, 44f),
                SizeF(250f, 110f) to fill(context, R.layout.widget_wide, data, 54f),
                SizeF(110f, 250f) to fill(context, R.layout.widget_tall, data, 52f),
                SizeF(250f, 250f) to fill(context, R.layout.widget_large, data, 60f),
            )
            return RemoteViews(map)
        }
        val opts = manager.getAppWidgetOptions(id)
        val w = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 110)
        val h = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)
        return when {
            w >= 250 && h >= 250 -> fill(context, R.layout.widget_large, data, 60f)
            w >= 250 -> fill(context, R.layout.widget_wide, data, 54f)
            h >= 250 -> fill(context, R.layout.widget_tall, data, 52f)
            else -> fill(context, R.layout.widget_small, data, 44f)
        }
    }

    /**
     * One progress ring: a translucent track, a rounded arc for [progress]
     * (0..1) and the percentage in the middle.
     */
    private fun ring(
        context: Context,
        progress: Float,
        arcColor: Int,
        sizeDp: Float,
        label: String,
    ): Bitmap {
        val density = context.resources.displayMetrics.density
        val size = (sizeDp * density).toInt().coerceAtLeast(24)
        val stroke = size * 0.115f
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val inset = stroke / 2f + 1f
        val box = RectF(inset, inset, size - inset, size - inset)

        val track = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            color = Color.argb(64, 255, 255, 255)
        }
        canvas.drawArc(box, 0f, 360f, false, track)

        val sweep = 360f * progress.coerceIn(0f, 1f)
        if (sweep > 0f) {
            val arc = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = stroke
                strokeCap = Paint.Cap.ROUND
                color = arcColor
            }
            canvas.drawArc(box, -90f, sweep, false, arc)
        }

        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textAlign = Paint.Align.CENTER
            textSize = size * 0.30f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val baseline = size / 2f - (text.descent() + text.ascent()) / 2f
        canvas.drawText(label, size / 2f, baseline, text)
        return bmp
    }

    private fun pct(value: Int, goal: Int): Float =
        if (goal <= 0) 0f else value.toFloat() / goal.toFloat()

    private fun pctLabel(value: Int, goal: Int): String =
        "${min(999, (pct(value, goal) * 100).toInt())}%"

    private fun fill(
        context: Context,
        layout: Int,
        data: SharedPreferences,
        ringDp: Float,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, layout)
        fun s(key: String, def: String) = data.getString(key, def) ?: def
        fun i(key: String, def: Int) = s(key, def.toString()).toIntOrNull() ?: def

        // Simple keeps only what gets acted on daily, and makes it bigger.
        val simple = s("widget_style", "detailed") == "simple"
        val textScale = when (s("widget_text", "normal")) {
            "large" -> 1.18f
            "xlarge" -> 1.38f
            else -> 1f
        }
        // Text sizes live here rather than in XML so one setting can scale
        // them all, including for readers who need them large.
        fun sp(id: Int, base: Float) =
            v.setTextViewTextSize(id, TypedValue.COMPLEX_UNIT_SP,
                base * textScale * (if (simple) 1.12f else 1f))
        // Rings grow with the style and the text setting, capped so they
        // cannot outgrow the cell they are drawn in.
        val ringCap = when (layout) {
            R.layout.widget_large -> 80f
            R.layout.widget_wide -> 72f
            R.layout.widget_tall -> 68f
            else -> 52f
        }
        val ringSize = (ringDp * (if (simple) 1.28f else 1f) *
            (if (textScale > 1.2f) 1.12f else if (textScale > 1f) 1.06f else 1f))
            .coerceAtMost(ringCap)

        val water = i("water_ml", 0)
        val waterGoal = i("water_goal", 2000).coerceAtLeast(1)
        val protein = i("protein_g", 0)
        val proteinGoal = i("protein_goal", 100).coerceAtLeast(1)
        val streak = i("streak", 0)
        val stageProgress = i("stage_progress", 0).coerceIn(0, 100)
        val checkedIn = s("checked_in", "0") == "1"

        // Rings. Colours are the app palette, brightened so they read on the
        // coral background.
        v.setImageViewBitmap(
            R.id.iv_water,
            ring(context, pct(water, waterGoal), Color.parseColor("#8FE6FF"), ringSize,
                pctLabel(water, waterGoal)),
        )
        v.setImageViewBitmap(
            R.id.iv_protein,
            ring(context, pct(protein, proteinGoal), Color.parseColor("#7CF0E2"), ringSize,
                pctLabel(protein, proteinGoal)),
        )
        v.setImageViewBitmap(
            R.id.iv_xp,
            ring(context, stageProgress / 100f, Color.parseColor("#FFE08A"), ringSize,
                "$stageProgress%"),
        )

        v.setTextViewText(R.id.tv_water, "💧 $water ml")
        v.setTextViewText(R.id.tv_protein, "🥩 $protein g")
        v.setTextViewText(R.id.tv_xp, "⭐ " + s("xp_total", "0") + " XP")

        v.setTextViewText(R.id.tv_pet, s("pet_emoji", "🥚"))
        v.setTextViewText(R.id.tv_name, s("pet_name", "GLPals"))
        v.setTextViewText(
            R.id.tv_streak,
            if (streak == 0) "🔥 Start a streak" else "🔥 $streak-day streak",
        )
        v.setTextViewText(
            R.id.tv_mood,
            if (checkedIn) s("mood", "") else "💤 No check-in yet today",
        )
        v.setTextViewText(R.id.tv_stage, s("stage_line", "Log a check-in to start growing"))
        v.setTextViewText(R.id.tv_shot, "💉 " + s("shot_line", "No shots logged yet"))
        v.setTextViewText(R.id.tv_last_shot, s("last_shot_line", "Log your first shot"))
        v.setTextViewText(R.id.tv_weight, "⚖️ " + s("weight_line", "No weight yet"))
        v.setTextViewText(R.id.tv_meals, "🍽️ " + s("meals_line", "No meals yet"))
        v.setTextViewText(
            R.id.tv_checkin,
            if (checkedIn) "✅ Checked in today" else "💤 No check-in yet",
        )
        v.setTextViewText(R.id.tv_updated, "Updated " + s("updated", "—"))
        v.setViewVisibility(
            R.id.tv_mood,
            if (s("mood", "").isEmpty() && checkedIn) View.GONE else View.VISIBLE,
        )

        // Countdown to the next dose. Inside a day it runs as a live
        // chronometer so it keeps ticking without the app pushing an update;
        // further out a plain "2d 4h" is enough.
        val dueMs = s("shot_due_ms", "0").toLongOrNull() ?: 0L
        val soon = s("shot_soon", "0") == "1"
        val fridge = s("fridge_tip", "0") == "1"
        val countdown = s("shot_countdown", "—")
        val hasDue = dueMs > 0L
        v.setTextViewText(
            R.id.tv_countdown,
            when {
                !hasDue -> "⏳ No dose scheduled"
                fridge -> "🧊 Pen out of the fridge ·"
                soon -> "⏳ Due in"
                countdown == "due now" -> "🎯 Due now"
                else -> "⏳ Due in $countdown"
            },
        )
        if (hasDue && soon) {
            v.setChronometer(
                R.id.chr_countdown,
                SystemClock.elapsedRealtime() + (dueMs - System.currentTimeMillis()),
                null,
                true,
            )
            v.setChronometerCountDown(R.id.chr_countdown, true)
            v.setViewVisibility(R.id.chr_countdown, View.VISIBLE)
        } else {
            v.setChronometer(R.id.chr_countdown, SystemClock.elapsedRealtime(), null, false)
            v.setViewVisibility(R.id.chr_countdown, View.GONE)
        }

        // Base text sizes per layout, scaled above.
        val big = layout == R.layout.widget_large
        val tall = layout == R.layout.widget_tall
        val tiny = layout == R.layout.widget_small
        sp(R.id.tv_name, if (big) 18f else if (tiny) 13f else if (tall) 15f else 14f)
        sp(R.id.tv_streak, if (tiny) 10f else 11f)
        sp(R.id.tv_mood, if (big) 11f else 10f)
        sp(R.id.tv_stage, if (big) 10f else 9f)
        sp(R.id.tv_water, if (big) 10f else if (tall) 9f else 10f)
        sp(R.id.tv_protein, if (big) 10f else if (tall) 9f else 10f)
        sp(R.id.tv_xp, if (big) 10f else if (tall) 9f else 10f)
        sp(R.id.tv_shot, if (big) 13f else if (tall) 11f else 12f)
        sp(R.id.tv_countdown, if (tiny) 10f else if (tall) 10f else 11f)
        sp(R.id.chr_countdown, if (tiny) 10f else if (tall) 10f else 11f)
        sp(R.id.tv_last_shot, 10f)
        sp(R.id.tv_weight, if (big) 11f else 10f)
        sp(R.id.tv_meals, if (big) 11f else 10f)
        sp(R.id.tv_checkin, 11f)
        sp(R.id.tv_updated, if (big) 10f else 9f)
        // The companion scales with the text, so the widget never ends up as a
        // big picture with unreadable numbers.
        v.setTextViewTextSize(
            R.id.tv_pet, TypedValue.COMPLEX_UNIT_SP,
            (if (big) 72f else if (tiny) 44f else if (tall) 62f else 60f) *
                (if (simple) 1.12f else 1f),
        )

        // Simple hides the secondary rows; every id still exists, so the next
        // switch back fills them in again.
        if (simple) {
            for (id in intArrayOf(
                R.id.tv_stage, R.id.tv_last_shot, R.id.tv_weight,
                R.id.tv_meals, R.id.tv_checkin, R.id.tv_updated,
                R.id.col_xp, R.id.tv_mood,
            )) {
                v.setViewVisibility(id, View.GONE)
            }
        }

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        v.setOnClickPendingIntent(R.id.widget_root, PendingIntent.getActivity(context, 0, intent, flags))
        return v
    }
}
