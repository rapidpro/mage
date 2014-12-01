package io.rapidpro.mage.temba;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.annotation.JsonSubTypes;
import com.fasterxml.jackson.annotation.JsonTypeInfo;
import io.rapidpro.mage.temba.request.FollowNotificationRequest;
import io.rapidpro.mage.temba.request.HandleMessageRequest;
import org.hibernate.validator.constraints.NotEmpty;

/**
 * Represents a queueable Temba API request
 */
@JsonTypeInfo(
        use = JsonTypeInfo.Id.NAME,
        include = JsonTypeInfo.As.PROPERTY,
        property = "action"
)
@JsonSubTypes({
        @JsonSubTypes.Type(value = HandleMessageRequest.class, name = TembaRequest.HANDLE_MESSAGE),
        @JsonSubTypes.Type(value = FollowNotificationRequest.class, name = TembaRequest.FOLLOW_NOTIFICATION)
})
public abstract class TembaRequest {

    protected static final String HANDLE_MESSAGE = "handle_message";
    protected static final String FOLLOW_NOTIFICATION = "follow_notification";

    @NotEmpty
    @JsonProperty("action")
    protected String m_action;

    public TembaRequest(String action) {
        this.m_action = action;
    }

    public static TembaRequest newHandleMessage(int messageId, boolean newContact) {
        return new HandleMessageRequest(messageId, newContact);
    }

    public static TembaRequest newFollowNotification(int channelId, int contactUrnId, boolean newContact) {
        return new FollowNotificationRequest(channelId, contactUrnId, newContact);
    }

    public String getAction() {
        return m_action;
    }
}
