package io.rapidpro.mage.resource;

import io.rapidpro.mage.MageConstants;
import io.rapidpro.mage.api.MessageEvent;
import io.rapidpro.mage.core.Status;
import io.rapidpro.mage.dao.Table;
import io.rapidpro.mage.process.MessageUpdate;
import io.rapidpro.mage.test.BaseResourceTest;
import io.rapidpro.mage.test.TestUtils;
import io.rapidpro.mage.util.JsonUtils;
import io.rapidpro.mage.util.MageUtils;
import com.sun.jersey.api.client.ClientResponse;
import com.sun.jersey.api.representation.Form;
import com.sun.jersey.core.util.MultivaluedMapImpl;
import com.twilio.sdk.TwilioUtils;
import org.junit.Test;

import javax.ws.rs.core.MultivaluedMap;
import java.util.Map;
import java.util.stream.Collectors;

import static org.hamcrest.Matchers.hasEntry;
import static org.hamcrest.Matchers.is;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.resource.TwilioResource}
 */
public class TwilioResourceTest extends BaseResourceTest<TwilioResource> {

    private static final String TEST_ACCOUNT_TOKEN = "6abb5cfa9f8b9018516cb6159088ef8d";

    @Override
    protected TwilioResource getResource() {
        return new TwilioResource(getServices());
    }

    @Test
    public void post_received_shouldReturn200() throws Exception {
        Form form = new Form();
        form.putSingle("From", "+250735250222");
        form.putSingle("To", "+250111111111"); // twilio channel for org #1
        form.putSingle("Body", "Testing");

        MultivaluedMap<String, String> query = new MultivaluedMapImpl();
        query.putSingle("action", "received");

        ClientResponse response = requestWithSignature(query, form);

        int msgId = TestUtils.assertResponse(response, 200, MessageEvent.Result.CREATED);

        Map<String, Object> sms = fetchSingleById(Table.MESSAGE, msgId);
        assertThat(sms, hasEntry("text", "Testing"));
        assertThat(sms, hasEntry("direction", "I"));

        // another message to check fetching of the incoming context from cache
        form.putSingle("From", "+250735250333");
        form.putSingle("To", "+250111111111"); // twilio channel for org #1
        form.putSingle("Body", "Testing again");
        query = new MultivaluedMapImpl();
        query.putSingle("action", "received");
        response = requestWithSignature(query, form);
        assertThat(response.getStatusInfo().getStatusCode(), is(200));
    }

    @Test
    public void post_received_badSignature_shouldReturn400() throws Exception {
        Form form = new Form();
        form.putSingle("From", "+250735250222");
        form.putSingle("To", "+250111111111"); // twilio channel for org #1
        form.putSingle("Body", "Testing");

        MultivaluedMap<String, String> query = new MultivaluedMapImpl();
        query.putSingle("action", "received");

        ClientResponse response = requestWithInvalidSignature(query, form);

        TestUtils.assertResponse(response, 400, MessageEvent.Result.ERROR);
    }

    @Test
    public void post_received_numberWithNoChannel_shouldReturn400() {
        Form form = new Form();
        form.putSingle("From", "+250735250222");
        form.putSingle("To", "+250000000000"); // no associated channel
        form.putSingle("Body", "Testing");

        MultivaluedMap<String, String> query = new MultivaluedMapImpl();
        query.putSingle("action", "received");

        ClientResponse response = requestWithSignature(query, form);

        TestUtils.assertResponse(response, 400, MessageEvent.Result.ERROR);
    }

    @Test
    public void post_received_orgHasNoConfig_shouldReturn400() throws Exception {
        executeSql("UPDATE " + Table.ORG + " SET config = NULL WHERE id = -11");

        Form form = new Form();
        form.putSingle("From", "+250735250222");
        form.putSingle("To", "+250111111111"); // twilio channel for org #1
        form.putSingle("Body", "Testing");

        MultivaluedMap<String, String> query = new MultivaluedMapImpl();
        query.putSingle("action", "received");

        ClientResponse response = requestWithSignature(query, form);

        TestUtils.assertResponse(response, 400, MessageEvent.Result.ERROR);
    }

    @Test
    public void post_callback_sent_shouldRequestMessageUpdateToSent() throws Exception {
        Form form = new Form();
        form.putSingle("SmsStatus", "sent");

        MultivaluedMap<String, String> query = new MultivaluedMapImpl();
        query.putSingle("action", "callback");
        query.putSingle("id", "-81");

        ClientResponse response = requestWithSignature(query, form);

        int msgId = TestUtils.assertResponse(response, 200, MessageEvent.Result.UPDATED);

        // check for queued update
        MessageUpdate update = JsonUtils.parse(getCache().listGetAll(MageConstants.CacheKey.MESSAGE_UPDATE_QUEUE).get(0), MessageUpdate.class);
        assertThat(update.getMessageId(), is(msgId));
        assertThat(update.getStatus(), is(Status.SENT));
    }

    @Test
    public void post_callback_failed_shouldRequestMessageUpdateToFailed() throws Exception {
        Form form = new Form();
        form.putSingle("SmsStatus", "failed");

        MultivaluedMap<String, String> query = new MultivaluedMapImpl();
        query.putSingle("action", "callback");
        query.putSingle("id", "-81");

        ClientResponse response = requestWithSignature(query, form);

        int msgId = TestUtils.assertResponse(response, 200, MessageEvent.Result.UPDATED);

        // check for queued update
        MessageUpdate update = JsonUtils.parse(getCache().listGetAll(MageConstants.CacheKey.MESSAGE_UPDATE_QUEUE).get(0), MessageUpdate.class);
        assertThat(update.getMessageId(), is(msgId));
        assertThat(update.getStatus(), is(Status.FAILED));
    }

    @Test
    public void post_callback_badSignature_shouldReturn400() throws Exception {
        Form form = new Form();
        form.putSingle("SmsStatus", "sent");

        MultivaluedMap<String, String> query = new MultivaluedMapImpl();
        query.putSingle("action", "callback");
        query.putSingle("id", "-81");

        ClientResponse response = requestWithInvalidSignature(query, form);

        TestUtils.assertResponse(response, 400, MessageEvent.Result.ERROR);

        // check no queued update
        assertThat(getCache().listLength(MageConstants.CacheKey.MESSAGE_UPDATE_QUEUE), is(0L));
    }

    @Test
    public void post_callback_nonExistentMessage_shouldReturn400() throws Exception {
        Form form = new Form();
        form.putSingle("SmsStatus", "sent");

        MultivaluedMap<String, String> query = new MultivaluedMapImpl();
        query.putSingle("action", "callback");
        query.putSingle("id", "13");

        ClientResponse response = requestWithSignature(query, form);

        TestUtils.assertResponse(response, 400, MessageEvent.Result.ERROR);
    }

    @Test
    public void post_callback_orgHasNoConfig_shouldReturn400() throws Exception {
        executeSql("UPDATE " + Table.ORG + " SET config = NULL WHERE id = -11");

        Form form = new Form();
        form.putSingle("SmsStatus", "failed");

        MultivaluedMap<String, String> query = new MultivaluedMapImpl();
        query.putSingle("action", "callback");
        query.putSingle("id", "-81");

        ClientResponse response = requestWithSignature(query, form);

        TestUtils.assertResponse(response, 400, MessageEvent.Result.ERROR);
    }

    @Test
    public void post_callback_orgHasNoTwilioConfig_shouldReturn400() throws Exception {
        executeSql("UPDATE " + Table.ORG + " SET config = '{\"foo\":\"bar\"}' WHERE id = -11");

        Form form = new Form();
        form.putSingle("SmsStatus", "failed");

        MultivaluedMap<String, String> query = new MultivaluedMapImpl();
        query.putSingle("action", "callback");
        query.putSingle("id", "-81");

        ClientResponse response = requestWithSignature(query, form);

        TestUtils.assertResponse(response, 400, MessageEvent.Result.ERROR);
    }

    @Test
    public void post_unknownaction_shouldReturn400() throws Exception {
        MultivaluedMap<String, String> query = new MultivaluedMapImpl();
        query.putSingle("action", "xxxx");

        ClientResponse response = requestWithSignature(query, new Form());

        TestUtils.assertResponse(response, 400, MessageEvent.Result.ERROR);
    }

    /**
     * Makes a request with a valid signature
     * @param query the query parameters
     * @param form the form parameters
     * @return the response
     */
    protected ClientResponse requestWithSignature(MultivaluedMap<String, String> query, Form form) {
        String url = getResourcePath() + "?" + query.keySet().stream().map(k -> k + "=" + query.getFirst(k)).collect(Collectors.joining("&"));

        TwilioUtils utils = new TwilioUtils(TEST_ACCOUNT_TOKEN);
        String signature = utils.getValidationSignature(url, MageUtils.simplifyMultivaluedMap(form));

        return resourceRequest()
                .queryParams(query)
                .header("X-Twilio-Signature", signature)
                .post(ClientResponse.class, form);
    }

    /**
     * Makes a request with an invalid signature
     * @param query the query parameters
     * @param form the form parameters
     * @return the response
     */
    protected ClientResponse requestWithInvalidSignature(MultivaluedMap<String, String> query, Form form) {
        return resourceRequest()
                .queryParams(query)
                .header("X-Twilio-Signature", "xxxxxx")
                .post(ClientResponse.class, form);
    }
}