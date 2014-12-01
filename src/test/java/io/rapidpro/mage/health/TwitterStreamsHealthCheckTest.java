package io.rapidpro.mage.health;

import io.rapidpro.mage.test.BaseTwitterTest;
import org.junit.Test;

import static org.hamcrest.Matchers.is;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.health.TwitterStreamsHealthCheck}
 */
public class TwitterStreamsHealthCheckTest extends BaseTwitterTest {

    private final TwitterStreamsHealthCheck m_check = new TwitterStreamsHealthCheck(getTwitter());

    /**
     * @see TwitterStreamsHealthCheck#check()
     */
    @Test
    public void check_shouldReturnHealthyIfNoHttpErrors() throws Exception {
        assertThat(m_check.check().isHealthy(), is(true));
    }

    /**
     * @see TwitterStreamsHealthCheck#check()
     */
    /*@Test
    public void check_shouldReturnUnealthyIfAny400Errors() throws Exception {
        getStatsReporter().incrNum400s();

        assertThat(m_check.check().isHealthy(), is(false));
    }*/

    /**
     * @see TwitterStreamsHealthCheck#check()
     */
    /*@Test
    public void check_shouldReturnUnealthyIfAny500Errors() throws Exception {
        getStatsReporter().incrNum500s();

        assertThat(m_check.check().isHealthy(), is(false));
    }*/
}