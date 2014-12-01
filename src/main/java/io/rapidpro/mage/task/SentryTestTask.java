package io.rapidpro.mage.task;

import com.google.common.collect.ImmutableMultimap;
import io.dropwizard.servlets.tasks.Task;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.PrintWriter;

/**
 * Task to test Sentry
 */
public class SentryTestTask extends Task {

    protected static final Logger log = LoggerFactory.getLogger(SentryTestTask.class);

    public SentryTestTask() {
        super("sentry-test");
    }

    /**
     * @see io.dropwizard.servlets.tasks.Task#execute(com.google.common.collect.ImmutableMultimap, java.io.PrintWriter)
     */
    @Override
    public void execute(ImmutableMultimap<String, String> params, PrintWriter output) throws Exception {
        output.println("Testing sentry...");

        try {
            throw new RuntimeException("This is an exception");
        }
        catch (Exception e) {
            log.error("Testing Sentry", e);
        }

        output.println("Done!");
    }
}