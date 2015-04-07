package io.rapidpro.mage.twitter;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import twitter4j.RateLimitStatus;
import twitter4j.TwitterException;

/**
 *
 */
public class TwitterExecutor {

    protected static final Logger log = LoggerFactory.getLogger(TwitterStream.class);

    @FunctionalInterface
    public interface OperationWithRateLimiting {
        void perform() throws TwitterException;
    }

    public static void performWithRateLimiting(OperationWithRateLimiting operation) {
        while (true) {
            try {
                operation.perform();
                break;
            }
            catch (TwitterException ex) {
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
}
