package io.rapidpro.mage.test;

import io.rapidpro.mage.twitter.TwitterManager;
import org.junit.AfterClass;
import org.junit.BeforeClass;
import org.junit.Ignore;

/**
 * Base class for tests that require a Twitter manager node
 */
@Ignore
public class BaseTwitterTest extends BaseServicesTest {

    private static TwitterManager s_twitter;

    @BeforeClass
    public static void setupTwitter() throws Exception {
        s_twitter = new TwitterManager(getServices(), getCache(), getTemba(), "abcd", "1234");
        s_twitter.start();

        // wait for this node to become master...
        while (!s_twitter.isMaster()) {
            Thread.sleep(10);
        }
    }

    @AfterClass
    public static void teardownTwitter() throws Exception {
        s_twitter.stop();
    }

    public static TwitterManager getTwitter() {
        return s_twitter;
    }
}