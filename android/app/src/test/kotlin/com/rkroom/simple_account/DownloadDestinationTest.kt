package com.rkroom.simple_account

import java.io.File
import java.nio.file.Files
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class DownloadDestinationTest {
    private lateinit var temporaryDirectory: File

    @Before
    fun setUp() {
        temporaryDirectory = Files.createTempDirectory("simple-account-download").toFile()
    }

    @After
    fun tearDown() {
        temporaryDirectory.deleteRecursively()
    }

    @Test
    fun `Android 9 and lower use legacy file storage`() {
        assertEquals(DownloadStorageStrategy.LEGACY_FILE, downloadStorageStrategy(24))
        assertEquals(DownloadStorageStrategy.LEGACY_FILE, downloadStorageStrategy(28))
    }

    @Test
    fun `Android 10 and higher use MediaStore`() {
        assertEquals(DownloadStorageStrategy.MEDIA_STORE, downloadStorageStrategy(29))
        assertEquals(DownloadStorageStrategy.MEDIA_STORE, downloadStorageStrategy(35))
    }

    @Test
    fun `legacy destination creates Downloads directory and writes content`() {
        val downloadDirectory = File(temporaryDirectory, "Downloads")
        val destination =
                createLegacyDownloadDestination(downloadDirectory, "bill_rules.json")

        assertNotNull(destination)
        destination!!.outputStream.use { stream ->
            stream.write("{\"schemaVersion\":1}".toByteArray())
        }

        val exportedFile = File(downloadDirectory, "bill_rules.json")
        assertTrue(exportedFile.isFile)
        assertEquals("{\"schemaVersion\":1}", exportedFile.readText())
        assertEquals(exportedFile.absolutePath, destination.displayPath)
    }

    @Test
    fun `legacy destination strips directory components from file name`() {
        val downloadDirectory = File(temporaryDirectory, "Downloads")
        val destination =
                createLegacyDownloadDestination(downloadDirectory, "../bill_rules.json")

        assertNotNull(destination)
        destination!!.outputStream.close()
        assertEquals(
                File(downloadDirectory, "bill_rules.json").absolutePath,
                destination.displayPath,
        )
    }
}
