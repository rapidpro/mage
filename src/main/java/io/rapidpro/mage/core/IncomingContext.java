package io.rapidpro.mage.core;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.databind.JsonNode;

/**
 * Holds the basic data required when an incoming message is received
 */
public class IncomingContext {

    @JsonProperty("channel_id")
    private int m_channelId;

    @JsonProperty("channel_country")
    private String m_channelCountry;

    @JsonProperty("channel_type")
    private ChannelType m_channelType;

    @JsonProperty("org_id")
    private int m_orgId;

    @JsonProperty("org_config")
    private JsonNode m_orgConfig;

    public IncomingContext() {
    }

    public IncomingContext(int channelId, String channelCountry, ChannelType channelType, int orgId, JsonNode orgConfig) {
        m_channelId = channelId;
        m_channelCountry = channelCountry;
        m_channelType = channelType;
        m_orgId = orgId;
        m_orgConfig = orgConfig;
    }

    public int getChannelId() {
        return m_channelId;
    }

    public String getChannelCountry() {
        return m_channelCountry;
    }

    public ChannelType getChannelType() {
        return m_channelType;
    }

    public int getOrgId() {
        return m_orgId;
    }

    public JsonNode getOrgConfig() {
        return m_orgConfig;
    }
}