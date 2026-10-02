// Compile-only stand-in; see AndroidxCore.kt.
package androidx.core.app

import android.content.Intent
import androidx.core.util.Consumer

interface OnNewIntentProvider {
    fun addOnNewIntentListener(listener: Consumer<Intent>)
    fun removeOnNewIntentListener(listener: Consumer<Intent>)
}
