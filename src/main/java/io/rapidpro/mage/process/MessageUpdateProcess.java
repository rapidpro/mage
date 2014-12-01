package io.rapidpro.mage.process;

import io.rapidpro.mage.MageConstants;
import io.rapidpro.mage.cache.Cache;
import io.rapidpro.mage.service.MessageService;
import io.rapidpro.mage.service.ServiceManager;
import io.rapidpro.mage.util.JsonUtils;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Date;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * Scheduled job to update statuses of outgoing messages
 */
public class MessageUpdateProcess extends BaseProcess {

    private final ServiceManager m_services;

    private final Cache m_cache;

    protected int m_failCount = 0;

    protected final long[] m_retryDelays = { 5000l, 10000l, 30000l };

    public MessageUpdateProcess(ServiceManager services, Cache cache) {
        super("msgupdater", 5000l);

        m_services = services;
        m_cache = cache;
    }

    /**
     * @see BaseProcess#doUnitOfWork()
     */
    @Override
    protected long doUnitOfWork() {
        List<String> encodedRequests = m_cache.listPopAll(MageConstants.CacheKey.MESSAGE_UPDATE_QUEUE);
        if (encodedRequests.isEmpty()) {
            log.debug("Found no pending message status updates");
            return 5000l;
        }

        try {
            List<MessageUpdate> updates = encodedRequests.stream().map(s -> JsonUtils.parse(s, MessageUpdate.class)).collect(Collectors.toList());
            processRequests(updates);
            m_failCount = 0;
            return 5000l;
        }
        catch (Exception e) {
            // if an exception occurs during processing, put back at start of list and schedule retry
            m_cache.listLPushAll(MageConstants.CacheKey.MESSAGE_UPDATE_QUEUE, encodedRequests);

            m_failCount++;
            long delay = m_retryDelays[Math.min(m_failCount, m_retryDelays.length) - 1];

            log.warn("Unable to process " + encodedRequests.size() + " messages, retrying in " + delay + " milliseconds");
            return delay;
        }
    }

    /**
     * Processes the given list of status updates
     * @param updates the updates
     */
    protected void processRequests(Collection<MessageUpdate> updates) throws Exception {
        MessageService messageService = m_services.getMessageService();

        updates = new LinkedHashSet<>(updates); // removes duplicates but preserves order

        List<Integer> sent = new ArrayList<>();
        List<Date> sentDates = new ArrayList<>();

        List<Integer> delivered = new ArrayList<>();
        List<Date> deliveredDates = new ArrayList<>();

        List<Integer> failed = new ArrayList<>();

        Set<Integer> broadcasts = new HashSet<>();

        for (MessageUpdate change : updates) {
            switch (change.getStatus()) {
                case SENT:
                    sent.add(change.getMessageId());
                    sentDates.add(change.getDate());
                    break;
                case DELIVERED:
                    delivered.add(change.getMessageId());
                    deliveredDates.add(change.getDate());
                    break;
                case FAILED:
                    failed.add(change.getMessageId());
                    break;
            }

            if (change.getBroadcastId() != null) {
                broadcasts.add(change.getBroadcastId());
            }
        }

        if (!sent.isEmpty()) {
            messageService.updateBatchToSent(sent, sentDates);
            log.debug("Updated " + sent.size() + " to SENT");
        }
        if (!delivered.isEmpty()) {
            messageService.updateBatchToDelivered(delivered, deliveredDates);
            log.debug("Updated " + delivered.size() + " to DELIVERED");
        }
        if (!failed.isEmpty()) {
            messageService.updateBatchToFailed(failed);
            log.debug("Updated " + failed.size() + " to FAILED");
        }

        // Update all broadcasts effected by the message updates
        broadcasts.forEach(messageService::updateBroadcast);
    }
}