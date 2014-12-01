package io.rapidpro.mage.health;

import com.codahale.metrics.health.HealthCheck;
import io.rapidpro.mage.test.BaseServicesTest;
import org.junit.Test;

import java.util.Arrays;

import static org.hamcrest.Matchers.is;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.health.CombinationHealthCheck}
 */
public class CombinationHealthCheckTest extends BaseServicesTest {

    /**
     * @see io.rapidpro.mage.health.CombinationHealthCheck#check()
     */
    @Test
    public void check() throws Exception {
        MockCheck check1 = new MockCheck(true, "I am fine");
        MockCheck check2 = new MockCheck(true, "I am also fine");
        MockCheck check3 = new MockCheck(false, "Not so fine");
        MockCheck check4 = new MockCheck(false, "Also not so fine");

        CombinationHealthCheck combo1 = new CombinationHealthCheck(Arrays.asList(check1, check2));
        assertThat(combo1.check().isHealthy(), is(true));
        assertThat(combo1.check().getMessage(), nullValue());

        CombinationHealthCheck combo2 = new CombinationHealthCheck(Arrays.asList(check1, check2, check3, check4));
        assertThat(combo2.check().isHealthy(), is(false));
        assertThat(combo2.check().getMessage(), is("Not so fine"));
    }

    protected class MockCheck extends HealthCheck {
        private boolean m_result = true;
        private String m_message = "";

        public MockCheck(boolean result, String message) {
            m_result = result;
            m_message = message;
        }

        @Override
        protected Result check() throws Exception {
            return m_result ? Result.healthy(m_message) : Result.unhealthy(m_message);
        }
    }
}