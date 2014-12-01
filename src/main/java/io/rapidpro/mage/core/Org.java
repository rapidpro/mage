package io.rapidpro.mage.core;

import io.rapidpro.mage.cache.Cache;

/**
 * Provides some functionality similar to the Temba Org class
 */
public class Org {

    public static enum OrgLock {
        CONTACTS,
        CHANNELS,
        CREDITS,
        FIELD
    }

    // cache keys
    public static final String LOCK_KEY = "org:%d:lock:%s";

    // cache TTLs
    public static final long LOCK_TTL = 60 * 1000;  // 1 minute

    private int m_orgId;
    private Cache m_cache;

    public Org(int orgId, Cache cache) {
        m_orgId = orgId;
        m_cache = cache;
    }

    /**
     * Performs an operation with an org-level contacts lock
     * @param lock the lock type
     * @param operation the operation
     * @return the operation result
     */
    public <T> T withLockOn(OrgLock lock, Cache.OperationWithResource<T> operation) {
        String lockName = getLockKey(lock, null);
        return m_cache.performWithLock(lockName, Org.LOCK_TTL, operation);
    }

    /**
     * Gets the cache key to use for the given lock
     * @param lock the lock type
     * @param qualifier the qualifier (e.g. field key)
     * @return the cache key
     */
    protected String getLockKey(OrgLock lock, String qualifier) {
        if (qualifier != null) {
            return String.format(LOCK_KEY + ":%s", m_orgId, lock.name().toLowerCase(), qualifier);
        }
        else {
            return String.format(LOCK_KEY, m_orgId, lock.name().toLowerCase());
        }
    }
}