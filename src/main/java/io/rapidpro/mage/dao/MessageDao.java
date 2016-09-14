package io.rapidpro.mage.dao;

import io.rapidpro.mage.core.CallbackContext;
import io.rapidpro.mage.core.ChannelType;
import io.rapidpro.mage.core.Direction;
import io.rapidpro.mage.core.IncomingContext;
import io.rapidpro.mage.core.Status;
import io.rapidpro.mage.dao.mapper.BindEnum;
import org.skife.jdbi.v2.DefaultMapper;
import org.skife.jdbi.v2.sqlobject.Bind;
import org.skife.jdbi.v2.sqlobject.GetGeneratedKeys;
import org.skife.jdbi.v2.sqlobject.SqlBatch;
import org.skife.jdbi.v2.sqlobject.SqlQuery;
import org.skife.jdbi.v2.sqlobject.SqlUpdate;
import org.skife.jdbi.v2.sqlobject.customizers.Mapper;
import org.skife.jdbi.v2.sqlobject.stringtemplate.UseStringTemplate3StatementLocator;
import org.skife.jdbi.v2.unstable.BindIn;
import org.skife.jdbi.v2.util.IntegerMapper;
import org.skife.jdbi.v2.util.LongMapper;
import org.skife.jdbi.v2.util.StringMapper;

import java.util.Date;
import java.util.List;
import java.util.Map;

/**
 * DAO for message operations
 */
@UseStringTemplate3StatementLocator // required for @BindIn
public interface MessageDao {

    @SqlQuery(
            "SELECT m.id AS message_id, m.status AS message_status, m.broadcast_id AS broadcast_id, o.id AS org_id, o.config AS org_config " +
            "FROM " + Table.MESSAGE + " m " +
            "INNER JOIN " + Table.ORG + " o ON o.id = m.org_id " +
            "WHERE m.id = :messageId"
    )
    CallbackContext getCallbackContext(@Bind("messageId") int messageId);

    @SqlQuery(
            "SELECT m.id AS message_id, m.status AS message_status, m.broadcast_id AS broadcast_id, o.id AS org_id, o.config AS org_config " +
            "FROM " + Table.MESSAGE + " m " +
            "INNER JOIN " + Table.ORG + " o ON o.id = m.org_id " +
            "INNER JOIN " + Table.CHANNEL + " c ON c.id = m.channel_id " +
            "WHERE c.uuid = :channelUuid AND c.channel_type = :channelType AND c.is_active = TRUE AND m.external_id = :externalId"
    )
    CallbackContext getCallbackContext(@Bind("channelUuid") String channelUuid, @BindEnum("channelType") ChannelType channelType, @Bind("externalId") String externalId);

    @SqlQuery(
            "SELECT c.id AS channel_id, c.country AS channel_country, c.channel_type AS channel_type, o.id AS org_id, o.config AS org_config " +
            "FROM " + Table.CHANNEL + " c " +
            "INNER JOIN " + Table.ORG + " o ON o.id = c.org_id " +
            "WHERE c.address = :address AND c.channel_type = :channelType AND c.is_active = TRUE"
    )
    IncomingContext getIncomingContextByChannelAddressAndType(@BindEnum("channelType") ChannelType channelType, @Bind("address") String address);

    @SqlQuery(
            "SELECT c.id AS channel_id, c.country AS channel_country, c.channel_type AS channel_type, o.id AS org_id, o.config AS org_config " +
            "FROM " + Table.CHANNEL + " c " +
            "INNER JOIN " + Table.ORG + " o ON o.id = c.org_id " +
            "WHERE c.uuid = :channelUuid AND c.channel_type = :channelType AND c.is_active = TRUE"
    )
    IncomingContext getIncomingContextByChannelUuidAndType(@Bind("channelUuid") String channelUuid, @BindEnum("channelType") ChannelType channelType);

    @SqlQuery(
            "SELECT id " +
            "FROM " + Table.MESSAGE + " " +
            "WHERE text = :text AND created_on = :createdOn AND contact_id = :contactId AND direction = :direction"
    )
    @Mapper(IntegerMapper.class)
    Integer getMessage(@Bind("text") String text, @Bind("createdOn") Date createdOn, @Bind("contactId") int contactId, @BindEnum("direction") Direction direction);

    @SqlQuery(
            "SELECT external_id " +
            "FROM " + Table.MESSAGE + " " +
            "WHERE channel_id = :channelId AND direction = :direction " +
            "ORDER BY id DESC, created_on DESC LIMIT 1" // see http://stackoverflow.com/questions/21385555/postgresql-query-very-slow-with-limit-1
    )
    @Mapper(StringMapper.class)
    String getLastExternalId(@Bind("channelId") int channelId, @BindEnum("direction") Direction direction);

    @SqlUpdate(
            "INSERT INTO " + Table.MESSAGE + " (channel_id, contact_id, contact_urn_id, text, direction, status, org_id, created_on, queued_on, has_template_error, msg_type, msg_count, external_id, error_count, next_attempt, visibility, priority) " +
            "VALUES(:channelId, :contactId, :contactUrnId, :text, 'I', 'P', :orgId, :createdOn, :queuedOn, FALSE, NULL, 1, :externalId, 0, NOW(), 'V', :priority)"
    )
    @GetGeneratedKeys
    int insertIncoming(@Bind("channelId") Integer channelId,
                       @Bind("contactId") Integer contactId,
                       @Bind("contactUrnId") Integer contactUrnId,
                       @Bind("text") String text,
                       @Bind("orgId") Integer orgId,
                       @Bind("createdOn") Date createdOn,
                       @Bind("queuedOn") Date queuedOn,
                       @Bind("externalId") String externalId,
                       @Bind("priority") int priority);

    /**
     * Updates a batch of messages to status SENT if they are currently PENDING, QUEUED or WIRED
     * @param messageIds the message ids
     * @param dates the sent on dates
     */
    @SqlBatch("UPDATE " + Table.MESSAGE + " SET status = 'S', sent_on = :sentOn WHERE status IN ('P', 'Q', 'W') AND id = :messageId")
    void updateBatchToSent(@Bind("messageId") Iterable<Integer> messageIds, @Bind("sentOn") Iterable<Date> dates);

    /**
     * Updates a batch of messages to status DELIVERED
     * @param messageIds the message ids
     * @param dates the delivered on dates
     */
    @SqlBatch("UPDATE " + Table.MESSAGE + " SET status = 'D', modified_on = :deliveredOn WHERE id = :messageId")
    void updateBatchToDelivered(@Bind("messageId") Iterable<Integer> messageIds, @Bind("deliveredOn") Iterable<Date> dates);

    /**
     * Updates a batch of messages to status FAILED
     * @param messageIds the message ids
     */
    @SqlUpdate("UPDATE " + Table.MESSAGE + " SET status = 'F' WHERE id IN (<messageIds>)")
    void updateBatchToFailed(@BindIn("messageIds") Iterable<Integer> messageIds);

    @SqlQuery(
            "SELECT m.status, COUNT(m.id)" +
            "FROM " + Table.MESSAGE + " m " +
            "INNER JOIN " + Table.BROADCAST + " b ON b.id = m.broadcast_id " +
            "WHERE b.id = :broadcastId " +
            "GROUP BY m.status"
    )
    @Mapper(DefaultMapper.class)
    List<Map<String, Object>> getBroadcastStatusCounts(@Bind("broadcastId") int broadcastId);

    @SqlUpdate("UPDATE " + Table.BROADCAST + " SET status = :status WHERE id = :broadcastId")
    void updateBroadcastStatus(@Bind("broadcastId") int broadcastId, @BindEnum("status") Status status);
}