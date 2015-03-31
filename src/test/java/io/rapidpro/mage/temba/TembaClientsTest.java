package io.rapidpro.mage.temba;

import com.fasterxml.jackson.annotation.JsonProperty;
import io.rapidpro.mage.test.BaseMageTest;
import org.junit.Test;

import javax.ws.rs.core.Form;

import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.temba.TembaClients}
 */
public class TembaClientsTest extends BaseMageTest {

    /**
     * @see io.rapidpro.mage.temba.TembaClients#buildForm(io.rapidpro.mage.temba.TembaRequest)
     */
    @Test
    public void buildForm_shouldBuildFormFromRequest() {
        TembaRequest request1 = TembaRequest.newHandleMessage(345, false);
        Form form1 = TembaClients.buildForm(request1);

        assertThat(form1.asMap().keySet(), hasSize(2));
        assertThat(form1.asMap().getFirst("message_id"), is("345"));
        assertThat(form1.asMap().getFirst("new_contact"), is("false"));

        TembaRequest request2 = TembaRequest.newFollowNotification(123, 456, true);
        Form form2 = TembaClients.buildForm(request2);

        assertThat(form2.asMap().keySet(), hasSize(3));
        assertThat(form2.asMap().getFirst("channel_id"), is("123"));
        assertThat(form2.asMap().getFirst("contact_urn_id"), is("456"));
        assertThat(form2.asMap().getFirst("new_contact"), is("true"));

        TestRequest request3 = new TestRequest();
        request3.setSerialized("abc");
        request3.setNotSerialized("xyz");
        Form form3 = TembaClients.buildForm(request3);

        assertThat(form3.asMap().keySet(), hasSize(1));
        assertThat(form3.asMap().getFirst("serialized"), is("abc"));
    }

    public class TestRequest extends TembaRequest {

        @JsonProperty("serialized")
        private String m_serialized;

        private String m_notSerialized;

        public TestRequest() {
            super(TembaRequest.HANDLE_MESSAGE);
        }

        public void setSerialized(String serialized) {
            m_serialized = serialized;
        }

        public void setNotSerialized(String notSerialized) {
            m_notSerialized = notSerialized;
        }
    }
}