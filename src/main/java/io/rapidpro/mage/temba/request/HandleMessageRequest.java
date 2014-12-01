package io.rapidpro.mage.temba.request;

import com.fasterxml.jackson.annotation.JsonProperty;
import io.rapidpro.mage.temba.TembaRequest;

/**
 * Requests Temba to handle the given message
 */
public class HandleMessageRequest extends TembaRequest {

    @JsonProperty("message_id")
    protected int m_messageId;

    @JsonProperty("new_contact")
    protected boolean m_newContact;

    public HandleMessageRequest() {
        super(HANDLE_MESSAGE);
    }

    public HandleMessageRequest(int messageId, boolean newContact) {
        super(HANDLE_MESSAGE);
        this.m_messageId = messageId;
        this.m_newContact = newContact;
    }

    public int getMessageId() {
        return m_messageId;
    }

    public boolean isNewContact() {
        return m_newContact;
    }
}
