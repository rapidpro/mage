package io.rapidpro.mage;

/**
 * General server constants
 */
public class MageConstants {

    /**
     * Service user properties
     */
    public static class ServiceUser {
        public static final String USERNAME = "mage";
        public static final String EMAIL = "code@nyaruka.com";
        public static final String ANALYTICS_ID = "System";
    }

    /**
     * Cache key names
     */
    public static class CacheKey {
        public static final String MESSAGE_UPDATE_QUEUE = "mage:queue:message_updates";
        public static final String TEMBA_REQUEST_QUEUE = "mage:queue:temba_requests";

        public static final String CALLBACK_CONTEXT_PREFIX = "mage:cache:callback_context:";
        public static final String INCOMING_CONTEXT_PREFIX = "mage:cache:incoming_context:";

        public static final String TWITTER_MASTER_LOCK = "mage:lock:twitter_master";
        public static final String TWITTER_STREAMOP_QUEUE = "mage:queue:twitter_streamops";
    }

    /**
     * Cache key time-to-live values (milliseconds)
     */
    public static class CacheTtl {
        public static final long INCOMING_CONTEXT = 60 * 60 * 1000; // 1 hour
        public static final long CALLBACK_CONTEXT = 60 * 60 * 1000; // 1 hour
    }
}