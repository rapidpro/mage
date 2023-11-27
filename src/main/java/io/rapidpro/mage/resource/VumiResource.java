package io.rapidpro.mage.resource;

import com.codahale.metrics.annotation.Timed;
import com.fasterxml.jackson.databind.node.ObjectNode;
import io.rapidpro.mage.core.CallbackContext;
import io.rapidpro.mage.core.ChannelType;
import io.rapidpro.mage.core.ContactUrn;
import io.rapidpro.mage.core.IncomingContext;
import io.rapidpro.mage.core.Status;
import io.rapidpro.mage.resource.exception.BadRequestException;
import io.rapidpro.mage.resource.exception.UnknownActionException;
import io.rapidpro.mage.service.MessageService;
import io.rapidpro.mage.service.ServiceManager;
import io.rapidpro.mage.util.JsonUtils;
import org.apache.commons.lang3.StringUtils;

import javax.ws.rs.Consumes;
import javax.ws.rs.POST;
import javax.ws.rs.Path;
import javax.ws.rs.PathParam;
import javax.ws.rs.core.MediaType;
import javax.ws.rs.core.Response;
import java.sql.Timestamp;
import java.util.Date;

@Path("/vumi")
public class VumiResource extends BaseResource {

    public VumiResource(ServiceManager services) {
        super(services);
    }

    @Timed
    @POST
    @Path("/{action}/{uuid}")
    @Consumes(MediaType.APPLICATION_JSON)
    public Response post(@PathParam("action") String action,
                         @PathParam("uuid") String channelUuid,
                         String body) {

        if (StringUtils.isEmpty(body)) {
            throw new BadRequestException("Request has no payload");
        }

        ObjectNode payload;
        try {
            payload = JsonUtils.parseObject(body);
        }
        catch (Exception e) {
            throw new BadRequestException("Request has bad payload: " + body);
        }

        switch (action) {
            case "event":
                return handleEvent(channelUuid, payload);
            case "receive":
                return handleReceive(channelUuid, payload);
            default:
                throw new UnknownActionException(action);
        }
    }

    /**
     * Handles an event callback
     */
    protected Response handleEvent(String channelUuid, ObjectNode payload) {
        MessageService messageService = getServices().getMessageService();

        String eventType = payload.path("event_type").textValue();
        String smsExternalId = payload.path("user_message_id").textValue();

        if (StringUtils.isAnyEmpty(eventType, smsExternalId)) {
            throw new BadRequestException("Message must contain: event_type and user_message_id");
        }

        CallbackContext context = messageService.getCallbackContext(channelUuid, ChannelType.VUMI, smsExternalId);

        if (context == null) {
            throw new BadRequestException("No VUMI channel found with uuid " + channelUuid + " or no message with ID " + smsExternalId);
        }

        Status newStatus = null;
        switch (eventType) {
            case "ack":
                newStatus = Status.SENT;
                break;
            case "delivery_report":
                newStatus = Status.DELIVERED;
                break;
        }

        return handleMessageUpdate(context, newStatus, new Date());
    }

    /**
     * Handles an incoming message
     */
    protected Response handleReceive(String channelUuid, ObjectNode payload) {
        MessageService messageService = getServices().getMessageService();
        IncomingContext context = messageService.getIncomingContextByChannelUuidAndType(channelUuid, ChannelType.VUMI);

        String timestamp = payload.path("timestamp").textValue();
        String from = payload.path("from_addr").textValue();
        String content = payload.path("content").textValue();
        String externalId = payload.path("message_id").textValue();

        if (StringUtils.isAnyEmpty(timestamp, from, content, externalId)) {
            throw new BadRequestException("Message must contain: timestamp, from_addr, content and message_id");
        }

        Date createdOn = Timestamp.valueOf(timestamp);

        return handleMessageCreate(context, new ContactUrn(ContactUrn.Scheme.TEL, from, null), content, createdOn, externalId);
    }
}