package io.rapidpro.mage.api;

import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * Returned from all twitter stream management calls
 */
public class StreamEvent {

    public enum Result {
        ADDED,
        UPDATED,
        REMOVED
    }

    @JsonProperty("channel_uuid")
    private String m_channelUuid;

    @JsonProperty("result")
    private Result m_result;

    @JsonProperty("description")
    private String m_description;

    public StreamEvent() {
    }

    public StreamEvent(String channelUuid, Result result, String description) {
        m_channelUuid = channelUuid;
        m_result = result;
        m_description = description;
    }

    public String getChannelUuid() {
        return m_channelUuid;
    }

    public Result getResult() {
        return m_result;
    }

    public String getDescription() {
        return m_description;
    }
}