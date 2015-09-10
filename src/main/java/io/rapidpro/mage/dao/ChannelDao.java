package io.rapidpro.mage.dao;

import io.rapidpro.mage.core.ChannelContext;
import io.rapidpro.mage.core.ChannelType;
import io.rapidpro.mage.dao.mapper.BindEnum;
import org.skife.jdbi.v2.sqlobject.Bind;
import org.skife.jdbi.v2.sqlobject.SqlQuery;
import org.skife.jdbi.v2.sqlobject.SqlUpdate;

import java.util.List;

/**
 * DAO for channel operations
 */
public interface ChannelDao {

    @SqlQuery(
            "SELECT c.id AS channel_id, c.uuid AS channel_uuid, c.address AS channel_address, c.channel_type AS channel_type, c.config AS channel_config, c.bod AS channel_bod, o.id AS org_id, o.is_anon AS org_anon " +
            "FROM " + Table.CHANNEL + " c " +
            "INNER JOIN " + Table.ORG + " o ON o.id = c.org_id " +
            "WHERE c.is_active = TRUE AND c.channel_type = :channelType"
    )
    List<ChannelContext> getChannelsByType(@BindEnum("channelType") ChannelType type);

    @SqlQuery(
            "SELECT c.id AS channel_id, c.uuid AS channel_uuid, c.address AS channel_address, c.channel_type AS channel_type, c.config AS channel_config, c.bod AS channel_bod, o.id AS org_id, o.is_anon AS org_anon " +
            "FROM " + Table.CHANNEL + " c " +
            "INNER JOIN " + Table.ORG + " o ON o.id = c.org_id " +
            "WHERE c.uuid = :channelUuid"
    )
    ChannelContext getChannelByUuid(@Bind("channelUuid") String uuid);

    @SqlUpdate("UPDATE " + Table.CHANNEL + " SET bod = :bod WHERE id = :channelId")
    void updateChannelBod(@Bind("channelId") int channelId, @Bind("bod") String bod);
}