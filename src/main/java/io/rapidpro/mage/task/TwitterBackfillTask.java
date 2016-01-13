package io.rapidpro.mage.task;

import com.google.common.collect.ImmutableList;
import com.google.common.collect.ImmutableMultimap;
import io.dropwizard.servlets.tasks.Task;
import io.rapidpro.mage.core.ChannelContext;
import io.rapidpro.mage.twitter.TwitterManager;
import io.rapidpro.mage.twitter.TwitterStream;
import org.apache.commons.lang3.StringUtils;

import java.io.PrintWriter;

/**
 * Task to backfill a Twitter stream
 */
public class TwitterBackfillTask extends Task {

    private final TwitterManager m_twitter;

    public TwitterBackfillTask(TwitterManager twitter) {
        super("twitter-backfill");

        this.m_twitter = twitter;
    }

    /**
     * @see Task#execute(ImmutableMultimap, PrintWriter)
     */
    @Override
    public void execute(ImmutableMultimap<String, String> params, PrintWriter output) throws Exception {
        String channelUuid = getParamValue(params, "channel");
        String hoursStr = getParamValue(params, "hours");

        int hours = StringUtils.isNotEmpty(hoursStr) ? Integer.parseInt(hoursStr) : 0;

        if (StringUtils.isEmpty(channelUuid) || hours == 0) {
            output.println("Channel UUID and number of hours required");
            return;
        }

        output.println("Backfill task initiated for channel " + channelUuid + " for previous " + hours + " hours...");

        ChannelContext channel = m_twitter.getServices().getChannelService().getChannelByUuid(channelUuid);
        if (channel != null) {
            TwitterStream stream = m_twitter.getNodeStreamByChannel(channel);

            if (stream != null) {
                stream.requestBackfill(hours);
                output.println("Back-filling requested for channel #" + channel.getChannelId());
            }
            else {
                output.println("No stream found for channel #" + channel.getChannelId());
            }
        } else {
            output.println("No channel found with UUID " + channelUuid);
        }
    }

    protected String getParamValue(ImmutableMultimap<String, String> params, String name) {
        ImmutableList<String> vals = params.get(name).asList();
        return vals.size() > 0 ? vals.get(0) : null;
    }
}