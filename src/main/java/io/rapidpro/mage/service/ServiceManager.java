package io.rapidpro.mage.service;

import io.rapidpro.mage.cache.Cache;
import io.rapidpro.mage.dao.ChannelDao;
import io.rapidpro.mage.dao.ContactDao;
import io.rapidpro.mage.dao.MessageDao;
import io.rapidpro.mage.dao.UserDao;
import io.rapidpro.mage.temba.TembaManager;
import io.dropwizard.lifecycle.Managed;
import org.skife.jdbi.v2.DBI;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Managed holder class for all database resources and services
 */
public class ServiceManager implements Managed {

    protected static final Logger log = LoggerFactory.getLogger(ServiceManager.class);

    private final DBI m_dbi;
    private final Cache m_cache;
    private final TembaManager m_temba;
    private final boolean m_production;

    private MessageService m_messageService;
    private ContactService m_contactService;
    private ChannelService m_channelService;
    private UserService m_userService;

    private int m_serviceUserId;

    public ServiceManager(DBI dbi, Cache cache, TembaManager temba, boolean production) {
        m_dbi = dbi;
        m_cache = cache;
        m_temba = temba;
        m_production = production;
    }

    /**
     * @see io.dropwizard.lifecycle.Managed#start()
     */
    @Override
    public void start() throws Exception {
        m_messageService = new MessageService(this, m_cache, m_temba, m_dbi.onDemand(MessageDao.class));
        m_contactService = new ContactService(this, m_cache, m_dbi.onDemand(ContactDao.class));
        m_channelService = new ChannelService(this, m_cache, m_dbi.onDemand(ChannelDao.class));
        m_userService = new UserService(this, m_cache, m_dbi.onDemand(UserDao.class));

        // get or create user for saving data
        m_serviceUserId = m_userService.getOrCreateServiceUser();

        log.info("Created services (user=#" + m_serviceUserId + ")");
    }

    /**
     * @see io.dropwizard.lifecycle.Managed#stop()
     */
    @Override
    public void stop() throws Exception {
        log.debug("Destroyed services");
    }

    public MessageService getMessageService() {
        return m_messageService;
    }

    public ContactService getContactService() {
        return m_contactService;
    }

    public ChannelService getChannelService() {
        return m_channelService;
    }

    public UserService getUserService() {
        return m_userService;
    }

    /**
     * Gets the user id to use for saving data
     * @return the user id
     */
    public int getServiceUserId() {
        return m_serviceUserId;
    }

    public boolean isProduction() {
        return m_production;
    }
}