package io.rapidpro.mage.resource;

import io.rapidpro.mage.api.MessageEvent;
import io.rapidpro.mage.core.CallbackContext;
import io.rapidpro.mage.core.ContactUrn;
import io.rapidpro.mage.core.IncomingContext;
import io.rapidpro.mage.core.Status;
import io.rapidpro.mage.service.MessageService;
import io.rapidpro.mage.service.ServiceManager;

import javax.ws.rs.core.MediaType;
import javax.ws.rs.core.Response;
import java.util.Date;

/**
 * Abstract base class for all resources
 */
public abstract class BaseResource {

    private final ServiceManager m_services;

    public BaseResource(ServiceManager services) {
        m_services = services;
    }

    public ServiceManager getServices() {
        return m_services;
    }

    /**
     * Default handling of a message creation
     * @param context the callback context
     * @return the response
     */
    protected Response handleMessageCreate(IncomingContext context, ContactUrn from, String text, Date createdOn, String externalId) {
        MessageService messageService = getServices().getMessageService();
        int messageId = messageService.createIncoming(context, from, text, createdOn, externalId, null);

        MessageEvent messageEvent = new MessageEvent(messageId, MessageEvent.Result.CREATED, null);
        return Response.status(200).type(MediaType.APPLICATION_JSON).entity(messageEvent).build();
    }

    /**
     * Default handling of a message status change
     * @param context the callback context
     * @param newStatus the new status (null means we don't recognise the requested status)
     * @param changedOn the date (usually now, the channel might explicitly provide this)
     * @return the response
     */
    protected Response handleMessageUpdate(CallbackContext context, Status newStatus, Date changedOn) {
        MessageService messageService = getServices().getMessageService();
        MessageEvent.Result result;

        if (newStatus != null && !newStatus.equals(context.getMessageStatus())) {
            messageService.requestMessageStatusUpdate(context.getMessageId(), newStatus, changedOn, context.getBroadcastId());
            result = MessageEvent.Result.UPDATED;
        }
        else {
            result = MessageEvent.Result.UNCHANGED;
        }

        MessageEvent messageEvent = new MessageEvent(context.getMessageId(), result, null);

        return Response.status(200).type(MediaType.APPLICATION_JSON).entity(messageEvent).build();
    }
}