package io.rapidpro.mage.resource;

import com.fasterxml.jackson.databind.node.ObjectNode;
import io.rapidpro.mage.api.MessageEvent;
import io.rapidpro.mage.dao.Table;
import io.rapidpro.mage.test.BaseResourceTest;
import io.rapidpro.mage.test.TestUtils;
import io.rapidpro.mage.util.JsonUtils;
import org.junit.Test;

import javax.ws.rs.client.Entity;
import javax.ws.rs.core.MediaType;
import javax.ws.rs.core.Response;
import java.util.Map;

import static org.hamcrest.Matchers.hasEntry;
import static org.hamcrest.Matchers.is;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.resource.VumiResource}
 */
public class VumiResourceTest extends BaseResourceTest<VumiResource> {

    @Override
    protected VumiResource getResource() {
        return new VumiResource(getServices());
    }

    @Test
    public void get_receive_shouldReturn405() {
        Response response = resourceRequest()
                .path("receive")
                .path("C4C92278-586E-4B38-93C4-D413FEF43FA2")
                .request(MediaType.APPLICATION_JSON)
                .get();

        assertThat(response.getStatusInfo().getStatusCode(), is(405));
    }

    @Test
    public void post_receive_shouldReturn200() throws Exception {
        ObjectNode payload = JsonUtils.object()
                .put("timestamp", "2014-04-18 03:54:20.570618")
                .put("from_addr", "+250783835665") //
                .put("content", "Testing")
                .put("message_id", "SMS84");

        Response response = resourceRequest()
                .path("receive")
                .path("C4C92278-586E-4B38-93C4-D413FEF43FA2")
                .request(MediaType.APPLICATION_JSON)
                .post(Entity.json(payload));

        int msgId = TestUtils.assertResponse(response, 200, MessageEvent.Result.CREATED);

        // check message was added to database
        Map<String, Object> msg = fetchSingleById(Table.MESSAGE, msgId);
        assertThat(msg, hasEntry("text", "Testing"));
        assertThat(msg, hasEntry("contact_id", -52));
        assertThat(msg, hasEntry("direction", "I"));
    }

    @Test
    public void post_receive_badPayload_shouldReturn400() throws Exception {
        ObjectNode payload = JsonUtils.object().put("foo", "bar");

        Response response = resourceRequest()
                .path("receive")
                .path("C4C92278-586E-4B38-93C4-D413FEF43FA2")
                .request(MediaType.APPLICATION_JSON)
                .post(Entity.json(payload));

        TestUtils.assertResponse(response, 400, MessageEvent.Result.ERROR);
    }

    @Test
    public void post_event_ack_shouldUpdateMessageAndReturn200() throws Exception {
        ObjectNode payload = JsonUtils.object()
                .put("event_type", "ack")
                .put("user_message_id", "SMS84");

        Response response = resourceRequest()
                .path("event")
                .path("C4C92278-586E-4B38-93C4-D413FEF43FA2")
                .request(MediaType.APPLICATION_JSON)
                .post(Entity.json(payload));

        TestUtils.assertResponse(response, 200, MessageEvent.Result.UPDATED);
    }

    @Test
    public void post_event_deliveryreport_shouldUpdateMessageReturn200() throws Exception {
        ObjectNode payload = JsonUtils.object()
                .put("event_type", "delivery_report")
                .put("user_message_id", "SMS84");

        Response response = resourceRequest()
                .path("event")
                .path("C4C92278-586E-4B38-93C4-D413FEF43FA2")
                .request(MediaType.APPLICATION_JSON)
                .post(Entity.json(payload));

        TestUtils.assertResponse(response, 200, MessageEvent.Result.UPDATED);
    }

    @Test
    public void post_event_ack_invalidPayload_shouldReturn400() throws Exception {
        ObjectNode payload = JsonUtils.object().put("foo", "bar");

        Response response = resourceRequest()
                .path("event")
                .path("C4C92278-586E-4B38-93C4-D413FEF43FA2")
                .request(MediaType.APPLICATION_JSON)
                .post(Entity.json(payload));

        TestUtils.assertResponse(response, 400, MessageEvent.Result.ERROR);
    }

    @Test
    public void post_event_ack_invalidChannelUuid_shouldReturn400() throws Exception {
        ObjectNode payload = JsonUtils.object()
                .put("event_type", "ack")
                .put("user_message_id", "SMS84");

        Response response = resourceRequest()
                .path("event")
                .path("xxxxxxx") // not a valid channel UUID
                .request(MediaType.APPLICATION_JSON)
                .post(Entity.json(payload));

        TestUtils.assertResponse(response, 400, MessageEvent.Result.ERROR);
    }

    @Test
    public void post_unknownaction_shouldReturn400() throws Exception {
        Response response = resourceRequest()
                .path("xxxxxxx")
                .path("C4C92278-586E-4B38-93C4-D413FEF43FA2")
                .request(MediaType.APPLICATION_JSON)
                .post(Entity.json(JsonUtils.object()));

        TestUtils.assertResponse(response, 400, MessageEvent.Result.ERROR);
    }
}