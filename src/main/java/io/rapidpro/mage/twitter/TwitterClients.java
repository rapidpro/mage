package io.rapidpro.mage.twitter;

import com.twitter.hbc.ClientBuilder;
import com.twitter.hbc.core.Client;
import com.twitter.hbc.core.Constants;
import com.twitter.hbc.core.HttpHosts;
import com.twitter.hbc.core.StatsReporter;
import com.twitter.hbc.core.endpoint.UserstreamEndpoint;
import com.twitter.hbc.core.processor.StringDelimitedProcessor;
import com.twitter.hbc.httpclient.auth.Authentication;
import com.twitter.hbc.httpclient.auth.OAuth1;
import com.twitter.hbc.twitter4j.Twitter4jUserstreamClient;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import twitter4j.DirectMessage;
import twitter4j.PagableResponseList;
import twitter4j.Paging;
import twitter4j.RateLimitStatus;
import twitter4j.ResponseList;
import twitter4j.Twitter;
import twitter4j.TwitterException;
import twitter4j.TwitterFactory;
import twitter4j.User;
import twitter4j.UserStreamListener;
import twitter4j.conf.ConfigurationBuilder;

import java.util.Arrays;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.LinkedBlockingQueue;

/**
 * The Twitter4J and Twitter Streaming API don't lend themselves to mocking. This factory and set of wrappers makes it
 * easier to run Mage without actually hitting real APIs
 */
public class TwitterClients {

    protected static final Logger log = LoggerFactory.getLogger(TwitterClients.class);

    /**
     * Interface for used REST client functionality
     */
    public static interface RestClient {
        ResponseList<DirectMessage> getDirectMessages(Paging paging) throws TwitterException;

        PagableResponseList<User> getFollowers(long cursor) throws TwitterException;

        void createFriendship(long userId) throws TwitterException;
    }

    /**
     * Interface for used streaming client functionality
     */
    public static interface StreamingClient {
        void start(UserStreamListener listener);

        void stop();

        StatsReporter.StatsTracker getStatsTracker();
    }

    /**
     * Default REST client - defers to the actual REST client
     */
    protected static class DefaultRestClient implements RestClient {

        private Twitter m_realClient;
        private static int MAX_RATE_LIMIT_RETRIES = 5;

        public DefaultRestClient(String apiKey, String apiSecret, String authToken, String authSecret) {
            ConfigurationBuilder cb = new ConfigurationBuilder()
                    .setOAuthConsumerKey(apiKey)
                    .setOAuthConsumerSecret(apiSecret)
                    .setOAuthAccessToken(authToken)
                    .setOAuthAccessTokenSecret(authSecret);
            TwitterFactory restClientFactory = new TwitterFactory(cb.build());
            m_realClient = restClientFactory.getInstance();
        }

        @Override
        public ResponseList<DirectMessage> getDirectMessages(Paging paging) throws TwitterException {
            return rateLimited(() -> m_realClient.getDirectMessages(paging));
        }

        @Override
        public PagableResponseList<User> getFollowers(long cursor) throws TwitterException {
            return rateLimited(() -> m_realClient.getFollowersList(m_realClient.getId(), cursor, 200));
        }

        @Override
        public void createFriendship(long userId) throws TwitterException {
            rateLimited(() -> m_realClient.createFriendship(userId));
        }

        @FunctionalInterface
        protected interface RateLimitedOperation<T> {
            T perform() throws TwitterException;
        }

        /**
         * Performs a rate-limited operation. If Twitter API returns a rate limit error, method waits before retrying
         * the operation. Method is static synchronized, synchronizing calls across all client instances.
         */
        protected static synchronized <T> T rateLimited(RateLimitedOperation<T> operation) throws TwitterException {
            int attempt = 1;
            while (true) {
                try {
                    return operation.perform();
                } catch (TwitterException ex) {
                    if (ex.exceededRateLimitation()) {
                        // log as error so goes to Sentry
                        log.error("Exceeded rate limit", ex);

                        if (attempt == MAX_RATE_LIMIT_RETRIES) {
                            // no more retrying so re-throw
                            throw ex;
                        }

                        RateLimitStatus status = ex.getRateLimitStatus();
                        try {
                            Thread.sleep(status.getSecondsUntilReset() * 1000);
                            attempt++;
                        } catch (InterruptedException e) {
                            // weren't able to wait out the rate limit, so re-throw
                            throw ex;
                        }
                    }
                    else {
                        // not a rate limit problem, so re-throw
                        throw ex;
                    }
                }
            }
        }
    }

    /**
     * Stub REST client - NOOPs all around
     */
    protected static class StubRestClient implements RestClient {
        @Override
        public ResponseList<DirectMessage> getDirectMessages(Paging paging) throws TwitterException {
            log.info("FAKED direct message fetch from Twitter API");
            return null;
        }

        @Override
        public PagableResponseList<User> getFollowers(long cursor) throws TwitterException {
            log.info("FAKED follower list fetch from Twitter API");
            return null;
        }

        @Override
        public void createFriendship(long userId) throws TwitterException {
            log.info("FAKED create friendship to user #" + userId);
        }
    }

    /**
     * Default streaming client - connects to Twitter Streaming API
     */
    protected static class DefaultStreamingClient implements StreamingClient {

        private ClientBuilder m_hbcClientBuilder;
        private BlockingQueue<String> m_streamingQueue = new LinkedBlockingQueue<>(10000);
        private Twitter4jUserstreamClient m_realClient;

        public DefaultStreamingClient(String apiKey, String apiSecret, String authToken, String authSecret) {
            Authentication auth = new OAuth1(apiKey, apiSecret, authToken, authSecret);
            UserstreamEndpoint endpoint = new UserstreamEndpoint();
            m_hbcClientBuilder = new ClientBuilder()
                    .hosts(new HttpHosts(Constants.USERSTREAM_HOST))
                    .authentication(auth)
                    .endpoint(endpoint)
                    .processor(new StringDelimitedProcessor(m_streamingQueue));
        }

        @Override
        public void start(UserStreamListener listener) {
            Client hbcClient = m_hbcClientBuilder.build();
            ExecutorService streamingExecutor = Executors.newFixedThreadPool(2);
            m_realClient = new Twitter4jUserstreamClient(hbcClient, m_streamingQueue, Arrays.asList(listener), streamingExecutor);
            m_realClient.connect();
            m_realClient.process();
            m_realClient.process();
        }

        @Override
        public void stop() {
            m_realClient.stop();
        }

        @Override
        public StatsReporter.StatsTracker getStatsTracker() {
            return m_realClient.getStatsTracker();
        }
    }

    /**
     * Stub streaming client - NOOPs all around
     */
    protected static class StubStreamingClient implements StreamingClient {

        private StatsReporter m_statsReporter = new StatsReporter();

        @Override
        public void start(UserStreamListener listener) {
            log.info("FAKED streaming client connect");
        }

        @Override
        public void stop() {
            log.info("FAKED streaming client stop");
        }

        @Override
        public StatsReporter.StatsTracker getStatsTracker() {
            return m_statsReporter.getStatsTracker();
        }
    }

    /**
     * Gets a REST client instance
     * @param apiKey the API key
     * @param apiSecret the API secret token
     * @param authToken the OAuth token
     * @param authSecret the OAuth token secret
     * @param production whether production mode is enabled
     * @return the client
     */
    public static RestClient getRestClient(String apiKey, String apiSecret, String authToken, String authSecret, boolean production) {
        return production ? new DefaultRestClient(apiKey, apiSecret, authToken, authSecret) : new StubRestClient();
    }

    /**
     * Gets a streaming API client instance
     * @param apiKey the API key
     * @param apiSecret the API secret token
     * @param authToken the OAuth token
     * @param authSecret the OAuth token secret
     * @param production whether production mode is enabled
     * @return the client
     */
    public static StreamingClient getStreamingClient(String apiKey, String apiSecret, String authToken, String authSecret, boolean production) {
        return production ? new DefaultStreamingClient(apiKey, apiSecret, authToken, authSecret) : new StubStreamingClient();
    }
}
