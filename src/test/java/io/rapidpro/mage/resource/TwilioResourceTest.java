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
import com.twilio.sdk.TwilioUtils;
import org.junit.Test;

import javax.ws.rs.client.Entity;
import javax.ws.rs.client.WebTarget;
import javax.ws.rs.core.Form;
import javax.ws.rs.core.Response;
import java.util.LinkedHashMap;
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
        form.param("From", "+250735250222");
        form.param("To", "+250111111111"); // twilio channel for org #1
        form.param("Body", "Testing");

        Map<String, String> query = new LinkedHashMap<>();
        query.put("action", "received");

        Response response = requestWithSignature(query, form);

        int msgId = TestUtils.assertResponse(response, 200, MessageEvent.Result.CREATED);

        Map<String, Object> sms = fetchSingleById(Table.MESSAGE, msgId);
        assertThat(sms, hasEntry("text", "Testing"));
        assertThat(sms, hasEntry("direction", "I"));

        // another message to check fetching of the incoming context from cache
        form.param("From", "+250735250333");
        form.param("To", "+250111111111"); // twilio channel for org #1
        form.param("Body", "Testing again");
        query = new LinkedHashMap<>();
        query.put("action", "received");
        response = requestWithSignature(query, form);
        assertThat(response.getStatusInfo().getStatusCode(), is(200));
    }

    @Test
    public void post_received_badSignature_shouldReturn400() throws Exception {
        Form form = new Form();
        form.param("From", "+250735250222");
        form.param("To", "+250111111111"); // twilio channel for org #1
        form.param("Body", "Testing");

        Map<String, String> query = new LinkedHashMap<>();
        query.put("action", "received");

        Response response = requestWithInvalidSignature(query, form);

        TestUtils.assertResponse(response, 400, MessageEvent.Result.ERROR);
    }

    @Test
    public void post_received_numberWithNoChannel_shouldReturn400() {
        Form form = new Form();
        form.param("From", "+250735250222");
        form.param("To", "+250000000000"); // no associated channel
        form.param("Body", "Testing");

        Map<String, String> query = new LinkedHashMap<>();
        query.put("action", "received");

        Response response = requestWithSignature(query, form);

        TestUtils.assertResponse(response, 400, MessageEvent.Result.ERROR);
    }

    @Test
    public void post_received_orgHasNoConfig_shouldReturn400() throws Exception {
        executeSql("UPDATE " + Table.ORG + " SET config = NULL WHERE id = -11");

        Form form = new Form();
        form.param("From", "+250735250222");
        form.param("To", "+250111111111"); // twilio channel for org #1
        form.param("Body", "Testing");

        Map<String, String> query = new LinkedHashMap<>();
        query.put("action", "received");

        Response response = requestWithSignature(query, form);

        TestUtils.assertResponse(response, 400, MessageEvent.Result.ERROR);
    }

    @Test
    public void post_callback_sent_shouldRequestMessageUpdateToSent() throws Exception {
        Form form = new Form();
        form.param("SmsStatus", "sent");

        Map<String, String> query = new LinkedHashMap<>();
        query.put("action", "callback");
        query.put("id", "-81");

        Response response = requestWithSignature(query, form);

        int msgId = TestUtils.assertResponse(response, 200, MessageEvent.Result.UPDATED);

        // check for queued update
        MessageUpdate update = JsonUtils.parse(getCache().listGetAll(MageConstants.CacheKey.MESSAGE_UPDATE_QUEUE).get(0), MessageUpdate.class);
        assertThat(update.getMessageId(), is(msgId));
        assertThat(update.getStatus(), is(Status.SENT));
    }

    @Test
    public void post_callback_failed_shouldRequestMessageUpdateToFailed() throws Exception {
        Form form = new Form();
        form.param("SmsStatus", "failed");

        Map<String, String> query = new LinkedHashMap<>();
        query.put("action", "callback");
        query.put("id", "-81");

        Response response = requestWithSignature(query, form);

        int msgId = TestUtils.assertResponse(response, 200, MessageEvent.Result.UPDATED);

        // check for queued update
        MessageUpdate update = JsonUtils.parse(getCache().listGetAll(MageConstants.CacheKey.MESSAGE_UPDATE_QUEUE).get(0), MessageUpdate.class);
        assertThat(update.getMessageId(), is(msgId));
        assertThat(update.getStatus(), is(Status.FAILED));
    }

    @Test
    public void post_callback_badSignature_shouldReturn400() throws Exception {
        Form form = new Form();
        form.param("SmsStatus", "sent");

        Map<String, String> query = new LinkedHashMap<>();
        query.put("action", "callback");
        query.put("id", "-81");

        Response response = requestWithInvalidSignature(query, form);

        TestUtils.assertResponse(response, 400, MessageEvent.Result.ERROR);

        // check no queued update
        assertThat(getCache().listLength(MageConstants.CacheKey.MESSAGE_UPDATE_QUEUE), is(0L));
    }

    @Test
    public void post_callback_nonExistentMessage_shouldReturn400() throws Exception {
        Form form = new Form();
        form.param("SmsStatus", "sent");

        Map<String, String> query = new LinkedHashMap<>();
        query.put("action", "callback");
        query.put("id", "13");

        Response response = requestWithSignature(query, form);

        TestUtils.assertResponse(response, 400, MessageEvent.Result.ERROR);
    }

    @Test
    public void post_callback_orgHasNoConfig_shouldReturn400() throws Exception {
        executeSql("UPDATE " + Table.ORG + " SET config = NULL WHERE id = -11");

        Form form = new Form();
        form.param("SmsStatus", "failed");

        Map<String, String> query = new LinkedHashMap<>();
        query.put("action", "callback");
        query.put("id", "-81");

        Response response = requestWithSignature(query, form);

        TestUtils.assertResponse(response, 400, MessageEvent.Result.ERROR);
    }

    @Test
    public void post_callback_orgHasNoTwilioConfig_shouldReturn400() throws Exception {
        executeSql("UPDATE " + Table.ORG + " SET config = '{\"foo\":\"bar\"}' WHERE id = -11");

        Form form = new Form();
        form.param("SmsStatus", "failed");

        Map<String, String> query = new LinkedHashMap<>();
        query.put("action", "callback");
        query.put("id", "-81");

        Response response = requestWithSignature(query, form);

        TestUtils.assertResponse(response, 400, MessageEvent.Result.ERROR);
    }

    @Test
    public void post_unknownaction_shouldReturn400() throws Exception {
        Map<String, String> query = new LinkedHashMap<>();
        query.put("action", "xxxx");

        Response response = requestWithSignature(query, new Form());

        TestUtils.assertResponse(response, 400, MessageEvent.Result.ERROR);
    }

    /**
     * Makes a request with a valid signature
     * @param query the query parameters
     * @param form the form parameters
     * @return the response
     */
    protected Response requestWithSignature(Map<String, String> query, Form form) {
        String url = getResourcePath() + "?" + query.keySet().stream().map(k -> k + "=" + query.get(k)).collect(Collectors.joining("&"));

        TwilioUtils utils = new TwilioUtils(TEST_ACCOUNT_TOKEN);
        String signature = utils.getValidationSignature(url, MageUtils.simplifyMultivaluedMap(form.asMap()));

        WebTarget target = resourceRequest();

        for (Map.Entry<String, String> param : query.entrySet()) {
            target = target.queryParam(param.getKey(), param.getValue());
        }

        return target.request().header("X-Twilio-Signature", signature).post(Entity.form(form));
    }

    /**
     * Makes a request with an invalid signature
     * @param query the query parameters
     * @param form the form parameters
     * @return the response
     */
    protected Response requestWithInvalidSignature(Map<String, String> query, Form form) {
        WebTarget target = resourceRequest();

        for (Map.Entry<String, String> param : query.entrySet()) {
            target = target.queryParam(param.getKey(), param.getValue());
        }

        return target.request().header("X-Twilio-Signature", "xxxxxxx").post(Entity.form(form));
    }
}