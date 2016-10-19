package io.rapidpro.mage.health;

import com.codahale.metrics.health.HealthCheck;
import com.codahale.metrics.health.HealthCheckRegistry;

import javax.servlet.ServletException;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Map;

/**
 * We don't allow the admin connector health checks to be publicly accessible so this servlet provides a limited status
 * report which can be shared publicly and made accessible to up-time checkers.
 */
public class HealthCheckServlet extends HttpServlet {

    private HealthCheckRegistry m_healthCheckRegistry;

    public HealthCheckServlet(HealthCheckRegistry healthCheckRegistry) {
        m_healthCheckRegistry = healthCheckRegistry;
    }

    @Override
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws ServletException, IOException {
        Map<String, HealthCheck.Result> results = m_healthCheckRegistry.runHealthChecks();
        boolean hasError = false;

        for (Map.Entry<String, HealthCheck.Result> entry : results.entrySet()) {
            HealthCheck.Result result = entry.getValue();
            String status;

            if (result.isHealthy()) {
                status = "OK";
            } else {
                status = "ERROR";
                hasError = true;
            }

            resp.getWriter().print(entry.getKey() + ": " + status);

            if (result.getMessage() != null) {
                resp.getWriter().print(" (" + result.getMessage() + ")");
            }

            resp.getWriter().println();
        }

        resp.setStatus(hasError ? HttpServletResponse.SC_SERVICE_UNAVAILABLE : HttpServletResponse.SC_OK);
    }
}