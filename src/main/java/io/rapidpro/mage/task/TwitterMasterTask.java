package io.rapidpro.mage.task;

import com.google.common.collect.ImmutableMultimap;
import io.rapidpro.mage.twitter.TwitterManager;
import io.dropwizard.servlets.tasks.Task;

import java.io.PrintWriter;

/**
 * Task to make this Mage instance become Twitter master
 */
public class TwitterMasterTask extends Task {

    private final TwitterManager m_twitter;

    public TwitterMasterTask(TwitterManager twitter) {
        super("twitter-master");

        this.m_twitter = twitter;
    }

    /**
     * @see Task#execute(com.google.common.collect.ImmutableMultimap, java.io.PrintWriter)
     */
    @Override
    public void execute(ImmutableMultimap<String, String> params, PrintWriter output) throws Exception {
        output.println("Becoming master...");

        m_twitter.becomeMaster();

        while (!m_twitter.isMaster()) {
            Thread.sleep(10);
        }

        output.println("Done!");
    }
}