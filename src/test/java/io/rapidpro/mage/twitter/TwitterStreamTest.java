package io.rapidpro.mage.twitter;

import io.rapidpro.mage.core.ChannelConfigException;
import io.rapidpro.mage.core.ChannelContext;
import io.rapidpro.mage.test.BaseTwitterTest;
import io.rapidpro.mage.test.TestUtils;
import org.junit.Test;

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

        // ensure backfill "completes"
        TestUtils.assertBecomesTrue(stream::isBackfillComplete, 10_000);

        // but back filling shouldn't actually have occurred as channel is new
        assertThat(queryRows("SELECT * FROM msgs_msg WHERE channel_id = -44" ), hasSize(0));
        assertThat(querySingle("SELECT bod FROM channels_channel WHERE id = " + channel.getChannelId()).get("bod"), is("0"));

        stream.stop();

        stream = new TwitterStream(getTwitter(), channel, "abcd", "1234");
        stream.start();

        // TODO figure out a good way to test saving and back-filling actual direct messages

        // ensure backfill completes
        TestUtils.assertBecomesTrue(stream::isBackfillComplete, 10_000);

        stream.onDirectMessage(createDirectMessage("twitter/direct_message_1.json"));

        assertThat(queryRows("SELECT * FROM msgs_msg WHERE channel_id = -44"), hasSize(1));
        assertThat(queryRows("SELECT * FROM contacts_contact WHERE org_id = -11"), hasSize(2));
        assertThat(querySingle("SELECT bod FROM channels_channel WHERE id = -44").get("bod"), is("0"));

        // another user follows channel user
        stream.onFollow(createTwitterUser("twitter/user_2.json"), createTwitterUser("twitter/user_1.json"));

        assertThat(queryRows("SELECT * FROM contacts_contact WHERE org_id = -11"), hasSize(3));
        assertThat(querySingle("SELECT bod FROM channels_channel WHERE id = -44").get("bod"), is("2960784075"));

        // channel user following them back shouldn't add anything
        stream.onFollow(createTwitterUser("twitter/user_1.json"), createTwitterUser("twitter/user_2.json"));

        assertThat(queryRows("SELECT * FROM contacts_contact WHERE org_id = -11"), hasSize(3));
        assertThat(querySingle("SELECT bod FROM channels_channel WHERE id = -44").get("bod"), is("2960784075"));

        stream.stop();
    }
}