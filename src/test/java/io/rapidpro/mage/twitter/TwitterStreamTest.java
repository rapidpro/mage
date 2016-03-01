package io.rapidpro.mage.twitter;

import io.rapidpro.mage.core.ChannelConfigException;
import io.rapidpro.mage.core.ChannelContext;
import io.rapidpro.mage.test.BaseTwitterTest;
import io.rapidpro.mage.test.TestUtils;
import org.junit.Test;

import java.util.List;
import java.util.Map;

import static org.hamcrest.Matchers.hasEntry;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.twitter.TwitterStream}
 */
public class TwitterStreamTest extends BaseTwitterTest {

    /**
     * @see io.rapidpro.mage.twitter.TwitterStream#TwitterStream(io.rapidpro.mage.twitter.TwitterManager, io.rapidpro.mage.core.ChannelContext, String, String)
     */
    @Test(expected = ChannelConfigException.class)
    public void create_shouldThrowExceptionIfConfigMissing() throws Exception {
        executeSql("UPDATE channels_channel SET config = NULL WHERE uuid = 'C5E00DFA-3477-49B7-8070-BE87EA69AD54'");

        ChannelContext channel = getServices().getChannelService().getChannelByUuid("C5E00DFA-3477-49B7-8070-BE87EA69AD54");
        new TwitterStream(getTwitter(), channel, "abcd", "1234");
    }

    /**
     * @see TwitterStream#TwitterStream(io.rapidpro.mage.twitter.TwitterManager, io.rapidpro.mage.core.ChannelContext, String, String)
     */
    @Test(expected = ChannelConfigException.class)
    public void create_shouldThrowExceptionIfConfigInvalid() throws Exception {
        executeSql("UPDATE channels_channel SET config = '{\"a\":\"b\"}' WHERE uuid = 'C5E00DFA-3477-49B7-8070-BE87EA69AD54'");

        ChannelContext channel = getServices().getChannelService().getChannelByUuid("C5E00DFA-3477-49B7-8070-BE87EA69AD54");
        new TwitterStream(getTwitter(), channel, "abcd", "1234");
    }

    /**
     * @see TwitterStream#TwitterStream(io.rapidpro.mage.twitter.TwitterManager, io.rapidpro.mage.core.ChannelContext, String, String)
     */
    @Test
    public void createAndStart() throws Exception {
        String channelUuid = "C5E00DFA-3477-49B7-8070-BE87EA69AD54";

        ChannelContext channel = getServices().getChannelService().getChannelByUuid(channelUuid);

        TwitterStream stream = new TwitterStream(getTwitter(), channel, "abcd", "1234");
        assertThat(stream.getChannel(), is(channel));
        assertThat(stream.getHandleId(), is(567890l));

        stream.start();

        // ensure streaming starts
        TestUtils.assertBecomesTrue(stream::isStreaming, 10_000);

        // but back-filling shouldn't actually have occurred as channel is new
        assertThat(stream.isBackfilled(), is(false));
        assertThat(queryRows("SELECT * FROM msgs_msg WHERE channel_id = -44" ), hasSize(0));

        stream.stop();

        channel = getServices().getChannelService().getChannelByUuid(channelUuid);
        stream = new TwitterStream(getTwitter(), channel, "abcd", "1234");
        stream.start();

        // TODO figure out a good way to test saving and back-filling actual direct messages

        // ensure streaming starts
        TestUtils.assertBecomesTrue(stream::isStreaming, 10_000);

        // and back-filling actually happened
        assertThat(stream.isBackfilled(), is(true));

        stream.onDirectMessage(createDirectMessage("twitter/direct_message_1.json"));

        assertThat(queryRows("SELECT * FROM msgs_msg WHERE channel_id = -44"), hasSize(1));

        List<Map<String, Object>> contacts = queryRows("SELECT * FROM contacts_contact WHERE org_id = -11 ORDER BY created_on");
        assertThat(contacts, hasSize(2));
        assertThat(contacts.get(0), hasEntry("name", "Nicolas"));
        assertThat(contacts.get(1), hasEntry("name", "Norbert Kwizera"));

        // urns are always lowercase
        List<Map<String, Object>> urns = queryRows("SELECT * FROM contacts_contacturn WHERE org_id = -11 AND scheme = 'twitter' ORDER BY id");
        assertThat(urns, hasSize(1));
        assertThat(urns.get(0), hasEntry("path", "norkans"));

        // another user follows channel user
        stream.onFollow(createTwitterUser("twitter/user_2.json"), createTwitterUser("twitter/user_1.json"));

        contacts = queryRows("SELECT * FROM contacts_contact WHERE org_id = -11 ORDER BY created_on");
        assertThat(contacts, hasSize(3));
        assertThat(contacts.get(2), hasEntry("name", "Bosco"));

        // channel user following them back shouldn't add anything
        stream.onFollow(createTwitterUser("twitter/user_1.json"), createTwitterUser("twitter/user_2.json"));

        assertThat(queryRows("SELECT * FROM contacts_contact WHERE org_id = -11"), hasSize(3));

        // make org anonymous and restart stream
        executeSql("UPDATE orgs_org SET is_anon = TRUE WHERE id = -11");
        stream.stop();
        channel = getServices().getChannelService().getChannelByUuid(channelUuid);
        stream = new TwitterStream(getTwitter(), channel, "abcd", "1234");
        stream.start();

        // now when we receive a new DM, new contact should be nameless
        stream.onDirectMessage(createDirectMessage("twitter/direct_message_2.json"));

        contacts = queryRows("SELECT * FROM contacts_contact WHERE org_id = -11 ORDER BY created_on");
        assertThat(contacts, hasSize(4));
        assertThat(contacts.get(3), hasEntry("name", null));

        // also when followed...
        stream.onFollow(createTwitterUser("twitter/user_3.json"), createTwitterUser("twitter/user_1.json"));

        contacts = queryRows("SELECT * FROM contacts_contact WHERE org_id = -11 ORDER BY created_on");
        assertThat(contacts, hasSize(5));
        assertThat(contacts.get(4), hasEntry("name", null));

        urns = queryRows("SELECT * FROM contacts_contacturn WHERE org_id = -11 AND scheme = 'twitter' ORDER BY id DESC");
        assertThat(urns, hasSize(4));
        assertThat(urns.get(0), hasEntry("path", "joeflowz"));

        stream.stop();
    }
}