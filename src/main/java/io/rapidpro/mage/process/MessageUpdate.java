package io.rapidpro.mage.process;

import com.fasterxml.jackson.annotation.JsonProperty;
import io.rapidpro.mage.core.Status;

import javax.validation.constraints.NotNull;
import java.util.Date;

/**
 * Describes a update of a message's status. Instances of this class will be serialized to JSON and queued for
 * processing by a background task
 */
public class MessageUpdate {

    @JsonProperty("message_id")
    private int m_messageId;

    @JsonProperty("status")
    @NotNull
    private Status m_status;

    @JsonProperty("date")
    private Date m_date;

    @JsonProperty("broadcast_id")
    private Integer m_broadcastId;

    public MessageUpdate() {
    }

    public MessageUpdate(int messageId, Status status, Date date, Integer broadcastId) {
        m_messageId = messageId;
        m_status = status;
        m_date = date;
        m_broadcastId = broadcastId;
    }

    public int getMessageId() {
        return m_messageId;
    }

    public Status getStatus() {
        return m_status;
    }

    public Date getDate() {
        return m_date;
    }

    public Integer getBroadcastId() {
        return m_broadcastId;
    }

    /**
     * Equality is based on message and status alone
     */
    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;

        MessageUpdate that = (MessageUpdate) o;

        if (m_messageId != that.m_messageId) return false;
        if (m_status != that.m_status) return false;

        return true;
    }

    /**
     * @see MessageUpdate#equals(Object)
     */
    @Override
    public int hashCode() {
        int result = m_messageId;
        result = 31 * result + m_status.hashCode();
        return result;
    }
}