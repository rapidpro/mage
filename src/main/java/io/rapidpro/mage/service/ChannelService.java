package io.rapidpro.mage.service;

import io.rapidpro.mage.cache.Cache;
import io.rapidpro.mage.core.ChannelContext;
import io.rapidpro.mage.core.ChannelType;
import io.rapidpro.mage.dao.ChannelDao;

import java.util.List;

/**
 * Service for user operations
 */
public class ChannelService extends BaseService<ChannelDao> {

    public ChannelService(ServiceManager manager, Cache cache, ChannelDao dao) {
        super(manager, cache, dao);
    }

    /**
     * Gets all channels of the given type
     * @param type the channel type e,g. NEXMO
     * @return the channel context
     */
    public List<ChannelContext> getChannelsByType(ChannelType type) {
        return getDao().getChannelsByType(type);
    }

    /**
     * Gets the channel with the given UUID
     * @param uuid the channel UUID
     * @return the channel context
     */
    public ChannelContext getChannelByUuid(String uuid) {
        return getDao().getChannelByUuid(uuid);
    }

    /**
     * Updates the BOD value for the given channel
     * @param channelId the channel id
     * @param bod the bod value
     */
    public void updateChannelBod(int channelId, String bod) {
        getDao().updateChannelBod(channelId, bod);
    }
}