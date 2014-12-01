package io.rapidpro.mage.temba;

import io.rapidpro.mage.test.BaseMageTest;
import io.rapidpro.mage.temba.request.FollowNotificationRequest;
import io.rapidpro.mage.temba.request.HandleMessageRequest;
import io.rapidpro.mage.util.JsonUtils;
import org.junit.Test;

import static org.hamcrest.Matchers.is;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.temba.TembaRequest}
 */
public class TembaRequestTest extends BaseMageTest {

    /**
     * @see io.rapidpro.mage.temba.TembaRequest#newHandleMessage(int, boolean)
     */
    @Test
    public void newHandleMessage() {
        HandleMessageRequest request = (HandleMessageRequest) TembaRequest.newHandleMessage(345, true);
        assertThat(request.getAction(), is("handle_message"));
        assertThat(request.getMessageId(), is(345));
        assertThat(request.isNewContact(), is(true));

        // encode and decode
        String json = JsonUtils.encode(request, true);
        request = (HandleMessageRequest) JsonUtils.parse(json, TembaRequest.class);
        assertThat(request.getAction(), is("handle_message"));
        assertThat(request.getMessageId(), is(345));
        assertThat(request.isNewContact(), is(true));
    }

    /**
     * @see TembaRequest#newFollowNotification(int, int, boolean)
     */
    @Test
    public void newFollowNotification() {
        FollowNotificationRequest request = (FollowNotificationRequest) TembaRequest.newFollowNotification(123, 456, false);
        assertThat(request.getAction(), is("follow_notification"));
        assertThat(request.getChannelId(), is(123));
        assertThat(request.getContactUrnId(), is(456));
        assertThat(request.isNewContact(), is(false));

        // encode and decode
        String json = JsonUtils.encode(request, true);
        request = (FollowNotificationRequest) JsonUtils.parse(json, TembaRequest.class);
        assertThat(request.getAction(), is("follow_notification"));
        assertThat(request.getChannelId(), is(123));
        assertThat(request.getContactUrnId(), is(456));
        assertThat(request.isNewContact(), is(false));
    }
}