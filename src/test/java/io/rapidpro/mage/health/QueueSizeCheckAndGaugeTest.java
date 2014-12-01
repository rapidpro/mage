package io.rapidpro.mage.health;

import io.rapidpro.mage.test.BaseServicesTest;
import org.junit.Test;

import static org.hamcrest.Matchers.is;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.health.QueueSizeCheckAndGauge}
 */
public class QueueSizeCheckAndGaugeTest extends BaseServicesTest {

    @Test
    public void getValueAndCheck() throws Exception {
        QueueSizeCheckAndGauge m_gauge = new QueueSizeCheckAndGauge(getCache(), "test_queue", 3);

        assertThat(m_gauge.getValue(), is(0l));
        assertThat(m_gauge.check().isHealthy(), is(true));

        getCache().listRPush("test_queue", "a");
        getCache().listRPush("test_queue", "b");
        getCache().listRPush("test_queue", "c");

        assertThat(m_gauge.getValue(), is(3l));
        assertThat(m_gauge.check().isHealthy(), is(true));

        getCache().listRPush("test_queue", "d");

        assertThat(m_gauge.getValue(), is(4l));
        assertThat(m_gauge.check().isHealthy(), is(false));
    }
}