/*
 * Copyright (C) 2023-2025 Yubico.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *       http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.yubico.authenticator.device

import com.yubico.yubikit.core.Transport
import com.yubico.yubikit.core.Version
import com.yubico.yubikit.management.DeviceInfo
import com.yubico.yubikit.management.FormFactor
import com.yubico.yubikit.management.VersionQualifier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.`when`

class InfoTest {
    @Test
    fun construction() {
        val deviceInfo = deviceInfoMock

        `when`(deviceInfo.serialNumber).thenReturn(1234)
        `when`(deviceInfo.version).thenReturn(Version(1, 2, 3))
        `when`(deviceInfo.formFactor).thenReturn(FormFactor.USB_C_KEYCHAIN)
        `when`(deviceInfo.isLocked).thenReturn(true)
        `when`(deviceInfo.isSky).thenReturn(false)
        `when`(deviceInfo.isFips).thenReturn(true)
        `when`(deviceInfo.hasTransport(Transport.NFC)).thenReturn(true)
        `when`(deviceInfo.hasTransport(Transport.USB)).thenReturn(true)
        `when`(deviceInfo.getSupportedCapabilities(Transport.USB)).thenReturn(456)
        `when`(deviceInfo.getSupportedCapabilities(Transport.NFC)).thenReturn(789)

        val info = Info(name = "TestD", isNfc = true, usbPid = null, deviceInfo = deviceInfo)

        assertEquals(Config(deviceConfigMock), info.config)
        assertEquals(1234u, info.serialNumber)
        assertEquals(Version(1, 2, 3).major, info.version.major)
        assertEquals(Version(1, 2, 3).minor, info.version.minor)
        assertEquals(Version(1, 2, 3).micro, info.version.micro)
        assertEquals(FormFactor.USB_C_KEYCHAIN.value, info.formFactor)
        assertTrue(info.isLocked)
        assertFalse(info.isSky)
        assertTrue(info.isFips)
        assertEquals(456, info.supportedCapabilities.usb)
        assertEquals(789, info.supportedCapabilities.nfc)
        assertEquals("TestD", info.name)
        assertTrue(info.isNfc)
        assertNull(info.usbPid)
        assertNotNull(info.versionQualifier)
        assertEquals(0.toByte(), info.versionQualifier.version.major)
        assertEquals(0.toByte(), info.versionQualifier.version.minor)
        assertEquals(0.toByte(), info.versionQualifier.version.micro)
        assertEquals(2u, info.versionQualifier.type.toUInt())
        assertEquals(0u, info.versionQualifier.iteration)
    }

    private fun DeviceInfo.withTransport(transport: Transport, capabilities: Int = 0): DeviceInfo {
        `when`(hasTransport(transport)).thenReturn(true)
        `when`(getSupportedCapabilities(transport)).thenReturn(capabilities)
        return this
    }

    private fun DeviceInfo.withoutTransport(transport: Transport): DeviceInfo {
        `when`(hasTransport(transport)).thenReturn(false)
        return this
    }

    private fun DeviceInfo.withVersionQualifier(
        version: Version,
        type: VersionQualifier.Type,
        iteration: Int
    ): DeviceInfo {
        `when`(versionQualifier).thenReturn(
            VersionQualifier(
                version,
                type,
                iteration
            )
        )
        return this
    }

    @Test
    fun withNfcCapabilities() {
        val deviceInfo = deviceInfoMock.withTransport(Transport.NFC, 123)
        val info = Info(name = "TestD", isNfc = false, usbPid = null, deviceInfo = deviceInfo)
        assertEquals(123, info.supportedCapabilities.nfc)
    }

    @Test
    fun withoutNfcCapabilities() {
        val deviceInfo = deviceInfoMock.withoutTransport(Transport.NFC)
        val info = Info(name = "TestD", isNfc = false, usbPid = null, deviceInfo = deviceInfo)
        assertNull(info.supportedCapabilities.nfc)
    }

    @Test
    fun withUsbCapabilities() {
        val deviceInfo = deviceInfoMock.withTransport(Transport.USB, 454)
        val info = Info(name = "TestD", isNfc = false, usbPid = null, deviceInfo = deviceInfo)
        assertEquals(454, info.supportedCapabilities.usb)
    }

    @Test
    fun withoutUsbCapabilities() {
        val deviceInfo = deviceInfoMock.withoutTransport(Transport.USB)
        val info = Info(name = "TestD", isNfc = false, usbPid = null, deviceInfo = deviceInfo)
        assertNull(info.supportedCapabilities.usb)
    }

    @Test
    fun testVersionQualifier() {
        var deviceInfo = deviceInfoMock.withVersionQualifier(
            Version(5, 7, 3),
            VersionQualifier.Type.BETA,
            5
        )
        var info = Info(name = "TestD", isNfc = false, usbPid = null, deviceInfo = deviceInfo)
        assertEquals(5.toByte(), info.versionQualifier.version.major)
        assertEquals(7.toByte(), info.versionQualifier.version.minor)
        assertEquals(3.toByte(), info.versionQualifier.version.micro)

        assertEquals(5u, info.versionQualifier.iteration)

        assertEquals(VersionQualifier.Type.BETA.ordinal.toUByte(), info.versionQualifier.type)

        deviceInfo = deviceInfoMock.withVersionQualifier(
            Version(5, 7, 3),
            VersionQualifier.Type.ALPHA,
            5
        )
        info = Info(name = "TestD", isNfc = false, usbPid = null, deviceInfo = deviceInfo)
        assertEquals(VersionQualifier.Type.ALPHA.ordinal.toUByte(), info.versionQualifier.type)

        deviceInfo = deviceInfoMock.withVersionQualifier(
            Version(5, 7, 3),
            VersionQualifier.Type.FINAL,
            5
        )
        info = Info(name = "TestD", isNfc = false, usbPid = null, deviceInfo = deviceInfo)
        assertEquals(VersionQualifier.Type.FINAL.ordinal.toUByte(), info.versionQualifier.type)

    }
}
