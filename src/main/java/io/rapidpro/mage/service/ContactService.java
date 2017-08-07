package io.rapidpro.mage.service;

import io.rapidpro.mage.cache.Cache;
import io.rapidpro.mage.core.ContactContext;
import io.rapidpro.mage.core.ContactUrn;
import io.rapidpro.mage.core.Org;
import io.rapidpro.mage.dao.ContactDao;
import org.apache.commons.lang3.ObjectUtils;

import java.util.UUID;

/**
 * Service for contact operations
 */
public class ContactService extends BaseService<ContactDao> {

    public ContactService(ServiceManager manager, Cache cache, ContactDao dao) {
        super(manager, cache, dao);
    }

    /**
     * Gets an existing contact or creates a new one. Operation is wrapped in a cache level lock
     * @param orgId the org id
     * @param urn the contact URN
     * @param channelId the last used channel id
     * @param name the contact name (only used if new contact is created)
     * @return the contact id
     */
    public ContactContext getOrCreateContact(int orgId, ContactUrn urn, Integer channelId, String name) {
        Org org = new Org(orgId, getCache());

        return org.withLockOn(Org.OrgLock.CONTACTS, resource -> {
            // look up the contact (with channel)
            ContactContext contactContext = getDao().getContactContextByOrgAndUrn(orgId, urn.toIdentity());

            int userId = getManager().getServiceUserId();

            if (contactContext != null) {
                Integer contactId = contactContext.getContactId();
                boolean isOrphan = contactId == null; // does URN have no contact? (i.e. contact was deactivated)
                boolean updateChannel = ObjectUtils.notEqual(contactContext.getChannelId(), channelId);

                if (isOrphan) {
                    contactId = getDao().insertContact(userId, orgId, name, UUID.randomUUID().toString());
                    contactContext.setContactId(contactId);
                    contactContext.setNewContact(true);
                }

                contactContext.setChannelId(channelId);

                if (isOrphan || updateChannel) {
                    getDao().updateContactUrn(
                            contactContext.getContactUrnId(),
                            contactContext.getContactId(),
                            contactContext.getChannelId()
                    );
                }
            } else {
                int contactId = getDao().insertContact(userId, orgId, name, UUID.randomUUID().toString());
                int contactUrnId = getDao().insertContactUrn(
                        orgId,
                        contactId,
                        urn.toIdentity(),
                        urn.getScheme().toString(),
                        urn.getPath(),
                        urn.getDisplay(),
                        urn.getScheme().getDefaultPriority(),
                        channelId
                );

                contactContext = new ContactContext(contactUrnId, contactId, channelId, true);
            }

            return contactContext;
        });
    }
}