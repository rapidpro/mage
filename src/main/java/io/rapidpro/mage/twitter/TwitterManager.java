package io.rapidpro.mage.twitter;

import com.google.common.util.concurrent.ThreadFactoryBuilder;
import io.rapidpro.mage.MageConstants;
import io.rapidpro.mage.cache.Cache;
import io.rapidpro.mage.core.ChannelContext;
import io.rapidpro.mage.core.ChannelType;
import io.rapidpro.mage.service.ChannelService;
import io.rapidpro.mage.service.ServiceManager;
import io.rapidpro.mage.temba.TembaManager;
import io.rapidpro.mage.util.JsonUtils;
import io.dropwizard.lifecycle.Managed;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.Vector;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;

/**
 * Manages all Twitter streams. There may be multiple Mage instances but only one can't manage Twitter streams at any
 * one time. So when started, this class will try to establish itself as the master node. If successful, it will create
 * streams for all active Twitter channels in the database.
 */
public class TwitterManager implements Managed {

    protected static final Logger log = LoggerFactory.getLogger(TwitterManager.class);

    private final ServiceManager m_services;
    private final Cache m_cache;
    private final TembaManager m_temba;
    private final String m_apiKey;
    private final String m_apiSecret;

    private final String m_identifier = UUID.randomUUID().toString();
    private ScheduledExecutorService m_masterMgmt;
    private boolean m_master = false;
    private List<TwitterStream> m_streams = new Vector<>();

    public TwitterManager(ServiceManager services, Cache cache, TembaManager temba, String apiKey, String apiSecret) {
        this.m_services = services;
        this.m_cache = cache;
        this.m_temba = temba;
        this.m_apiKey = apiKey;
        this.m_apiSecret = apiSecret;
    }

    @Override
    public void start() throws Exception {
        log.info("Starting Twitter manager node...");

        ThreadFactory masterFactory = new ThreadFactoryBuilder().setNameFormat("mastermgmt-%d").build();
        m_masterMgmt = Executors.newSingleThreadScheduledExecutor(masterFactory);
        m_masterMgmt.scheduleWithFixedDelay(new MasterManagementTask(), 0, 5, TimeUnit.SECONDS);
    }

    @Override
    public void stop() throws Exception {
        log.info("Stopping Twitter manager node...");

        m_masterMgmt.shutdown();

        if (m_master) {
            onResignMaster();

            getCache().deleteValue(MageConstants.CacheKey.TWITTER_MASTER_LOCK);

            m_master = false;
        }
    }

    /**
     * Requests a stream operation on the given channel. Request will be handled by the master node.
     * @param channel the channel context
     * @param action the action to perform
     */
    public void requestStreamOperation(ChannelContext channel, StreamOperation.Action action)  {
        StreamOperation operation = new StreamOperation(channel.getChannelUuid(), action);
        getCache().listRPush(MageConstants.CacheKey.TWITTER_STREAMOP_QUEUE, JsonUtils.encode(operation, true));
    }

    /**
     * Called when this node becomes the Twitter master
     */
    protected void onBecomeMaster() {
        log.info("Becoming Twitter master node...");

        ChannelService service = m_services.getChannelService();
        List<ChannelContext> channels = service.getChannelsByType(ChannelType.TWITTER);

        log.info("Found " + channels.size() + " active Twitter channel(s)");

        for (ChannelContext channel: channels) {
            try {
                addNodeStream(channel);
            }
            catch (Exception ex) {
                log.error("Unable to add stream for channel #" + channel.getChannelId(), ex);
            }
        }
    }

    /**
     * Called when this node ceases to be the Twitter master
     */
    protected void onResignMaster() {
        log.info("Resigning Twitter master node...");

        for (TwitterStream stream : new ArrayList<>(m_streams)) {
            try {
                removeNodeStream(stream.getChannel());
            } catch (Exception ex) {
                log.error("Unable to add remove stream for channel #" + stream.getChannel().getChannelId(), ex);
            }
        }
    }

    /**
     * Fetches a channel from the database
     * @param channelUuid the channel UUID
     * @return the channel context
     */
    protected ChannelContext fetchChannel(String channelUuid) {
        ChannelContext channel = getServices().getChannelService().getChannelByUuid(channelUuid);
        if (channel == null) {
            throw new RuntimeException("No such channel with UUID " + channelUuid);
        }
        return channel;
    }

    /**
     * Gets a node stream for the given channel
     * @param channel the channel context
     * @return the stream or null
     */
    public TwitterStream getNodeStreamByChannel(ChannelContext channel) {
        for (TwitterStream stream : m_streams) {
            if (channel.getChannelUuid().equals(stream.getChannel().getChannelUuid())) {
                return stream;
            }
        }
        return null;
    }

    /**
     * Gets all streams managed by this node
     * @return the streams
     */
    public List<TwitterStream> getNodeStreams() {
        return m_streams;
    }

    /**
     * Scheduled task which does two things:
     * 1. Keeps track of whether we are the master node
     * 2. Processes queued stream operations if we are the master node
     */
    protected class MasterManagementTask implements Runnable {

        @Override
        public void run() {
            try {
                String masterIdentifier = getCache().setValueIfEqual(MageConstants.CacheKey.TWITTER_MASTER_LOCK, m_identifier, 30_000);
                boolean newState = m_identifier.equals(masterIdentifier);

                if (!m_master && newState) {
                    onBecomeMaster();
                } else if (m_master && !newState) {
                    onResignMaster();
                }

                if (newState) {
                    processQueuedOperations();
                }

                m_master = newState;
            }
            catch (Exception ex) {
                log.error("Error in master management task", ex);
            }
        }
    }

    /**
     * Pops queued stream operations out of the redis queue and processes them
     */
    protected void processQueuedOperations() {
        while (true) {
            String encodedOperation;
            try {
                encodedOperation = getCache().listLPop(MageConstants.CacheKey.TWITTER_STREAMOP_QUEUE);
                if (encodedOperation == null) {
                    break;
                }
            }
            catch (Exception ex) {
                // if redis is unavailable we end up here. Break out of the loop to back off for a bit
                log.error("Unable to fetch queued stream operations", ex);
                break;
            }

            try {
                StreamOperation operation = JsonUtils.parse(encodedOperation, StreamOperation.class);
                processOperation(operation);
            }
            catch (Exception ex) {
                // processing an individual request failed but carry on processing others
                log.error("Unable to process queued stream operation", ex);
            }
        }
    }

    /**
     * Processes a single stream operation
     * @param operation the stream operation
     */
    protected synchronized void processOperation(StreamOperation operation) throws Exception {
        ChannelContext channel = fetchChannel(operation.getChannelUuid());

        switch (operation.getAction()) {
            case ADD:
                addNodeStream(channel);
                break;
            case UPDATE:
                updateNodeStream(channel);
                break;
            case REMOVE:
                removeNodeStream(channel);
                break;
        }
    }

    /**
     * Adds a stream for the given Twitter channel to this node
     * @param channel the channel context
     * @return the stream
     */
    protected TwitterStream addNodeStream(ChannelContext channel) throws Exception {
        // if we already have a stream for this channel, return that
        TwitterStream existing = getNodeStreamByChannel(channel);
        if (existing != null) {
            return existing;
        }

        TwitterStream stream = new TwitterStream(this, channel, m_apiKey, m_apiSecret);
        m_streams.add(stream);
        log.info("Added Twitter stream for handle " + channel.getChannelAddress() + " (" + stream.getHandleId() + ") on channel #" + channel.getChannelId());

        stream.start();

        return stream;
    }

    /**
     * Removes the stream for the given Twitter channel from this node
     * @param channel the channel context
     */
    protected void updateNodeStream(ChannelContext channel) throws Exception {
        log.info("Updating Twitter stream for channel #" + channel.getChannelId());

        TwitterStream stream = getNodeStreamByChannel(channel);
        if (stream == null) {
            throw new RuntimeException("No Twitter stream active for channel #" + channel.getChannelId());
        }

        stream.updateFromConfig(channel.getChannelConfig());
    }

    /**
     * Removes the stream for the given Twitter channel from this node
     * @param channel the channel context
     */
    protected void removeNodeStream(ChannelContext channel) throws Exception {
        // if we already have a stream for this channel, return that
        TwitterStream stream = getNodeStreamByChannel(channel);
        if (stream == null) {
            throw new RuntimeException("No Twitter stream active for channel #" + channel.getChannelId());
        }

        stream.stop();
        m_streams.remove(stream);

        log.info("Removed Twitter stream for handle " + channel.getChannelAddress() + " (" + stream.getHandleId() + ") on channel #" + channel.getChannelId());
    }

    /**
     * Takes master status by force
     */
    public void becomeMaster() {
        getCache().setValue(MageConstants.CacheKey.TWITTER_MASTER_LOCK, m_identifier, 30_000);
    }

    public ServiceManager getServices() {
        return m_services;
    }

    public Cache getCache() {
        return m_cache;
    }

    public TembaManager getTemba() {
        return m_temba;
    }

    public boolean isMaster() {
        return m_master;
    }
}