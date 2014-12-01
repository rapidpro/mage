package io.rapidpro.mage.twitter;

import com.fasterxml.jackson.databind.node.ObjectNode;
import io.rapidpro.mage.MageConstants;
import io.rapidpro.mage.core.ChannelContext;
import io.rapidpro.mage.test.BaseTwitterTest;
import io.rapidpro.mage.test.TestUtils;
import io.rapidpro.mage.util.JsonUtils;
import org.junit.Test;

import static org.hamcrest.Matchers.is;
import static org.hamcrest.Matchers.not;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.twitter.TwitterManager}
 */
public class TwitterManagerTest extends BaseTwitterTest {

    @Test
    public void masterMode() throws Exception {
        // fake another node stealing master state
        getCache().setValue(MageConstants.CacheKey.TWITTER_MASTER_LOCK, "xyz", 30_000);

        // wait for this node to resign from being master...
        TestUtils.assertBecomesTrue(() -> !getTwitter().isMaster(), 10_000);

        assertThat(getCache().getValue(MageConstants.CacheKey.TWITTER_MASTER_LOCK), is("xyz"));

        // fake that node resigning master state
        getCache().deleteValue(MageConstants.CacheKey.TWITTER_MASTER_LOCK);

        // wait for this node to re-become master...
        TestUtils.assertBecomesTrue(() -> getTwitter().isMaster(), 10_000);

        assertThat(getCache().getValue(MageConstants.CacheKey.TWITTER_MASTER_LOCK), not("xyz"));

        // again fake another node stealing master state
        getCache().setValue(MageConstants.CacheKey.TWITTER_MASTER_LOCK, "xyz");

        // wait for this node to resign from being master...
        TestUtils.assertBecomesTrue(() -> !getTwitter().isMaster(), 10_000);

        assertThat(getCache().getValue(MageConstants.CacheKey.TWITTER_MASTER_LOCK), is("xyz"));

        // take master status by force!
        getTwitter().becomeMaster();

        assertThat(getCache().getValue(MageConstants.CacheKey.TWITTER_MASTER_LOCK), not("xyz"));

        // wait for this node to re-become master...
        TestUtils.assertBecomesTrue(() -> getTwitter().isMaster(), 10_000);

        assertThat(getCache().getValue(MageConstants.CacheKey.TWITTER_MASTER_LOCK), not("xyz"));
    }

    @Test
    public void streamOperations() throws Exception {
        String channelUuid = "C5E00DFA-3477-49B7-8070-BE87EA69AD54";
        ChannelContext channel = getServices().getChannelService().getChannelByUuid(channelUuid);

        // ensure that the stream has been added
        TestUtils.assertBecomesTrue(() -> getTwitter().getNodeStreamByChannel(channel) != null, 10_000);

        // request manager to remove stream
        getTwitter().requestStreamOperation(channel, StreamOperation.Action.REMOVE);

        // wait for stream to be removed
        TestUtils.assertBecomesTrue(() -> getTwitter().getNodeStreamByChannel(channel) == null, 10_000);

        // request manager to re-add stream
        getTwitter().requestStreamOperation(channel, StreamOperation.Action.ADD);

        // wait for stream to be added
        TestUtils.assertBecomesTrue(() -> getTwitter().getNodeStreamByChannel(channel) != null, 10_000);

        // in the initial dataset, auto-following is enabled for this channel
        assertThat(getTwitter().getNodeStreamByChannel(channel).isAutoFollow(), is(true));

        // request manager to update stream based on change to auto_follow in config
        ObjectNode config = channel.getChannelConfig();
        config.put("auto_follow", false);
        executeSql(String.format("UPDATE channels_channel SET config = '%s' WHERE uuid = '%s'", JsonUtils.encode(config), channelUuid));
        ChannelContext updatedChannel = getServices().getChannelService().getChannelByUuid(channelUuid);

        getTwitter().requestStreamOperation(updatedChannel, StreamOperation.Action.UPDATE);

        TestUtils.assertBecomesTrue(() -> !getTwitter().getNodeStreamByChannel(channel).isAutoFollow(), 10_000);
    }
}