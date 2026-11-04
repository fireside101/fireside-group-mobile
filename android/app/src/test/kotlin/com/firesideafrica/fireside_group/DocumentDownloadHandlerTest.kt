package com.firesideafrica.fireside_group

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.ArgumentCaptor
import org.mockito.ArgumentMatchers.*
import org.mockito.Mockito.*
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.io.ByteArrayOutputStream

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [27,33], manifest = Config.NONE)
@LooperMode(LooperMode.Mode.PAUSED)
class DocumentDownloadHandlerTest {
    class Reply : MethodChannel.Result {
        var count=0; var value: Any?=null; var error: String?=null
        override fun success(result: Any?) {count++;value=result}
        override fun error(code: String, message: String?, details: Any?) {count++;error=code}
        override fun notImplemented() {count++;error="NOT_IMPLEMENTED"}
    }
    private fun call(bytes: ByteArray=byteArrayOf(1,2,3), mime: String="application/pdf") =
        MethodCall("saveDocument", mapOf("bytes" to bytes,"name" to "../../report.pdf","mime" to mime))

    @Test fun systemPickerIsOnlyFileAuthorityAndWritesExactBytesOffMain() {
        val activity=mock(Activity::class.java)
        val resolver=mock(ContentResolver::class.java)
        `when`(activity.contentResolver).thenReturn(resolver)
        val uri=Uri.parse("content://documents/chosen/report")
        val output=ByteArrayOutputStream()
        `when`(resolver.openOutputStream(uri,"w")).thenAnswer {
            assertNotSame(Looper.getMainLooper().thread,Thread.currentThread()); output
        }
        val handler=DocumentDownloadHandler(activity);val reply=Reply()
        handler.onMethodCall(call(),reply)
        val intent=ArgumentCaptor.forClass(Intent::class.java)
        verify(activity).startActivityForResult(intent.capture(),eq(DocumentDownloadHandler.REQUEST_CODE))
        assertEquals(Intent.ACTION_CREATE_DOCUMENT,intent.value.action)
        assertEquals("application/pdf",intent.value.type)
        assertTrue(intent.value.categories.contains(Intent.CATEGORY_OPENABLE))
        assertFalse(intent.value.getStringExtra(Intent.EXTRA_TITLE)!!.contains('/'))
        assertEquals(0,reply.count); verifyNoInteractions(resolver)
        handler.onActivityResult(DocumentDownloadHandler.REQUEST_CODE,Activity.RESULT_OK,Intent().setData(uri))
        val until=System.nanoTime()+5_000_000_000L
        while(reply.count==0 && System.nanoTime()<until){Thread.sleep(10);shadowOf(Looper.getMainLooper()).idle()}
        assertEquals(1,reply.count);assertEquals(true,reply.value)
        assertArrayEquals(byteArrayOf(1,2,3),output.toByteArray());handler.dispose()
    }

    @Test fun rejectsUnsupportedOversizedAndEmptyDocumentsBeforeOpeningPicker() {
        val activity=mock(Activity::class.java);val handler=DocumentDownloadHandler(activity)
        for(request in listOf(call(mime="text/html"),call(byteArrayOf()),call(ByteArray(DocumentDownloadHandler.MAX_BYTES+1)))) {
            val reply=Reply();handler.onMethodCall(request,reply)
            assertEquals("INVALID_DOCUMENT",reply.error);assertEquals(1,reply.count)
        }
        verifyNoInteractions(activity);handler.dispose()
    }

    @Test fun cancelNavigationDisposalAndNonContentUriNeverWrite() {
        for(mode in listOf("cancel","dispose","file","user-cancel")) {
            val activity=mock(Activity::class.java);val handler=DocumentDownloadHandler(activity);val reply=Reply()
            handler.onMethodCall(call(),reply)
            if(mode=="cancel")handler.onMethodCall(MethodCall("cancel",null),Reply())
            if(mode=="dispose")handler.dispose()
            handler.onActivityResult(DocumentDownloadHandler.REQUEST_CODE,
                if(mode=="user-cancel")Activity.RESULT_CANCELED else Activity.RESULT_OK,
                Intent().setData(Uri.parse(if(mode=="file")"file:///private/leak" else "content://documents/choice")))
            assertEquals(1,reply.count);assertEquals(false,reply.value)
            verify(activity,never()).contentResolver
            handler.dispose();assertEquals(1,reply.count)
        }
    }

    @Test fun overlappingPickerRequestsAreRejectedWithoutReplacingOriginal() {
        val activity=mock(Activity::class.java);val handler=DocumentDownloadHandler(activity)
        val first=Reply();val second=Reply()
        handler.onMethodCall(call(),first);handler.onMethodCall(call(),second)
        assertEquals("BUSY",second.error);assertEquals(0,first.count)
        handler.dispose();assertEquals(1,first.count)
    }
}
