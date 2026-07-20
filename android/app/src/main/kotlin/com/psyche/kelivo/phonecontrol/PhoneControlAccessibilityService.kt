package com.psyche.kelivo.phonecontrol

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.Rect
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class PhoneControlAccessibilityService : AccessibilityService() {
    companion object {
        @Volatile var instance: PhoneControlAccessibilityService? = null
            private set
    }

    override fun onServiceConnected() { instance = this }
    override fun onDestroy() { if (instance === this) instance = null; super.onDestroy() }
    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit
    override fun onInterrupt() = Unit

    fun uiTree(): Map<String, Any?>? = rootInActiveWindow?.let { nodeToMap(it, 0, intArrayOf(0)) }

    fun tap(text: String?, x: Int?, y: Int?): Boolean {
        val node = text?.takeIf { it.isNotBlank() }?.let { findText(rootInActiveWindow, it) }
        if (node != null) {
            var current: AccessibilityNodeInfo? = node
            while (current != null) {
                if (current.isClickable && current.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return true
                current = current.parent
            }
        }
        return if (x != null && y != null) gesture(x, y, 80) else false
    }

    fun longPress(text: String?, x: Int?, y: Int?): Boolean {
        val node = text?.takeIf { it.isNotBlank() }?.let { findText(rootInActiveWindow, it) }
        if (node != null && node.performAction(AccessibilityNodeInfo.ACTION_LONG_CLICK)) return true
        return if (x != null && y != null) gesture(x, y, 650) else false
    }

    fun input(text: String): Boolean {
        val node = rootInActiveWindow ?: return false
        val focused = findFocused(node) ?: return false
        return focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        })
    }

    fun scroll(forward: Boolean): Boolean {
        val node = findScrollable(rootInActiveWindow) ?: return false
        return node.performAction(if (forward) AccessibilityNodeInfo.ACTION_SCROLL_FORWARD else AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)
    }

    private fun gesture(x: Int, y: Int, duration: Long): Boolean {
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        val gesture = GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(path, 0, duration)).build()
        return dispatchGesture(gesture, null, null)
    }

    private fun findText(node: AccessibilityNodeInfo?, text: String): AccessibilityNodeInfo? {
        node ?: return null
        if (node.text?.toString()?.contains(text, true) == true || node.contentDescription?.toString()?.contains(text, true) == true) return node
        for (i in 0 until node.childCount) findText(node.getChild(i), text)?.let { return it }
        return null
    }

    private fun findFocused(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        node ?: return null
        if (node.isFocused && node.isEditable) return node
        for (i in 0 until node.childCount) findFocused(node.getChild(i))?.let { return it }
        return null
    }

    private fun findScrollable(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        node ?: return null
        if (node.isScrollable) return node
        for (i in 0 until node.childCount) findScrollable(node.getChild(i))?.let { return it }
        return null
    }

    private fun nodeToMap(node: AccessibilityNodeInfo, depth: Int, count: IntArray): Map<String, Any?>? {
        if (depth > 24 || count[0]++ > 300) return null
        val bounds = Rect().also(node::getBoundsInScreen)
        return mapOf(
            "text" to (node.text?.toString() ?: ""), "description" to (node.contentDescription?.toString() ?: ""),
            "viewId" to (node.viewIdResourceName ?: ""), "className" to (node.className?.toString() ?: ""),
            "clickable" to node.isClickable, "editable" to node.isEditable, "scrollable" to node.isScrollable,
            "bounds" to listOf(bounds.left, bounds.top, bounds.right, bounds.bottom),
            "children" to (0 until node.childCount).mapNotNull { node.getChild(it)?.let { child -> nodeToMap(child, depth + 1, count) } }
        )
    }
}
