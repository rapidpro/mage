package io.rapidpro.mage.resource;

import io.rapidpro.mage.api.MessageEvent;
import io.rapidpro.mage.dao.Table;
import io.rapidpro.mage.test.BaseResourceTest;
import io.rapidpro.mage.test.TestUtils;
import org.junit.Test;

import javax.ws.rs.client.Entity;
import javax.ws.rs.core.Form;
import javax.ws.rs.core.MediaType;
import javax.ws.rs.core.Response;
import java.util.Map;

import static org.hamcrest.Matchers.hasEntry;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.resource.ExternalResource}
 */
public class ExternalResourceTest extends BaseResourceTest<ExternalResource> {

    @Override
    protected ExternalResource getResource() {
        return new ExternalResource(getServices());
    }

    @Test
    public void get_received_shouldCreateMessageAndReturn200() throws Exception {
        Response response = resourceRequest()
                .path("received")
                .path("788B08AF-405C-43EF-9D40-7535CFA7663E")
                .queryParam("from", "+250735250222")
                .queryParam("text", "Testing")
                .request(MediaType.APPLICATION_JSON)
                .get();

        int msgId = TestUtils.assertResponse(response, 200, MessageEvent.Result.CREATED);

        Map<String, Object> sms = fetchSingleById(Table.MESSAGE, msgId);
        assertThat(sms, hasEntry("text", "Testing"));
        assertThat(sms, hasEntry("direction", "I"));
    }

    @Test
    public void post_received_shouldCreateMessageAndReturn200() throws Exception {
        Form form = new Form();
        form.param("from", "+250735250222");
        form.param("text", "Testing");

        Response response = resourceRequest()
                .path("received")
                .path("788B08AF-405C-43EF-9D40-7535CFA7663E")
                .request()
                .post(Entity.form(form));

        int msgId = TestUtils.assertResponse(response, 200, MessageEvent.Result.CREATED);

        Map<String, Object> sms = fetchSingleById(Table.MESSAGE, msgId);
        assertThat(sms, hasEntry("text", "Testing"));
        assertThat(sms, hasEntry("direction", "I"));
    }

    @Test
    public void get_received_invalidChannelUUID_shouldReturn400() throws Exception {
        Response response = resourceRequest()
                .path("received")
                .path("xxxxxxxx")
                .queryParam("from", "+250735250222")
                .queryParam("text", "Testing")
                .request(MediaType.APPLICATION_JSON)
                .get();

        TestUtils.assertResponse(response, 400, MessageEvent.Result.ERROR);
    }

    @Test
    public void get_sent_shouldUpdateMessageAndReturn200() throws Exception {
        Response response = resourceRequest()
                .path("sent")
                .path("788B08AF-405C-43EF-9D40-7535CFA7663E")
                .queryParam("id", "-81")
                .request()
                .get();

        TestUtils.assertResponse(response, 200, MessageEvent.Result.UPDATED);
    }

    @Test
    public void get_sent_statusMatchesCurrentStatus_shouldReturn200() throws Exception {
        Response response = resourceRequest()
                .path("sent")
                .path("788B08AF-405C-43EF-9D40-7535CFA7663E")
                .queryParam("id", "-82")
                .request()
                .get();

        TestUtils.assertResponse(response, 200, MessageEvent.Result.UNCHANGED);
    }

    @Test
    public void get_delivered_shouldUpdateMessageAndReturn200() throws Exception {
        Response response = resourceRequest()
                .path("delivered")
                .path("788B08AF-405C-43EF-9D40-7535CFA7663E")
                .queryParam("id", "-81")
                .request()
                .get();

        TestUtils.assertResponse(response, 200, MessageEvent.Result.UPDATED);
    }

    @Test
    public void get_failed_callback_shouldUpdateMessageAndReturn200() throws Exception {
        Response response = resourceRequest()
                .path("failed")
                .path("788B08AF-405C-43EF-9D40-7535CFA7663E")
                .queryParam("id", "-81")
                .request()
                .get();

        TestUtils.assertResponse(response, 200, MessageEvent.Result.UPDATED);
    }

    @Test
    public void get_failed_unknownMessageId_shouldReturn400() throws Exception {
        Response response = resourceRequest()
                .path("failed")
                .path("788B08AF-405C-43EF-9D40-7535CFA7663E")
                .queryParam("id", "13")
                .request()
                .get();

        TestUtils.assertResponse(response, 400, MessageEvent.Result.ERROR);
    }

    @Test
    public void get_unknownAction_shouldReturn400() throws Exception {
        Response response = resourceRequest()
                .path("xxxxx")
                .path("788B08AF-405C-43EF-9D40-7535CFA7663E")
                .queryParam("id", "-81")
                .request()
                .get();

        TestUtils.assertResponse(response, 400, MessageEvent.Result.ERROR);
    }
}