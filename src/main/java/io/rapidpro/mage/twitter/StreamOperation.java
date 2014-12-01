package io.rapidpro.mage.twitter;

import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * A queuable stream management operation
 */
public class StreamOperation {

    public enum Action {
        ADD,
        UPDATE,
        REMOVE
    }

    @JsonProperty("channel_uuid")
    private String m_channelUuid;

    @JsonProperty("result")
    private Action m_action;

    public StreamOperation() {
    }

    public StreamOperation(String channelUuid, Action action) {
        m_channelUuid = channelUuid;
        m_action = action;
    }

    public String getChannelUuid() {
        return m_channelUuid;
    }

    public Action getAction() {
        return m_action;
    }
}