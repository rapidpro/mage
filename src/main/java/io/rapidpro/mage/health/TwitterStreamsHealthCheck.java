package io.rapidpro.mage.health;

import com.codahale.metrics.health.HealthCheck;
import io.rapidpro.mage.twitter.TwitterManager;
import io.rapidpro.mage.twitter.TwitterStream;
import com.twitter.hbc.core.StatsReporter;

/**
 * Health check to look for Twitter streams on this node with 500/400 errors
 */
public class TwitterStreamsHealthCheck extends HealthCheck {

    private final TwitterManager m_manager;

    public TwitterStreamsHealthCheck(TwitterManager manager) {
        m_manager = manager;
    }

    /**
     * @see com.codahale.metrics.health.HealthCheck#check()
     */
    @Override
    protected Result check() throws Exception {
        int errors = 0;
        for (TwitterStream stream : m_manager.getNodeStreams()) {
            StatsReporter.StatsTracker stats = stream.getStreamingStatistics();
            errors += stats.getNum400s();
            errors += stats.getNum500s();
        }

        if (errors == 0) {
            return Result.healthy();
        } else {
            return Result.unhealthy("Twitter streams have recorded " + errors + " errored requests");
        }
    }
}