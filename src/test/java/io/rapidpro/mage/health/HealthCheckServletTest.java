package io.rapidpro.mage.health;

import com.codahale.metrics.health.HealthCheck;
import com.codahale.metrics.health.HealthCheckRegistry;
import io.rapidpro.mage.test.BaseServicesTest;
import org.junit.Test;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import java.io.PrintWriter;
import java.io.StringWriter;

import static org.hamcrest.Matchers.is;
import static org.junit.Assert.assertThat;
import static org.mockito.Mockito.*;

/**
 * Tests for {@link io.rapidpro.mage.health.HealthCheckServlet}
 */
public class HealthCheckServletTest extends BaseServicesTest {

    class TestCheck extends HealthCheck {
        boolean healthy = true;

        @Override
        protected Result check() throws Exception {
            return healthy ? Result.healthy() : Result.unhealthy("problem");
        }

        void setHealthy(boolean healthy) {
            this.healthy = healthy;
        }
    }

    @Test
    public void doGet() throws Exception {
        TestCheck testCheck1 = new TestCheck();
        TestCheck testCheck2 = new TestCheck();
        HealthCheckRegistry healthCheckRegistry = new HealthCheckRegistry();
        healthCheckRegistry.register("check1", testCheck1);
        healthCheckRegistry.register("check2", testCheck2);

        HealthCheckServlet servlet = new HealthCheckServlet(healthCheckRegistry);

        HttpServletRequest request = mock(HttpServletRequest.class);
        HttpServletResponse response = mock(HttpServletResponse.class);

        StringWriter writer = new StringWriter();
        when(response.getWriter()).thenReturn(new PrintWriter(writer));

        servlet.doGet(request, response);

        assertThat(writer.toString(), is("check1: OK\ncheck2: OK\n"));
        verify(response).setStatus(200);

        // simulate one of the checks now failing
        testCheck1.setHealthy(false);

        response = mock(HttpServletResponse.class);

        writer = new StringWriter();
        when(response.getWriter()).thenReturn(new PrintWriter(writer));

        servlet.doGet(request, response);

        assertThat(writer.toString(), is("check1: ERROR (problem)\ncheck2: OK\n"));
        verify(response).setStatus(503);
    }
}
