package io.rapidpro.mage.resource;

import io.rapidpro.mage.api.StreamEvent;
import io.rapidpro.mage.test.BaseTwitterTest;
import io.rapidpro.mage.util.JsonUtils;
import com.sun.jersey.api.client.ClientResponse;
import com.sun.jersey.api.client.WebResource;
import com.sun.jersey.api.representation.Form;
import io.dropwizard.testing.junit.ResourceTestRule;
import org.junit.Rule;
import org.junit.Test;

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
        form.putSingle("uuid", "C5E00DFA-3477-49B7-8070-BE87EA69AD54");
        ClientResponse response = m_resourceRule.client().resource("/twitter")
                .header("Authorization", "Token xyz")
                .post(ClientResponse.class, form);

        assertThat(response.getStatusInfo().getStatusCode(), is(401));

        response = m_resourceRule.client().resource("/twitter").post(ClientResponse.class, form);

        assertThat(response.getStatusInfo().getStatusCode(), is(401));
    }

    @Test
    public void post_shouldAddStreamByChannelUuid() throws Exception {
        // TODO clear all existing streams

        Form form = new Form();
        form.putSingle("uuid", "C5E00DFA-3477-49B7-8070-BE87EA69AD54");
        ClientResponse response = resourceRequest(null).post(ClientResponse.class, form);

        assertThat(response.getStatusInfo().getStatusCode(), is(200));
        StreamEvent event = response.getEntity(StreamEvent.class);
        assertThat(event.getResult(), is(StreamEvent.Result.ADDED));
        assertThat(event.getChannelUuid(), is("C5E00DFA-3477-49B7-8070-BE87EA69AD54"));

        // add same channel again...
        response = resourceRequest(null).post(ClientResponse.class, form);

        assertThat(response.getStatusInfo().getStatusCode(), is(200));
        event = response.getEntity(StreamEvent.class);
        assertThat(event.getResult(), is(StreamEvent.Result.ADDED));
        assertThat(event.getChannelUuid(), is("C5E00DFA-3477-49B7-8070-BE87EA69AD54"));
    }

    @Test
    public void delete_uuid_shouldRemoveStreamByChannelUuid() throws Exception {
        ClientResponse response = resourceRequest("C5E00DFA-3477-49B7-8070-BE87EA69AD54").delete(ClientResponse.class);

        assertThat(response.getStatusInfo().getStatusCode(), is(200));
        StreamEvent event = response.getEntity(StreamEvent.class);
        assertThat(event.getResult(), is(StreamEvent.Result.REMOVED));
        assertThat(event.getChannelUuid(), is("C5E00DFA-3477-49B7-8070-BE87EA69AD54"));
    }

    protected WebResource.Builder resourceRequest(String path) {
        WebResource resource = m_resourceRule.client().resource("/twitter");
        if (path != null) {
            resource = resource.path(path);
        }

        return resource.header("Authorization", "Token " + TEST_AUTH_TOKEN);
    }
}