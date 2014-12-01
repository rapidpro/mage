package io.rapidpro.mage.health;

import com.codahale.metrics.health.HealthCheck;

import java.util.Collection;

/**
 * Health check which combines a set of child health checks
 */
public class CombinationHealthCheck extends HealthCheck {

    private Collection<? extends HealthCheck> m_checks;

    public CombinationHealthCheck(Collection<? extends HealthCheck> checks) {
        this.m_checks = checks;
    }

    /**
     * @see com.codahale.metrics.health.HealthCheck#check()
     */
    @Override
    protected Result check() throws Exception {
        for (HealthCheck child : m_checks) {
            Result result = child.execute();
            if (!result.isHealthy()) {
                return result;
            }
        }

        return Result.healthy();
    }
}