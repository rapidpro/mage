package io.rapidpro.mage.service;

import io.rapidpro.mage.MageConstants;
import io.rapidpro.mage.cache.Cache;
import io.rapidpro.mage.core.CallbackContext;
import io.rapidpro.mage.core.ChannelType;
import io.rapidpro.mage.core.ContactContext;
import io.rapidpro.mage.core.ContactUrn;
import io.rapidpro.mage.core.Direction;
import io.rapidpro.mage.core.IncomingContext;
import io.rapidpro.mage.core.Status;
import io.rapidpro.mage.dao.MessageDao;
import io.rapidpro.mage.process.MessageUpdate;
import io.rapidpro.mage.temba.TembaManager;
import io.rapidpro.mage.temba.TembaRequest;
import io.rapidpro.mage.util.JsonUtils;
import org.apache.commons.lang3.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Service for message operations
 */
public class MessageService extends BaseService<MessageDao> {

    protected static final Logger log = LoggerFactory.getLogger(MessageService.class);

    protected static final int MESSAGE_NORMAL_PRIORITY = 500;

    protected final TembaManager m_temba;

    public MessageService(ServiceManager manager, Cache cache, TembaManager temba, MessageDao dao) {
        super(manager, cache, dao);

        m_temba = temba;
    }

    /**
     * Fetches the context data for a callback message, using the message ID
     * @param messageId the message ID
     * @return the context data
     */
    public CallbackContext getCallbackContext(int messageId) {
        String cacheKey = MageConstants.CacheKey.CALLBACK_CONTEXT_PREFIX + messageId;

        return getCache().fetchJsonSerializable(cacheKey, MageConstants.CacheTtl.CALLBACK_CONTEXT, CallbackContext.class,
                () -> getDao().getCallbackContext(messageId)
        );
    }

    /**
     * Fetches the context data for a callback message, using the the channel UUID, type and an external message ID
     * @param channelUuid the channel UUID
     * @param channelType the channel type
     * @param externalId the external ID of the message
     * @return the context data
     */
    public CallbackContext getCallbackContext(String channelUuid, ChannelType channelType, String externalId) {
        String cacheKey = MageConstants.CacheKey.CALLBACK_CONTEXT_PREFIX + channelUuid + ":" + externalId;

        return getCache().fetchJsonSerializable(cacheKey, MageConstants.CacheTtl.CALLBACK_CONTEXT, CallbackContext.class,
                () -> getDao().getCallbackContext(channelUuid, channelType, externalId)
        );
    }

    /**
     * Fetches the context data for an incoming message, using the destination phone number
     * @param channelType the channel type
     * @param address the channel address
     * @return the context data
     */
    public IncomingContext getIncomingContextByChannelAddressAndType(ChannelType channelType, String address) {
        String cacheKey = MageConstants.CacheKey.INCOMING_CONTEXT_PREFIX + address;

        return getCache().fetchJsonSerializable(cacheKey, MageConstants.CacheTtl.INCOMING_CONTEXT, IncomingContext.class,
                () -> getDao().getIncomingContextByChannelAddressAndType(channelType, address)
        );
    }

    /**
     * Fetches the context data for an incoming message, using the channel UUID and type
     * @param channelUuid the channel UUID
     * @param channelType the channel type
     * @return the context data
     */
    public IncomingContext getIncomingContextByChannelUuidAndType(String channelUuid, ChannelType channelType) {
        String cacheKey = MageConstants.CacheKey.INCOMING_CONTEXT_PREFIX + channelUuid;

        return getCache().fetchJsonSerializable(cacheKey, MageConstants.CacheTtl.INCOMING_CONTEXT, IncomingContext.class,
                () -> getDao().getIncomingContextByChannelUuidAndType(channelUuid, channelType)
        );
    }

    /**
     * Gets the external id of the last message on the given channel
     * @param channelId the channel id
     * @param direction the message direction
     * @return the external message id
     */
    public String getLastExternalId(int channelId, Direction direction) {
        return getDao().getLastExternalId(channelId, direction);
    }

    /**
     * Creates and saves a new incoming message
     * @param context the incoming context
     * @param urn the source URN
     * @param text the message text
     * @return the created message id
     */
    public int createIncoming(IncomingContext context, ContactUrn urn, String text, Date createdOn, String externalId, String name) {
        // try to normalize our URN using our channel country
        urn = urn.normalize(context.getChannelCountry());

        ContactContext contact = getManager().getContactService().getOrCreateContact(context.getOrgId(), urn, context.getChannelId(), name);

        // TODO use externalId + channelId for quicker existing check?

        Integer existingId = getDao().getMessage(text, createdOn, contact.getContactId(), Direction.INCOMING);
        if (existingId != null) {
            return existingId;
        }

        // limit text messages to 640 characters
        text = StringUtils.substring(text, 0, 640); // won't throw null/bounds exception unlike same method in String

        if (createdOn == null) {
            createdOn = new Date();
        }

        int messageId = getDao().insertIncoming(
                context.getChannelId(),
                contact.getContactId(),
                contact.getContactUrnId(),
                text,
                context.getOrgId(),
                createdOn,
                new Date(), // queued on
                externalId,
                MESSAGE_NORMAL_PRIORITY
        );

        // queues up a Temba API call which will both handle this message and trigger a webhook events
        requestMessageHandling(messageId, contact.isNewContact());

        return messageId;
    }

    /**
     * Requests an update of the status of a message
     * @param messageId the message id
     * @param newStatus the new status
     * @param date the date of the change
     * @param broadcastId the broadcast id of the message (may be null)
     */
    public void requestMessageStatusUpdate(int messageId, Status newStatus, Date date, Integer broadcastId) {
        MessageUpdate change = new MessageUpdate(messageId, newStatus, date, broadcastId);
        getCache().listRPush(MageConstants.CacheKey.MESSAGE_UPDATE_QUEUE, JsonUtils.encode(change, true));
    }

    /**
     * Requests handling of an incoming message
     * @param messageId the message id
     */
    public void requestMessageHandling(int messageId, boolean newContact) {
        TembaRequest request = TembaRequest.newHandleMessage(messageId, newContact);
        m_temba.queueRequest(request);
    }

    /**
     * Updates a batch of messages to SENT status
     * @param messageIds the message ids
     * @param dates the update dates
     */
    public void updateBatchToSent(List<Integer> messageIds, List<Date> dates) {
        getDao().updateBatchToSent(messageIds, dates);
    }

    /**
     * Updates a batch of messages to DELIVERED status
     * @param messageIds the message ids
     * @param dates the update dates
     */
    public void updateBatchToDelivered(List<Integer> messageIds, List<Date> dates) {
        getDao().updateBatchToDelivered(messageIds, dates);
    }

    /**
     * Updates a batch of messages to FAILED status
     * @param messageIds the message ids
     */
    public void updateBatchToFailed(List<Integer> messageIds) {
        getDao().updateBatchToFailed(messageIds);
    }

    /**
     * Updates the given broadcast based on the statuses of its associated messages
     * @param broadcastId the broadcast id
     */
    public Status updateBroadcast(int broadcastId) {
        Map<Status, Long> counts = getBroadcastStatusCounts(broadcastId);
        long total = counts.values().stream().reduce(0l, Long::sum);
        Status broadcastStatus = null;

        if (counts.get(Status.ERRORED) > total / 2) {
            broadcastStatus = Status.ERRORED;
        }
        else if (counts.get(Status.FAILED) > total / 2) {
            broadcastStatus = Status.FAILED;
        }
        else if (counts.get(Status.QUEUED) > 0 || counts.get(Status.PENDING) > 0) {
            broadcastStatus = Status.QUEUED;
        }
        else if (counts.get(Status.SENT) > 0 || counts.get(Status.WIRED) > 0) {
            broadcastStatus = Status.SENT;
        }
        else if (counts.get(Status.DELIVERED) == total) {
            broadcastStatus = Status.DELIVERED;
        }

        if (broadcastStatus != null) {
            getDao().updateBroadcastStatus(broadcastId, broadcastStatus);
            log.debug("Broadcast #" + broadcastId + " updated to " + broadcastStatus.name());
        }
        else {
            log.debug("Broadcast #" + broadcastId + " unchanged");
        }
        return broadcastStatus;
    }

    /**
     * Calculates the counts of a broadcast's messages with different statuses
     * @param broadcastId the broadcast id
     * @return the map of statuses to counts
     */
    public Map<Status, Long> getBroadcastStatusCounts(int broadcastId) {
        List<Map<String, Object>> rows = getDao().getBroadcastStatusCounts(broadcastId);

        Map<Status, Long> map = new HashMap<>();
        for (Map<String, Object> row : rows) {
            Status status = Status.fromString((String) row.get("status"));
            Long count = (Long) row.get("count");
            map.put(status, count);
        }

        // add zero defaults for all non-included status
        for (Status status : Status.values()) {
            if (!map.containsKey(status)) {
                map.put(status, 0L);
            }
        }

        return map;
    }
}