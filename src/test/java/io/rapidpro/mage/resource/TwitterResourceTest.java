package io.rapidpro.mage.resource;

import io.rapidpro.mage.api.StreamEvent;
import io.rapidpro.mage.test.BaseTwitterTest;
import io.rapidpro.mage.util.JsonUtils;
import io.dropwizard.testing.junit.ResourceTestRule;
import org.junit.Rule;
import org.junit.Test;

import javax.ws.rs.client.Entity;
import javax.ws.rs.client.Invocation;
import javax.ws.rs.client.WebTarget;
import javax.ws.rs.core.Form;
import javax.ws.rs.core.Response;

import static org.hamcrest.Matchers.is;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.resource.TwitterResource}
 */
public class TwitterResourceTest extends BaseTwitterTest {

    private static final String TEST_AUTH_TOKEN = "1234567890abcdef";

    private final TwitterResource m_resource = new TwitterResource(getTwitter(), getServices(), TEST_AUTH_TOKEN);

    @Rule
    public final ResourceTestRule m_resourceRule = ResourceTestRule.builder().addResource(m_resource).build();

    public TwitterResourceTest() {
        JsonUtils.disableMapperAutoDetection(m_resourceRule.getObjectMapper());
    }

    @Test
    public void post_shouldReturn401ForIncorrectOrMissingAuthToken() throws Exception {
        Form form = new Form();
        form.param("uuid", "C5E00DFA-3477-49B7-8070-BE87EA69AD54");
        Response response = m_resourceRule.client().target("/twitter")
                .request()
                .header("Authorization", "Token xyz")
                .post(Entity.form(form));

        assertThat(response.getStatusInfo().getStatusCode(), is(401));

        response = m_resourceRule.client().target("/twitter").request().post(Entity.form(form));

        assertThat(response.getStatusInfo().getStatusCode(), is(401));
    }

    @Test
    public void post_shouldAddStreamByChannelUuid() throws Exception {
        // TODO clear all existing streams

        Form form = new Form();
        form.param("uuid", "C5E00DFA-3477-49B7-8070-BE87EA69AD54");
        Response response = resourceRequest(null).post(Entity.form(form));

        assertThat(response.getStatusInfo().getStatusCode(), is(200));
        StreamEvent event = response.readEntity(StreamEvent.class);
        assertThat(event.getResult(), is(StreamEvent.Result.ADDED));
        assertThat(event.getChannelUuid(), is("C5E00DFA-3477-49B7-8070-BE87EA69AD54"));

        // add same channel again...
        response = resourceRequest(null).post(Entity.form(form));

        assertThat(response.getStatusInfo().getStatusCode(), is(200));
        event = response.readEntity(StreamEvent.class);
        assertThat(event.getResult(), is(StreamEvent.Result.ADDED));
        assertThat(event.getChannelUuid(), is("C5E00DFA-3477-49B7-8070-BE87EA69AD54"));
    }

    @Test
    public void delete_uuid_shouldRemoveStreamByChannelUuid() throws Exception {
        Response response = resourceRequest("C5E00DFA-3477-49B7-8070-BE87EA69AD54").delete();

        assertThat(response.getStatusInfo().getStatusCode(), is(200));
        StreamEvent event = response.readEntity(StreamEvent.class);
        assertThat(event.getResult(), is(StreamEvent.Result.REMOVED));
        assertThat(event.getChannelUuid(), is("C5E00DFA-3477-49B7-8070-BE87EA69AD54"));
    }

    protected Invocation.Builder resourceRequest(String path) {
        WebTarget target = m_resourceRule.client().target("/twitter");
        if (path != null) {
            target = target.path(path);
        }

        return target.request().header("Authorization", "Token " + TEST_AUTH_TOKEN);
    }
}