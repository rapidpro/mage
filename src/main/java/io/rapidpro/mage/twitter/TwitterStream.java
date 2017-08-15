package io.rapidpro.mage.twitter;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.google.common.util.concurrent.ThreadFactoryBuilder;
import io.rapidpro.mage.core.ChannelConfigException;
import io.rapidpro.mage.core.ChannelContext;
import io.rapidpro.mage.core.ChannelType;
import io.rapidpro.mage.core.ContactContext;
import io.rapidpro.mage.core.ContactUrn;
import io.rapidpro.mage.core.Direction;
import io.rapidpro.mage.core.IncomingContext;
import io.rapidpro.mage.service.MessageService;
import io.rapidpro.mage.temba.TembaRequest;
import com.twitter.hbc.core.StatsReporter;
import io.dropwizard.lifecycle.Managed;
import org.apache.commons.lang3.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import twitter4j.DirectMessage;
import twitter4j.Paging;
import twitter4j.ResponseList;
import twitter4j.TwitterException;
import twitter4j.User;
import twitter4j.UserStreamAdapter;

import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadFactory;

/**
 * Provides connection to a single Twitter account using both the Streaming API for real time message fetching, and the
 * REST API for back filling. When the stream is started it first checks the channel BOD field to see if there is a
 * last message id. If there isn't then we know that this is a new stream and we don't try to back-fill anything. If
 * there is then that is used as a starting point for back-filling.
 */
public class TwitterStream extends UserStreamAdapter implements Managed {

    protected static final Logger log = LoggerFactory.getLogger(TwitterStream.class);

    protected static final String CONFIG_HANDLE_ID = "handle_id";
    protected static final String CONFIG_TOKEN = "oauth_token";
    protected static final String CONFIG_TOKEN_SECRET = "oauth_token_secret";

    private final TwitterManager m_manager;
    private final ChannelContext m_channel;
    private long m_handleId;

    private TwitterClients.RestClient m_restClient;
    private TwitterClients.StreamingClient m_streamingClient;
    private boolean m_backfilled = false;
    private boolean m_streaming = false;

    private ExecutorService m_backfillExecutor;

    public TwitterStream(TwitterManager manager, ChannelContext channel, String apiKey, String apiSecret) throws ChannelConfigException {
        this.m_manager = manager;
        this.m_channel = channel;

        ObjectNode config = channel.getChannelConfig();
        if (config == null) {
            throw new ChannelConfigException("Channel #" + channel.getChannelId() + " has no configuration");
        }

        JsonNode handleId = config.get(CONFIG_HANDLE_ID);
        m_handleId = handleId != null ? handleId.longValue() : 0L;

        JsonNode token = config.get(CONFIG_TOKEN);
        JsonNode secret = config.get(CONFIG_TOKEN_SECRET);
        if (token == null || secret == null) {
            throw new ChannelConfigException("Channel #" + channel.getChannelId() + " has no Twitter auth configuration");
        }

        updateFromConfig(config);

        boolean production = m_manager.getServices().isProduction();

        m_restClient = TwitterClients.getRestClient(apiKey, apiSecret, token.textValue(), secret.textValue(), production);
        m_streamingClient = TwitterClients.getStreamingClient(apiKey, apiSecret, token.textValue(), secret.textValue(), production);

        ThreadFactory backfillFactory = new ThreadFactoryBuilder().setNameFormat("backfill-%d").build();
        m_backfillExecutor = Executors.newSingleThreadExecutor(backfillFactory);
    }

    /**
     * Updates this stream according to the given channel config
     * @param config the configuration JSON
     */
    public void updateFromConfig(ObjectNode config) {
        // currently no-op as there are no config options
    }

    /**
     * @see io.dropwizard.lifecycle.Managed#start()
     */
    @Override
    public void start() throws Exception {
        if (StringUtils.isEmpty(m_channel.getChannelBod())) {
            // this channel is new so don't really back-fill
            onBackfillComplete(false);
        }
        else {
            m_backfillExecutor.execute(new BackfillFetcherTask(1, true)); // back-fill over last hour
        }

        String timestamp = String.valueOf(System.currentTimeMillis());
        m_manager.getServices().getChannelService().updateChannelBod(m_channel.getChannelId(), timestamp);
    }

    /**
     * @see io.dropwizard.lifecycle.Managed#stop()
     */
    @Override
    public void stop() throws Exception {
        m_backfillExecutor.shutdown();

        m_streamingClient.stop();
    }

    /**
     * Request back-filling
     * @param hours the number of hours
     */
    public void requestBackfill(int hours) {
        m_backfillExecutor.execute(new BackfillFetcherTask(hours, false));
    }

    /**
     * Called when back-filling step is complete or skipped
     */
    public void onBackfillComplete(boolean performed) {
        log.info((performed ? "Finished" : "Skipped") + " back-fill task for channel #" + getChannel().getChannelId());

        m_backfilled = performed;

        // to preserve message order, only start streaming after back-filling is complete
        m_streamingClient.start(this);

        m_streaming = true;
    }

    /**
     * Handles an incoming direct message, whether received via streaming or back-filling
     * @param message the direct message
     * @param fromStream whether this came from streaming or back-filling
     * @return the saved message id
     */
    protected int handleMessageReceived(DirectMessage message, boolean fromStream) {
        IncomingContext context = new IncomingContext(m_channel.getChannelId(), null, ChannelType.TWITTER, m_channel.getOrgId(), null);
        MessageService service = m_manager.getServices().getMessageService();
        ContactUrn from = new ContactUrn(ContactUrn.Scheme.TWITTERID, "" + message.getSenderId(), message.getSenderScreenName());
        String name = m_channel.isOrgAnon() ? null : message.getSender().getName();

        int savedId = service.createIncoming(context, from, message.getText(), message.getCreatedAt(), String.valueOf(message.getId()), name);

        log.info("Direct message " + message.getId() + " " + (fromStream ? "streamed" : "back-filled") + " on channel #" + m_channel.getChannelId() + " and saved as msg #" + savedId);

        return savedId;
    }

    /**
     * Handles a following of this handle
     * @param follower the new follower
     */
    protected void handleFollow(User follower) {
        // ensure contact exists for this new follower
        ContactUrn urn = new ContactUrn(ContactUrn.Scheme.TWITTERID, "" + follower.getId(), follower.getScreenName()).normalize(null);
        String name = m_channel.isOrgAnon() ? null : follower.getName();

        ContactContext contact = m_manager.getServices().getContactService().getOrCreateContact(getChannel().getOrgId(),
                urn, getChannel().getChannelId(), name);

        if (contact.isNewContact()) {
            log.info("New follower '" + follower.getScreenName() + "' on channel #" + m_channel.getChannelId() + " and saved as contact #" + contact.getContactId());
        } else {
            log.info("New follower '" + follower.getScreenName() + "' on channel #" + m_channel.getChannelId() + " is existing contact #" + contact.getContactId());
        }

        // queue a request to notify Temba that the channel account has been followed
        TembaRequest request = TembaRequest.newFollowNotification(getChannel().getChannelId(), contact.getContactUrnId(), contact.isNewContact());
        m_manager.getTemba().queueRequest(request);
    }

    /**
     * Handles an un-following of this handle
     * @param unfollower the user that unfollowed
     */
    protected void handleUnfollow(User unfollower) {
        // for now just log this
        log.info("Un-followed by '" + unfollower.getScreenName() + "' on channel #" + m_channel.getChannelId());
    }

    /**
     * @see UserStreamAdapter#onDirectMessage(twitter4j.DirectMessage)
     */
    @Override
    public void onDirectMessage(DirectMessage message) {
        try {
            // don't do anything if we are the sender
            if (message.getSenderId() == m_handleId) {
                return;
            }

            handleMessageReceived(message, true);
        }
        catch (Exception ex) {
            // ensure any errors go to Sentry
            log.error("Unable to handle message", ex);
        }
    }

    /**
     * @see UserStreamAdapter#onFollow(twitter4j.User, twitter4j.User)
     */
    @Override
    public void onFollow(User follower, User followed) {
        try {
            // don't do anything the user being followed isn't us
            if (followed.getId() != m_handleId) {
                return;
            }

            handleFollow(follower);
        }
        catch (Exception ex) {
            // ensure any errors go to Sentry
            log.error("Unable to handle new follow", ex);
        }
    }

    /**
     * @see UserStreamAdapter#onUnfollow(twitter4j.User, twitter4j.User)
     */
    @Override
    public void onUnfollow(User source, User unfollowed) {
        try {
            // don't do anything the user being un-followed isn't us
            if (unfollowed.getId() != m_handleId) {
                return;
            }

            handleUnfollow(unfollowed);
        }
        catch (Exception ex) {
            // ensure any errors go to Sentry
            log.error("Unable to handle unfollow", ex);
        }
    }

    /**
     * @see twitter4j.StatusAdapter#onTrackLimitationNotice(int)
     */
    @Override
    public void onTrackLimitationNotice(int numberOfLimitedStatuses) {
        log.warn("Track limitation notice: " + numberOfLimitedStatuses);

        super.onTrackLimitationNotice(numberOfLimitedStatuses);
    }

    @Override
    public void onException(Exception ex) {
        log.error("Exception in Twitter stream", ex);

        super.onException(ex);
    }

    /**
     * Background task which fetches potentially missed tweets using the REST API. This happens in a task so the
     * Twitter Manager can execute all back-fill tasks sequentially, making it easier to respect the Twitter API
     * rate limits.
     */
    protected class BackfillFetcherTask implements Runnable {

        protected int m_hours;
        protected boolean m_isStarting;

        public BackfillFetcherTask(int hours, boolean isStarting) {
            this.m_hours = hours;
            this.m_isStarting = isStarting;
        }

        /**
         * @see Runnable#run()
         */
        @Override
        public void run() {
            log.info("Starting back-fill task for channel #" + getChannel().getChannelId());

            try {
                backfillMessages();

                if (m_isStarting) {
                    onBackfillComplete(true);
                }
            }
            catch (TwitterException ex) {
                throw new RuntimeException(ex);
            }
        }

        /**
         * Back-fills missed direct messages
         */
        protected void backfillMessages() throws TwitterException {
            Instant now = Instant.now();
            Instant minMsgTime = now.minus(m_hours, ChronoUnit.HOURS);

            int page = 1;
            Paging paging = new Paging(page, 200);
            List<DirectMessage> all_messages = new ArrayList<>();

            // fetch all messages - Twitter will give us them in reverse chronological order
            outer:
            while (true) {
                ResponseList<DirectMessage> messages = m_restClient.getDirectMessages(paging);
                if (messages == null) {
                    break;
                }

                long minPageMessageId = 0;

                for (DirectMessage message : messages) {
                    // check if message is too old (thus all subsequent messages are too old)
                    if (message.getCreatedAt().toInstant().isBefore(minMsgTime)) {
                        break outer;
                    }

                    all_messages.add(message);

                    minPageMessageId = Math.min(minPageMessageId, message.getId());
                }

                if (messages.size() < paging.getCount()) { // no more messages
                    break;
                }

                // update paging to get next 200 DMs, ensuring that we don't take new ones into account
                paging.setPage(page);
                paging.setMaxId(minPageMessageId - 1); // see https://dev.twitter.com/rest/public/timelines
            }

            // handle all messages in chronological order
            Collections.reverse(all_messages);
            for (DirectMessage message : all_messages) {
                handleMessageReceived(message, false);
            }
        }
    }

    public ChannelContext getChannel() {
        return m_channel;
    }

    public StatsReporter.StatsTracker getStreamingStatistics() {
        return m_streamingClient.getStatsTracker();
    }

    public long getHandleId() {
        return m_handleId;
    }

    public boolean isBackfilled() {
        return m_backfilled;
    }

    public boolean isStreaming() {
        return m_streaming;
    }
}