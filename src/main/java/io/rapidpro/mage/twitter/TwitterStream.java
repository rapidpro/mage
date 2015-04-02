package io.rapidpro.mage.twitter;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import io.rapidpro.mage.core.ChannelConfigException;
import io.rapidpro.mage.core.ChannelContext;
import io.rapidpro.mage.core.ChannelType;
import io.rapidpro.mage.core.ContactContext;
import io.rapidpro.mage.core.ContactUrn;
import io.rapidpro.mage.core.IncomingContext;
import io.rapidpro.mage.service.MessageService;
import io.rapidpro.mage.temba.TembaRequest;
import com.twitter.hbc.core.StatsReporter;
import io.dropwizard.lifecycle.Managed;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import twitter4j.DirectMessage;
import twitter4j.PagableResponseList;
import twitter4j.Paging;
import twitter4j.RateLimitStatus;
import twitter4j.ResponseList;
import twitter4j.TwitterException;
import twitter4j.User;
import twitter4j.UserStreamAdapter;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

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
    protected static final String CONFIG_AUTO_FOLLOW = "auto_follow";

    protected static final long BACKFILL_MAX_AGE = 60 * 60 * 1000; // 1 hour (in millis)

    private final TwitterManager m_manager;
    private final ChannelContext m_channel;
    private long m_handleId;
    private boolean m_autoFollow;

    private TwitterClients.RestClient m_restClient;
    private TwitterClients.StreamingClient m_streamingClient;
    private boolean m_backfillComplete = false;

    public TwitterStream(TwitterManager manager, ChannelContext channel, String apiKey, String apiSecret) throws ChannelConfigException {
        this.m_manager = manager;
        this.m_channel = channel;

        ObjectNode config = channel.getChannelConfig();
        if (config == null) {
            throw new ChannelConfigException("Channel #" + channel.getChannelId() + " has no configuration");
        }

        JsonNode handleId = config.get(CONFIG_HANDLE_ID);
        m_handleId = handleId != null ? handleId.longValue() : 0l;

        JsonNode token = config.get(CONFIG_TOKEN);
        JsonNode secret = config.get(CONFIG_TOKEN_SECRET);
        if (token == null || secret == null) {
            throw new ChannelConfigException("Channel #" + channel.getChannelId() + " has no Twitter auth configuration");
        }

        updateFromConfig(config);

        boolean production = m_manager.getServices().isProduction();

        m_restClient = TwitterClients.getRestClient(apiKey, apiSecret, token.textValue(), secret.textValue(), production);
        m_streamingClient = TwitterClients.getStreamingClient(apiKey, apiSecret, token.textValue(), secret.textValue(), production);
    }

    /**
     * Updates this stream according to the given channel config
     * @param config the configuration JSON
     */
    public void updateFromConfig(ObjectNode config) {
        JsonNode autoFollow = config.get(CONFIG_AUTO_FOLLOW);
        m_autoFollow = autoFollow == null || autoFollow.booleanValue();
    }

    /**
     * @see io.dropwizard.lifecycle.Managed#start()
     */
    @Override
    public void start() throws Exception {
        // for Twitter channels, bod field is used to hold the external id of last message retrieved
        Long lastExternalId = getLastExternalId();

        // if we don't have a previous last message id, then this channel is being streamed for the first time so don't
        // try to back-fill
        if (lastExternalId != null) {
            m_manager.requestBackfill(new BackfillFetcherTask(lastExternalId));
        }
        else {
            onBackfillComplete(0l, false);
        }
    }

    /**
     * @see io.dropwizard.lifecycle.Managed#stop()
     */
    @Override
    public void stop() throws Exception {
        m_streamingClient.stop();
    }

    /**
     * Called when back-filling step is complete or skipped
     * @param lastExternalId the maximum message id retrieved during back-fill
     * @param performed whether back-filling was performed or skipped
     */
    public void onBackfillComplete(long lastExternalId, boolean performed) {
        if (performed) {
            log.info("Finished back-fill task for channel #" + getChannel().getChannelId() + " (last id is " + lastExternalId + ")");
        }
        else {
            log.info("Skipped back-fill task for channel #" + getChannel().getChannelId());
        }

        setLastExternalId(lastExternalId);

        m_backfillComplete = true;

        // to preserve message order, only start streaming after back-filling is complete
        m_streamingClient.start(this);
    }

    /**
     * Handles an incoming direct message, whether received via streaming or back-filling
     * @param message the direct message
     * @return the saved message id
     */
    protected int handleMessageReceived(DirectMessage message, boolean fromStream) {
        // don't do anything if we are the sender
        if (message.getSenderId() == m_handleId) {
            return 0;
        }

        IncomingContext context = new IncomingContext(m_channel.getChannelId(), null, ChannelType.TWITTER, m_channel.getOrgId(), null);
        MessageService service = m_manager.getServices().getMessageService();
        ContactUrn from = new ContactUrn(ContactUrn.Scheme.TWITTER, message.getSenderScreenName());
        String name = message.getSenderScreenName();

        int savedId = service.createIncoming(context, from, message.getText(), message.getCreatedAt(), String.valueOf(message.getId()), name);

        log.info("Direct message " + message.getId() + " " + (fromStream ? "streamed" : "back-filled") + " on channel #" + m_channel.getChannelId() + " and saved as msg #" + savedId);

        setLastExternalId(message.getId());

        return savedId;
    }

    /**
     * @see UserStreamAdapter#onDirectMessage(twitter4j.DirectMessage)
     */
    @Override
    public void onDirectMessage(DirectMessage message) {
        handleMessageReceived(message, true);
    }

    /**
     * @see UserStreamAdapter#onFollow(twitter4j.User, twitter4j.User)
     */
    @Override
    public void onFollow(User follower, User followed) {
        // don't do anything the user being followed isn't us
        if (followed.getId() != m_handleId) {
            return;
        }

        // optionally follow back
        if (m_autoFollow) {
            try {
                m_restClient.createFriendship(follower.getId());

                log.info("Auto-followed user '" + follower.getScreenName() + "' by '" + followed.getScreenName() + "'");
            } catch (TwitterException ex) {
                log.error("Unable to auto-follow '" + follower.getScreenName() + "' by '" + followed.getScreenName() + "'", ex);
            }
        }

        // ensure contact exists for this new follower
        ContactUrn urn = new ContactUrn(ContactUrn.Scheme.TWITTER, follower.getScreenName());
        ContactContext contact = m_manager.getServices().getContactService().getOrCreateContact(getChannel().getOrgId(),
                urn, getChannel().getChannelId(), follower.getScreenName());

        // queue a request to notify Temba that the channel account has been followed
        TembaRequest request = TembaRequest.newFollowNotification(getChannel().getChannelId(), contact.getContactUrnId(), contact.isNewContact());
        m_manager.getTemba().queueRequest(request);
    }

    /**
     * Background task which fetches potentially missed tweets and follows using the REST API. This happens in a task
     * so the Twitter Manager can run multiple back-fill tasks sequentially, making it easier to respect the Twitter API
     * rate limits.
     */
    protected class BackfillFetcherTask implements Runnable {

        private long m_lastMessageId;

        public BackfillFetcherTask(long lastMessageId) {
            this.m_lastMessageId = lastMessageId;
        }

        /**
         * @see Runnable#run()
         */
        @Override
        public void run() {
            log.info("Starting back-fill task for channel #" + getChannel().getChannelId() + " (sinceId=" + m_lastMessageId + ")");

            backfillFollows();

            long maxMessageId = backfillTweets();

            onBackfillComplete(maxMessageId, true);
        }

        /**
         * Back-fills missed follows
         */
        protected void backfillFollows() {
            long cursor = -1l;
            while (true) {
                try {
                    PagableResponseList<User> followers = m_restClient.getFollowers(cursor);
                    if (followers == null) {
                        break;
                    }

                    for (User follower : followers) {
                        // ensure contact exists for this follower
                        ContactUrn urn = new ContactUrn(ContactUrn.Scheme.TWITTER, follower.getScreenName());
                        ContactContext contact = m_manager.getServices().getContactService().getOrCreateContact(getChannel().getOrgId(),
                                urn, getChannel().getChannelId(), follower.getScreenName());

                        if (contact.isNewContact()) {
                            log.info("Follow from " + follower.getScreenName() + " back-filled and saved as new contact #" + contact.getContactId());

                            // queue a request to notify Temba that the channel account has been followed
                            TembaRequest request = TembaRequest.newFollowNotification(getChannel().getChannelId(), contact.getContactUrnId(), contact.isNewContact());
                            m_manager.getTemba().queueRequest(request);
                        }
                    }

                    if (followers.hasNext()) {
                        cursor = followers.getNextCursor();
                    } else {
                        break;
                    }

                } catch (TwitterException ex) {
                    if (ex.exceededRateLimitation()) {
                        // log as error so goes to Sentry
                        log.error("Exceeded rate limit", ex);

                        RateLimitStatus status = ex.getRateLimitStatus();
                        try {
                            Thread.sleep(status.getSecondsUntilReset() * 1000);
                            continue;

                        } catch (InterruptedException e) {
                            break;
                        }
                    }
                    break;
                }
            }
        }

        /**
         * Back-fills missed tweets
         * @return the last message id back filled
         */
        protected long backfillTweets() {
            Instant now = Instant.now();

            int page = 1;
            Paging paging = new Paging(page, 200);
            if (m_lastMessageId > 0) {
                paging.setSinceId(m_lastMessageId);
            }

            List<DirectMessage> all_messages = new ArrayList<>();
            long maxMessageId = 0;

            // fetch all messages - Twitter will give us them in reverse chronological order
            outer:
            while (true) {
                try {
                    ResponseList<DirectMessage> messages = m_restClient.getDirectMessages(paging);
                    if (messages == null) {
                        break;
                    }

                    long minPageMessageId = 0;

                    for (DirectMessage message : messages) {
                        // check if message is too old (thus all subsequent messages are too old)
                        if (Duration.between(message.getCreatedAt().toInstant(), now).toMillis() > BACKFILL_MAX_AGE) {
                            break outer;
                        }

                        all_messages.add(message);

                        maxMessageId = Math.max(maxMessageId, message.getId());
                        minPageMessageId = Math.min(minPageMessageId, message.getId());
                    }

                    if (messages.size() < paging.getCount()) { // no more messages
                        break;
                    }

                    // update paging to get next 200 DMs, ensuring that we don't take new ones into account
                    paging.setPage(page);
                    paging.setMaxId(minPageMessageId - 1); // see https://dev.twitter.com/rest/public/timelines

                } catch (TwitterException ex) {
                    if (ex.exceededRateLimitation()) {
                        // log as error so goes to Sentry
                        log.error("Exceeded rate limit", ex);

                        RateLimitStatus status = ex.getRateLimitStatus();
                        try {
                            Thread.sleep(status.getSecondsUntilReset() * 1000);
                            continue;

                        } catch (InterruptedException e) {
                            break;
                        }
                    }
                    break;
                }
            }

            // handle all messages in chronological order
            Collections.reverse(all_messages);
            for (DirectMessage message : all_messages) {
                handleMessageReceived(message, false);
            }

            return maxMessageId;
        }
    }

    protected Long getLastExternalId() {
        // this was previously being stored in Redis so look there first
        String key = "stream_" + m_channel.getChannelUuid() + ":last_external_id";
        String val = m_manager.getCache().getValue(key);
        if (val != null) {
            // migrate value to channel.bod field so next time we get it from there
            long fromRedis = Long.parseLong(val);
            setLastExternalId(fromRedis);
            m_manager.getCache().deleteValue(key);
            return fromRedis;
        }

        if (m_channel.getChannelBod() != null) {
            try {
                return Long.parseLong(m_channel.getChannelBod());
            }
            catch (NumberFormatException ex) {}
        }

        return null;
    }

    /**
     * Updates the last external message id record for this stream
     * @param externalId the message id from Twitter
     */
    protected void setLastExternalId(long externalId) {
        m_manager.getServices().getChannelService().updateChannelBod(m_channel.getChannelId(), String.valueOf(externalId));
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

    public boolean isBackfillComplete() {
        return m_backfillComplete;
    }

    public boolean isAutoFollow() {
        return m_autoFollow;
    }
}