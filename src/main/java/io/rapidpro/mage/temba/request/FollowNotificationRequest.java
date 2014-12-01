package io.rapidpro.mage.temba.request;

import com.fasterxml.jackson.annotation.JsonProperty;
import io.rapidpro.mage.temba.TembaRequest;

/**
 * Notifies Temba that the owning account has been followed in social media channel
 */
public class FollowNotificationRequest extends TembaRequest {

    @JsonProperty("channel_id")
    protected int m_channelId;

    @JsonProperty("contact_urn_id")
    protected int m_contactUrnId;

    @JsonProperty("new_contact")
    protected boolean m_newContact;

    public FollowNotificationRequest() {
        super(FOLLOW_NOTIFICATION);
    }

    public FollowNotificationRequest(int channelId, int contactUrnId, boolean newContact) {
        super(FOLLOW_NOTIFICATION);
        this.m_channelId = channelId;
        this.m_contactUrnId = contactUrnId;
        this.m_newContact = newContact;
    }

    public int getChannelId() {
        return m_channelId;
    }

    public int getContactUrnId() {
        return m_contactUrnId;
    }

    public boolean isNewContact() {
        return m_newContact;
    }
}
