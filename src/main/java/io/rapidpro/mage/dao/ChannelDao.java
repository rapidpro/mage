package io.rapidpro.mage.dao;

import io.rapidpro.mage.core.ChannelContext;
import io.rapidpro.mage.core.ChannelType;
import io.rapidpro.mage.dao.mapper.BindEnum;
import org.skife.jdbi.v2.sqlobject.Bind;
import org.skife.jdbi.v2.sqlobject.SqlQuery;

import java.util.List;

/**
 * DAO for channel operations
 */
public interface ChannelDao {

    @SqlQuery(
            "SELECT c.id AS channel_id, c.uuid AS channel_uuid, c.channel_type AS channel_type, c.config AS channel_config, c.org_id AS org_id " +
            "FROM " + Table.CHANNEL + " c " +
            "WHERE c.is_active = TRUE AND c.channel_type = :channelType"
    )
    List<ChannelContext> getChannelsByType(@BindEnum("channelType") ChannelType type);

    @SqlQuery(
            "SELECT c.id AS channel_id, c.uuid AS channel_uuid, c.channel_type AS channel_type, c.config AS channel_config, c.org_id AS org_id " +
            "FROM " + Table.CHANNEL + " c " +
            "WHERE c.uuid = :channelUuid"
    )
    ChannelContext getChannelByUuid(@Bind("channelUuid") String uuid);
}