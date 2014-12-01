package io.rapidpro.mage.core;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.databind.JsonNode;

import javax.validation.constraints.NotNull;

/**
 * Holds the basic data required when a callback message is received
 */
public class CallbackContext {

    @JsonProperty("message_id")
    private int m_messageId;

    @JsonProperty("message_status")
    @NotNull
    private Status m_messageStatus;

    @JsonProperty("org_id")
    private int m_orgId;

    @JsonProperty("org_config")
    private JsonNode m_orgConfig;

    @JsonProperty("broadcast_id")
    private Integer m_broadcastId;

    public int getMessageId() {
        return m_messageId;
    }

    public Status getMessageStatus() {
        return m_messageStatus;
    }

    public int getOrgId() {
        return m_orgId;
    }

    public JsonNode getOrgConfig() {
        return m_orgConfig;
    }

    public Integer getBroadcastId() {
        return m_broadcastId;
    }
}