package io.rapidpro.mage.core;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.databind.node.ObjectNode;

import javax.validation.constraints.NotNull;

/**
 * Used for fetching channels
 */
public class ChannelContext {

    @JsonProperty("channel_id")
    private int m_channelId;

    @JsonProperty("channel_uuid")
    private String m_channelUuid;

    @JsonProperty("channel_address")
    private String m_channelAddress;

    @JsonProperty("channel_type")
    @NotNull
    private ChannelType m_channelType;

    @JsonProperty("channel_config")
    private ObjectNode m_channelConfig;

    @JsonProperty("channel_bod")
    private String m_channelBod;

    @JsonProperty("org_id")
    private Integer m_orgId;

    public int getChannelId() {
        return m_channelId;
    }

    public String getChannelUuid() {
        return m_channelUuid;
    }

    public String getChannelAddress() {
        return m_channelAddress;
    }

    public ChannelType getChannelType() {
        return m_channelType;
    }

    public ObjectNode getChannelConfig() {
        return m_channelConfig;
    }

    public String getChannelBod() {
        return m_channelBod;
    }

    public Integer getOrgId() {
        return m_orgId;
    }
}