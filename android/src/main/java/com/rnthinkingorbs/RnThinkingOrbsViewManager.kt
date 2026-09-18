package com.rnthinkingorbs

import android.graphics.Color
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.uimanager.annotations.ReactProp
import com.facebook.react.viewmanagers.RnThinkingOrbsViewManagerDelegate
import com.facebook.react.viewmanagers.RnThinkingOrbsViewManagerInterface

@ReactModule(name = RnThinkingOrbsViewManager.NAME)
class RnThinkingOrbsViewManager :
  SimpleViewManager<ThinkingOrbsView>(), RnThinkingOrbsViewManagerInterface<ThinkingOrbsView> {
  private val delegate: ViewManagerDelegate<ThinkingOrbsView> =
    RnThinkingOrbsViewManagerDelegate(this)

  override fun getDelegate(): ViewManagerDelegate<ThinkingOrbsView> = delegate

  override fun getName(): String = NAME

  public override fun createViewInstance(context: ThemedReactContext): ThinkingOrbsView =
    ThinkingOrbsView(context)

  @ReactProp(name = "accentColor")
  override fun setAccentColor(view: ThinkingOrbsView?, value: String?) {
    view?.accentColor = parseColor(value, Color.parseColor("#2A67F4"))
  }

  @ReactProp(name = "dotColor")
  override fun setDotColor(view: ThinkingOrbsView?, value: String?) {
    view?.dotColor = parseColor(value, Color.BLACK)
  }

  @ReactProp(name = "animated", defaultBoolean = true)
  override fun setAnimated(view: ThinkingOrbsView?, value: Boolean) {
    view?.animated = value
  }

  companion object {
    const val NAME = "RnThinkingOrbsView"

    private fun parseColor(value: String?, fallback: Int): Int {
      if (value.isNullOrBlank()) return fallback
      var hex = value.trim()
      if (hex.startsWith("#")) hex = hex.substring(1)
      if (hex.length == 3) {
        hex = hex.map { "$it$it" }.joinToString("")
      }
      return try {
        when (hex.length) {
          6 -> Color.parseColor("#$hex")
          8 -> {
            val n = hex.toLong(16)
            val r = ((n shr 24) and 0xFF).toInt()
            val g = ((n shr 16) and 0xFF).toInt()
            val b = ((n shr 8) and 0xFF).toInt()
            val a = (n and 0xFF).toInt()
            Color.argb(a, r, g, b)
          }
          else -> fallback
        }
      } catch (_: IllegalArgumentException) {
        fallback
      } catch (_: NumberFormatException) {
        fallback
      }
    }
  }
}
