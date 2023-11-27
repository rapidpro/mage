package io.rapidpro.mage.resource;

import com.codahale.metrics.annotation.Timed;
import io.rapidpro.mage.core.CallbackContext;
import io.rapidpro.mage.core.ChannelType;
import io.rapidpro.mage.core.ContactUrn;
import io.rapidpro.mage.core.IncomingContext;
import io.rapidpro.mage.core.Status;
import io.rapidpro.mage.resource.exception.BadRequestException;
import io.rapidpro.mage.resource.exception.UnknownActionException;
import io.rapidpro.mage.service.MessageService;
import io.rapidpro.mage.service.ServiceManager;

import javax.ws.rs.FormParam;
import javax.ws.rs.GET;
import javax.ws.rs.POST;
import javax.ws.rs.Path;
import javax.ws.rs.PathParam;
import javax.ws.rs.QueryParam;
import javax.ws.rs.core.Response;
import java.util.Date;

@Path("/external")
public class ExternalResource extends BaseResource {

    public ExternalResource(ServiceManager services) {
        super(services);
    }

    /**
     * Supports GET or POST with all parameters in the querystring. GET handler here simply delegates to the POST handler
     */
    @Timed
    @GET
    @Path("/{action}/{uuid}")
    public Response get(@PathParam("action") String action,
                        @PathParam("uuid") String channelUuid,
                        @QueryParam("id") Integer smsId,
                        @QueryParam("from") String from,
                        @QueryParam("text") String text) {

        return post(action, channelUuid, smsId, from, text);
    }

    @Timed
    @POST
    @Path("/{action}/{uuid}")
    public Response post(@PathParam("action") String action,
                         @PathParam("uuid") String channelUuid,
                         @FormParam("id") Integer smsId,
                         @FormParam("from") String from,
                         @FormParam("text") String text) {

        action = action.toLowerCase();

        switch (action) {
            case "delivered":
            case "failed":
            case "sent":
                return handleCallback(smsId, action);
            case "received":
                return handleReceived(channelUuid, from, text);
            default:
                throw new UnknownActionException(action);
        }
    }

    /**
     * Handles a callback
     */
    protected Response handleCallback(int smsId, String action) {
        MessageService messageService = getServices().getMessageService();
        CallbackContext context = messageService.getCallbackContext(smsId);

        if (context == null) {
            throw new BadRequestException(smsId, "No such message with id");
        }

        Status newStatus = null;
        switch (action) {
            case "sent":
                newStatus = Status.SENT;
                break;
            case "delivered":
                newStatus = Status.DELIVERED;
                break;
            case "failed":
                newStatus = Status.FAILED;
                break;
        }

        return handleMessageUpdate(context, newStatus, new Date());
    }

    /**
     * Handles an incoming message
     */
    protected Response handleReceived(String channelUuid, String from, String text) {
        MessageService messageService = getServices().getMessageService();
        IncomingContext context = messageService.getIncomingContextByChannelUuidAndType(channelUuid, ChannelType.EXTERNAL);

        if (context == null) {
            throw new BadRequestException("Channel with uuid: " + channelUuid + " not found");
        }

        return handleMessageCreate(context, new ContactUrn(ContactUrn.Scheme.TEL, from, null), text, null, null);
    }
}