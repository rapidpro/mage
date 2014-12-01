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
import twitter4j.Paging;
import twitter4j.ResponseList;
import twitter4j.TwitterException;
import twitter4j.User;
import twitter4j.UserStreamAdapter;

import java.time.Duration;
import java.time.Instant;

/**
 * Provides connection to a single Twitter account using both the Streaming API for real time message fetching, and the
 * REST API for back filling
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
        m_streamingClient.start(this);

        // if we don't have a previous last message id, then this channel is being streamed for the first time so don't
        // try to back-fill unless there is one
        Long lastExternalId = getLastExternalId();
        if (lastExternalId != null) {
            m_manager.requestBackfill(new BackfillFetcherTask(lastExternalId));
        }
        else {
            log.info("Skipping back-fill task for new channel #" + getChannel().getChannelId());
            setLastExternalId(0l);
            m_backfillComplete = true;
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
     * @see UserStreamAdapter#onDirectMessage(twitter4j.DirectMessage)
     */
    @Override
    public void onDirectMessage(DirectMessage message) {
        int savedId = handleMessageReceived(message);

        if (savedId > 0) {
            log.info("Direct message " + message.getId() + " received on channel #" + m_channel.getChannelId() + " and saved as msg #" + savedId);
        }
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

    public void onBackfillComplete(long maxMessageId) {
        log.info("Finished back-fill task for channel #" + getChannel().getChannelId() + " (maxId=" + maxMessageId + ")");

        m_backfillComplete = true;
    }

    /**
     * Handles an incoming direct message, whether received via Streaming or REST
     * @param message the direct message
     * @return the saved message id
     */
    protected int handleMessageReceived(DirectMessage message) {
        // don't do anything if we are the sender
        if (message.getSenderId() == m_handleId) {
            return 0;
        }

        IncomingContext context = new IncomingContext(m_channel.getChannelId(), null, ChannelType.TWITTER, m_channel.getOrgId(), null);
        MessageService service = m_manager.getServices().getMessageService();
        ContactUrn from = new ContactUrn(ContactUrn.Scheme.TWITTER, message.getSenderScreenName());
        String name = message.getSenderScreenName();

        int savedId = service.createIncoming(context, from, message.getText(), message.getCreatedAt(), String.valueOf(message.getId()), name);

        Long lastExternalId = getLastExternalId();
        if (lastExternalId != null && message.getId() > lastExternalId) {
            setLastExternalId(message.getId());
        }

        return savedId;
    }

    /**
     * Background task which fetches potentially missed tweets using the REST API
     */
    protected class BackfillFetcherTask implements Runnable {

        private long m_sinceId;

        public BackfillFetcherTask(long sinceId) {
            this.m_sinceId = sinceId;
        }

        /**
         * @see Runnable#run()
         */
        @Override
        public void run() {
            log.info("Starting back-fill task for channel #" + getChannel().getChannelId() + " (sinceId=" + m_sinceId + ")");

            Instant now = Instant.now();

            int page = 1;
            Paging paging = new Paging(page, 200);
            if (m_sinceId > 0) {
                paging.setSinceId(m_sinceId);
            }

            long maxMessageId = 0;

            outer:
            while (true) {
                try {
                    ResponseList<DirectMessage> messages = m_restClient.getDirectMessages(paging);
                    if (messages == null) {
                        break;
                    }

                    // TODO handle rate limit status?
                    //RateLimitStatus rateStatus = messages.getRateLimitStatus();

                    long minPageMessageId = 0;

                    for (DirectMessage message : messages) {
                        // check if message is too old (thus all subsequent messages are too old)
                        if (Duration.between(message.getCreatedAt().toInstant(), now).toMillis() > BACKFILL_MAX_AGE) {
                            break outer;
                        }

                        int savedId = handleMessageReceived(message);
                        if (savedId > 0) {
                            log.info("Direct message " + message.getId() + " back-filled and saved as msg #" + savedId);
                        }

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
                    ex.printStackTrace();

                    // TODO handle rate limit exception? For now just bail
                    break;
                }
            }

            onBackfillComplete(maxMessageId);
        }
    }

    protected Long getLastExternalId() {
        String key = "stream_" + m_channel.getChannelUuid() + ":last_external_id";
        String val = m_manager.getCache().getValue(key);
        return val != null ? Long.parseLong(val) : null;
    }

    protected void setLastExternalId(long externalId) {
        String key = "stream_" + m_channel.getChannelUuid() + ":last_external_id";
        m_manager.getCache().setValue(key, String.valueOf(externalId));
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