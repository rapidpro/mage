package io.rapidpro.mage.core;

import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * When fetching an existing contact or create a new one
 */
public class ContactContext {

    @JsonProperty("contact_urn_id")
    private int m_contactUrnId;

    @JsonProperty("contact_id")
    private Integer m_contactId;

    @JsonProperty("channel_id")
    private Integer m_channelId;

    private boolean m_newContact = false;

    public ContactContext() {
    }

    public ContactContext(int contactUrnId, Integer contactId, Integer channelId, boolean newContact) {
        this.m_contactUrnId = contactUrnId;
        this.m_contactId = contactId;
        this.m_channelId = channelId;
        this.m_newContact = newContact;
    }

    public int getContactUrnId() {
        return m_contactUrnId;
    }

    public Integer getContactId() {
        return m_contactId;
    }

    public void setContactId(Integer contactId) {
        this.m_contactId = contactId;
    }

    public Integer getChannelId() {
        return m_channelId;
    }

    public void setChannelId(Integer channelId) {
        this.m_channelId = channelId;
    }

    public boolean isNewContact() {
        return m_newContact;
    }

    public void setNewContact(boolean newContact) {
        m_newContact = newContact;
    }
}