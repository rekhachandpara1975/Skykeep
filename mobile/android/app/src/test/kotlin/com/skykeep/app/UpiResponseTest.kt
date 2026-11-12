package com.skykeep.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class UpiResponseTest {
    @Test fun success() {
        val r = UpiResponse.parse("txnId=AXI123456&responseCode=00&Status=SUCCESS&txnRef=SK20261112ABCD1234&ApprovalRefNo=123456789012")
        assertEquals("SUCCESS", r.status)
        assertEquals("AXI123456", r.txnId)
        assertEquals("00", r.responseCode)
        assertEquals("SK20261112ABCD1234", r.txnRef)
        assertEquals("123456789012", r.approvalRefNo)
    }

    @Test fun failure() {
        val r = UpiResponse.parse("txnId=&responseCode=ZD&Status=FAILURE&txnRef=SK1")
        assertEquals("FAILURE", r.status)
        assertNull("empty values are null", r.txnId)
        assertEquals("ZD", r.responseCode)
    }

    @Test fun failedSpellingIsFailure() = assertEquals("FAILURE", UpiResponse.parse("Status=Failed").status)

    @Test fun submitted() = assertEquals("SUBMITTED", UpiResponse.parse("status=submitted&txnRef=SK1").status)

    @Test fun pending() = assertEquals("PENDING", UpiResponse.parse("Status=PENDING").status)

    @Test fun empty() {
        assertEquals("EMPTY", UpiResponse.parse(null).status)
        assertEquals("EMPTY", UpiResponse.parse("   ").status)
    }

    @Test fun malformed() {
        val r = UpiResponse.parse("garbage=&&==&noequals&%zz")
        assertEquals("UNKNOWN", r.status)
        assertNull(r.txnId)
    }

    @Test fun lowercaseKeysAndEncodedValues() {
        val r = UpiResponse.parse("txnid=abc%20123&status=success&txnref=SK2&approvalrefno=999")
        assertEquals("SUCCESS", r.status)
        assertEquals("abc 123", r.txnId)
        assertEquals("SK2", r.txnRef)
        assertEquals("999", r.approvalRefNo)
    }

    @Test fun badPercentEncodingKeptRaw() = assertEquals("a%zz", UpiResponse.parse("Status=SUCCESS&txnId=a%zz").txnId)
}
