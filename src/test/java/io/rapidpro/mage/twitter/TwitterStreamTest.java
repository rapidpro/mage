package io.rapidpro.mage.twitter;

import io.rapidpro.mage.core.ChannelConfigException;
import io.rapidpro.mage.core.ChannelContext;
import io.rapidpro.mage.test.BaseTwitterTest;
import io.rapidpro.mage.test.TestUtils;
import org.junit.Ignore;
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
    public void create_shouldNotBackfillWhenNew() throws Exception {
        String channelUuid = "C5E00DFA-3477-49B7-8070-BE87EA69AD54";
        String lastExtIdKey = "stream_" + channelUuid + ":last_external_id";

        ChannelContext channel = getServices().getChannelService().getChannelByUuid(channelUuid);

        TwitterStream stream = new TwitterStream(getTwitter(), channel, "abcd", "1234");
        assertThat(stream.getChannel(), is(channel));
        assertThat(stream.getHandleId(), is(567890l));

        stream.start();

        // ensure backfill "completes"
        TestUtils.assertBecomesTrue(stream::isBackfillComplete, 10_000);

        // but back filling shouldn't actually have occurred as stream had no 'last external id' in redis
        assertThat(queryRows("SELECT * FROM msgs_msg WHERE channel_id = " + channel.getChannelId()), hasSize(0));
        assertThat(Long.parseLong(getCache().getValue(lastExtIdKey)), is(0l));

        stream.stop();

        stream = new TwitterStream(getTwitter(), channel, "abcd", "1234");
        stream.start();

        // ensure backfill "completes"
        TestUtils.assertBecomesTrue(stream::isBackfillComplete, 10_000);

        stream.stop();

        // TODO figure out a good way to test saving and back-filling actual direct messages
    }

    /**
     * @see TwitterStream#onFollow(twitter4j.User, twitter4j.User)
     */
    @Ignore
    @Test
    public void onFollow_shouldAddContactAndFollowBack() throws Exception {
        /*String channelUuid = "C5E00DFA-3477-49B7-8070-BE87EA69AD54";
        ChannelContext channel = getServices().getChannelService().getChannelByUuid(channelUuid);
        TwitterStream stream = getTwitter().getNodeStreamByChannel(channel);

        User mockChannelUser = PowerMockito.mock(User.class);
        User mockOtheruser = PowerMockito.mock(User.class);

        PowerMockito.when(mockChannelUser.getId()).thenReturn(567890l);
        PowerMockito.when(mockChannelUser.getScreenName()).thenReturn("Nyaruka");
        PowerMockito.when(mockOtheruser.getId()).thenReturn(987654l);
        PowerMockito.when(mockOtheruser.getScreenName()).thenReturn("Annie83");

        // the channel user doing the following should do nothing
        stream.onFollow(mockChannelUser, mockOtheruser);

        assertThat(queryRows("SELECT * FROM "+ Table.CONTACT + " WHERE name = 'Annie83'"), hasSize(0));
        assertThat(getCache().listLength(MageConstants.CacheKey.TEMBA_REQUEST_QUEUE), is(0l));

        // the channel user being followed should create a new contact
        stream.onFollow(mockOtheruser, mockChannelUser);

        Map<String, Object> contact = querySingle("SELECT * FROM " + Table.CONTACT + " WHERE name = 'Annie83'");
        Map<String, Object> contactUrn = querySingle("SELECT * FROM " + Table.CONTACT_URN + " WHERE contact_id = " + contact.get("id"));
        assertThat(contactUrn, hasEntry("urn", "twitter:Annie83"));
        assertThat(contactUrn, hasEntry("scheme", "twitter"));
        assertThat(contactUrn, hasEntry("path", "Annie83"));

        TembaRequest request = JsonUtils.parse(getCache().listLPop(MageConstants.CacheKey.TEMBA_REQUEST_QUEUE), TembaRequest.class);
        assertThat(request, instanceOf(FollowNotificationRequest.class));
        assertThat(((FollowNotificationRequest) request).getChannelId(), is(channel.getChannelId()));
        assertThat(((FollowNotificationRequest) request).getContactUrnId(), is(contactUrn.get("id")));*/
    }
}