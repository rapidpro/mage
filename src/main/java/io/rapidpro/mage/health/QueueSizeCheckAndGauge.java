package io.rapidpro.mage.health;

import com.codahale.metrics.Gauge;
import com.codahale.metrics.health.HealthCheck;
import io.rapidpro.mage.cache.Cache;

/**
 * Gauge metric and health check based on a list size in the cache
 */
public class QueueSizeCheckAndGauge extends HealthCheck implements Gauge<Long> {

    private final Cache m_cache;

    private final String m_key;

    private final long m_maxHealthySize;

    public QueueSizeCheckAndGauge(Cache cache, String key, long maxHealthySize) {
        m_cache = cache;
        m_key = key;
        m_maxHealthySize = maxHealthySize;
    }

    /**
     * @see com.codahale.metrics.Gauge#getValue()
     */
    @Override
    public Long getValue() {
        return m_cache.listLength(m_key);
    }

    /**
     * @see com.codahale.metrics.health.HealthCheck#check()
     */
    @Override
    protected Result check() throws Exception {
        long size = getValue();
        String message = "size=" + size + ", threshold=" + m_maxHealthySize;

        if (size > m_maxHealthySize) {
            return Result.unhealthy(message);
        }
        return Result.healthy(message);
    }
}
