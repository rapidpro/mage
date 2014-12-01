package io.rapidpro.mage.service;

import io.rapidpro.mage.cache.Cache;

/**
 * Abstract base class for services
 */
public abstract class BaseService<D> {

    private ServiceManager m_manager;

    private Cache m_cache;

    private D m_dao;

    protected BaseService(ServiceManager manager, Cache cache, D dao) {
        m_manager = manager;
        m_cache = cache;
        m_dao = dao;
    }

    /**
     * Gets the service manager which provides access to all other services
     * @return the service manager
     */
    public ServiceManager getManager() {
        return m_manager;
    }

    public Cache getCache() {
        return m_cache;
    }

    public D getDao() {
        return m_dao;
    }
}