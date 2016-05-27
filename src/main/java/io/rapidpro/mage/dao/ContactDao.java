package io.rapidpro.mage.dao;

import io.rapidpro.mage.core.ContactContext;
import org.skife.jdbi.v2.sqlobject.Bind;
import org.skife.jdbi.v2.sqlobject.GetGeneratedKeys;
import org.skife.jdbi.v2.sqlobject.SqlQuery;
import org.skife.jdbi.v2.sqlobject.SqlUpdate;

/**
 * DAO for contact operations
 */
public interface ContactDao {

    @SqlQuery(
            "SELECT cu.id AS contact_urn_id, c.id AS contact_id, c.is_blocked AS is_blocked, r.id AS channel_id " +
            "FROM " + Table.CONTACT_URN + " cu " +
            "LEFT OUTER JOIN " + Table.CONTACT + " c ON c.id = cu.contact_id " +
            "LEFT OUTER JOIN " + Table.CHANNEL + " r ON r.id = cu.channel_id " +
            "WHERE cu.org_id = :orgId AND cu.urn = :urn"
    )
    ContactContext getContactContextByOrgAndUrn(@Bind("orgId") int orgId, @Bind("urn") String urn);

    @SqlUpdate(
            "INSERT INTO " + Table.CONTACT + " (org_id, name, is_active, created_by_id, created_on, modified_by_id, modified_on, is_test, is_blocked, is_stopped, uuid) " +
            "VALUES(:orgId, :name, TRUE, :userId, NOW(), :userId, NOW(), FALSE, FALSE, FALSE, :uuid)"
    )
    @GetGeneratedKeys
    int insertContact(@Bind("userId") int userId, @Bind("orgId") int orgId, @Bind("name") String name, @Bind("uuid") String uuid);

    @SqlUpdate(
            "INSERT INTO " + Table.CONTACT_URN + " (org_id, contact_id, urn, scheme, path, priority, channel_id) " +
            "VALUES(:orgId, :contactId, :urn, :scheme, :path, :priority, :channelId)"
    )
    @GetGeneratedKeys
    int insertContactUrn(@Bind("orgId") int orgId,
                         @Bind("contactId") int contactId,
                         @Bind("urn") String urn,
                         @Bind("scheme") String scheme,
                         @Bind("path") String path,
                         @Bind("priority") int priority,
                         @Bind("channelId") int channelId);

    @SqlUpdate("UPDATE " + Table.CONTACT_URN + " SET channel_id = :channelId, contact_id = :contactId WHERE id = :contactUrnId")
    void updateContactUrn(@Bind("contactUrnId") int contactUrnId,
                          @Bind("contactId") Integer contactId,
                          @Bind("channelId") Integer channelId);
}