package io.rapidpro.mage.resource;

import com.codahale.metrics.annotation.Timed;
import com.fasterxml.jackson.databind.JsonNode;
import io.rapidpro.mage.core.CallbackContext;
import io.rapidpro.mage.core.ChannelType;
import io.rapidpro.mage.core.ContactUrn;
import io.rapidpro.mage.core.IncomingContext;
import io.rapidpro.mage.core.Status;
import io.rapidpro.mage.resource.exception.BadRequestException;
import io.rapidpro.mage.resource.exception.UnknownActionException;
import io.rapidpro.mage.service.MessageService;
import io.rapidpro.mage.service.ServiceManager;
import io.rapidpro.mage.util.MageUtils;
import com.twilio.sdk.TwilioRestClient;
import com.twilio.sdk.TwilioUtils;

import javax.ws.rs.DefaultValue;
import javax.ws.rs.FormParam;
import javax.ws.rs.HeaderParam;
import javax.ws.rs.POST;
import javax.ws.rs.Path;
import javax.ws.rs.QueryParam;
import javax.ws.rs.core.Context;
import javax.ws.rs.core.MultivaluedMap;
import javax.ws.rs.core.Response;
import javax.ws.rs.core.UriInfo;
import java.net.URI;
import java.util.Date;

@Path("/twilio")
public class TwilioResource extends BaseResource {

    private static final String ACTION_CALLBACK = "callback";
    private static final String ACTION_RECEIVED = "received";

    private static final String TWILIO_ACCOUNT_SID = "ACCOUNT_SID";
    private static final String TWILIO_ACCOUNT_TOKEN = "ACCOUNT_TOKEN";

    private static final String HEADER_TWILIO_SIGNATURE = "X-Twilio-Signature";

    public TwilioResource(ServiceManager services) {
        super(services);
    }

    @Timed
    @POST
    public Response post(@DefaultValue(ACTION_RECEIVED) @QueryParam("action") String action,
                         @QueryParam("id") Integer smsId,
                         @DefaultValue("") @FormParam("SmsStatus") String smsStatus,
                         @FormParam("To") String to,
                         @FormParam("From") String from,
                         @FormParam("Body") String body,
                         @HeaderParam(HEADER_TWILIO_SIGNATURE) String signature,
                         @Context UriInfo uriInfo,
                         MultivaluedMap<String, String> params) {

        URI url = uriInfo.getRequestUri();

        switch (action) {
            case ACTION_CALLBACK:
                return handleCallback(smsId, smsStatus, signature, url, params);
            case ACTION_RECEIVED:
                return handleReceived(to, from, body, signature, url, params);
            default:
                throw new UnknownActionException(action);
        }
    }

    /**
     * Handles a callback
     */
    protected Response handleCallback(int smsId, String status, String signature, URI url, MultivaluedMap<String, String> params) {
        MessageService messageService = getServices().getMessageService();
        CallbackContext context = messageService.getCallbackContext(smsId);

        if (context == null) {
            throw new BadRequestException(smsId, "No such message with id");
        }

        JsonNode orgConfig = context.getOrgConfig();
        if (orgConfig == null) {
            throw new BadRequestException(smsId, "No org config found for message");
        }

        validateRequest(orgConfig, signature, url, params);

        Status newStatus = null;

        // queued, sending, sent, or failed
        switch (status) {
            case "sent":
                newStatus = Status.SENT;
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
    protected Response handleReceived(String to, String from, String text, String signature, URI url, MultivaluedMap<String, String> params) {
        MessageService messageService = getServices().getMessageService();
        IncomingContext context = messageService.getIncomingContextByChannelAddressAndType(ChannelType.TWILIO, to);

        if (context == null) {
            throw new BadRequestException("No active channel and org found for number: " + to);
        }

        JsonNode orgConfig = context.getOrgConfig();
        if (orgConfig == null) {
            throw new BadRequestException("No org config found for number: " + to);
        }

        validateRequest(orgConfig, signature, url, params);

        return handleMessageCreate(context, new ContactUrn(ContactUrn.Scheme.TEL, from, null), text, null, null);
    }

    /**
     * Validates the request using Twilio's client library to compare the request params and URL with the signature
     * @throws BadRequestException if request is invalid
     */
    protected void validateRequest(JsonNode orgConfig, String signature, URI url, MultivaluedMap<String, String> params) {
        TwilioRestClient client = getTwilioClient(orgConfig);

        if (client == null) {
            throw new BadRequestException("No Twilio client config for org");
        }

        TwilioUtils utils = new TwilioUtils(client.getAccount().getAuthToken());
        if (!utils.validateRequest(signature, url.toString(), MageUtils.simplifyMultivaluedMap(params))) {
            throw new BadRequestException("Invalid request signature");
        }
    }

    /**
     * Gets a Twilio client instance for this org if the org's config contains the required fields
     * @return the client
     */
    public TwilioRestClient getTwilioClient(JsonNode orgConfig) {
        String accountSid = orgConfig.path(TWILIO_ACCOUNT_SID).textValue();
        String accountToken = orgConfig.path(TWILIO_ACCOUNT_TOKEN).textValue();

        if (accountSid != null && accountToken != null) {
            return new TwilioRestClient(accountSid, accountToken);
        }
        return null;
    }
}