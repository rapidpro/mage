package io.rapidpro.mage.api;

import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * Returned from all message handler calls
 */
public class MessageEvent {

    public enum Result {
        CREATED,
        UPDATED,
        UNCHANGED,
        ERROR
    }

    @JsonProperty("message_id")
    private Integer m_messageId;

    @JsonProperty("result")
    private Result m_result;

    @JsonProperty("description")
    private String m_description;

    public MessageEvent() {
    }

    public MessageEvent(Integer messageId, Result result, String description) {
        m_messageId = messageId;
        m_result = result;
        m_description = description;
    }

    public Integer getMessageId() {
        return m_messageId;
    }

    public Result getResult() {
        return m_result;
    }

    public String getDescription() {
        return m_description;
    }
}