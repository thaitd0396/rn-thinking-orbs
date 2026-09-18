package com.rnthinkingorbs

import android.graphics.Color
import android.graphics.RuntimeShader
import android.os.Build

internal class ThinkingOrbsAgslRenderer {
  private val shader = RuntimeShader(ThinkingOrbsAgsl.source)

  fun apply(
    phase: Float,
    size: Float,
    fit: Float,
    dotScale: Float,
    contentsScale: Float,
    originX: Float,
    originY: Float,
    userRotation: FloatArray,
    accent: Int,
    ink: Int,
  ): RuntimeShader {
    shader.setFloatUniform("phase", phase)
    shader.setFloatUniform("size", size)
    shader.setFloatUniform("fit", fit)
    shader.setFloatUniform("dotScale", dotScale)
    shader.setFloatUniform("contentsScale", contentsScale)
    shader.setFloatUniform("origin", originX, originY)
    shader.setFloatUniform("userR0", userRotation[0], userRotation[1], userRotation[2])
    shader.setFloatUniform("userR1", userRotation[3], userRotation[4], userRotation[5])
    shader.setFloatUniform("userR2", userRotation[6], userRotation[7], userRotation[8])
    setColor("accent", accent)
    setColor("ink", ink)
    return shader
  }

  private fun setColor(name: String, color: Int) {
    shader.setFloatUniform(
      name,
      Color.red(color) / 255f,
      Color.green(color) / 255f,
      Color.blue(color) / 255f,
      Color.alpha(color) / 255f,
    )
  }

  companion object {
    fun createOrNull(): ThinkingOrbsAgslRenderer? {
      if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
        return null
      }
      return try {
        ThinkingOrbsAgslRenderer()
      } catch (_: Throwable) {
        null
      }
    }
  }
}
