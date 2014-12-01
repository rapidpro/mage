package io.rapidpro.mage.util;

import com.github.segmentio.Analytics;
import com.github.segmentio.models.Context;
import com.github.segmentio.models.Options;
import com.github.segmentio.models.Props;
import io.rapidpro.mage.MageConstants;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Analytics wrapper for segment.io
 */
public class AnalyticsUtils {

    protected static final Logger log = LoggerFactory.getLogger(AnalyticsUtils.class);

    private static boolean s_initialized = false;

    private static String s_hostname = null;

    /**
     * Initializes the analytics system. If not initialized then tracking calls won't actually do anything
     * @param hostname the server hostname
     * @param writeKey the segment.io write key
     */
    public static void initialize(String hostname, String writeKey) {
        s_hostname = hostname;

        Analytics.initialize(writeKey);
        s_initialized = true;

        log.info("Initialized analytics");
    }

    /**
     * Tracks an event
     * @param event the event
     */
    public static void track(String event) {
        log.debug(event);

        // don't really track anything if we're not initialized
        if (!s_initialized) {
            return;
        }

        Context context = new Context();
        context.put("source", s_hostname);
        Options options = new Options();
        options.setContext(context);

        Analytics.getDefaultClient().track(MageConstants.ServiceUser.ANALYTICS_ID, event, new Props(), options);
    }
}