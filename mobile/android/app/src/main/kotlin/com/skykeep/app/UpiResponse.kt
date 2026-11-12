package com.skykeep.app

import java.net.URLDecoder

/**
 * Parses the string a UPI app returns, e.g.
 * `txnId=AXI123&responseCode=00&Status=SUCCESS&txnRef=SK20261112ABCD1234&ApprovalRefNo=123456789012`.
 * Keys are matched case-insensitively. The result is only a hint for the UI — the server
 * stores the raw string, re-parses it and decides; premium is never activated from the phone.
 */
data class UpiResponse(
    val status: String,          // SUCCESS | FAILURE | SUBMITTED | PENDING | UNKNOWN | EMPTY
    val txnId: String? = null,
    val responseCode: String? = null,
    val txnRef: String? = null,
    val approvalRefNo: String? = null,
) {
    fun toMap(): Map<String, String?> = mapOf(
        "status" to status, "txnId" to txnId, "responseCode" to responseCode,
        "txnRef" to txnRef, "approvalRefNo" to approvalRefNo,
    )

    companion object {
        fun parse(raw: String?): UpiResponse {
            if (raw.isNullOrBlank()) return UpiResponse("EMPTY")
            val map = HashMap<String, String>()
            for (part in raw.split('&', '?')) {
                val i = part.indexOf('=')
                if (i <= 0) continue
                val key = part.substring(0, i).trim().lowercase()
                val value = try {
                    URLDecoder.decode(part.substring(i + 1).trim(), "UTF-8")
                } catch (e: IllegalArgumentException) {
                    part.substring(i + 1).trim()
                }
                if (value.isNotEmpty()) map[key] = value
            }
            val status = when (map["status"]?.uppercase()) {
                "SUCCESS" -> "SUCCESS"
                "FAILURE", "FAILED" -> "FAILURE"
                "SUBMITTED" -> "SUBMITTED"
                "PENDING" -> "PENDING"
                else -> "UNKNOWN"
            }
            return UpiResponse(status, map["txnid"], map["responsecode"], map["txnref"], map["approvalrefno"])
        }
    }
}
