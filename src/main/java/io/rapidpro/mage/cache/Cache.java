package io.rapidpro.mage.cache;

import com.github.jedis.lock.JedisLock;
import io.rapidpro.mage.util.JsonUtils;
import io.dropwizard.lifecycle.Managed;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import redis.clients.jedis.BinaryJedis;
import redis.clients.jedis.Jedis;
import redis.clients.jedis.JedisPool;
import redis.clients.jedis.JedisPoolConfig;
import redis.clients.jedis.Protocol;
import redis.clients.jedis.Response;
import redis.clients.jedis.Transaction;

import java.util.Collection;
import java.util.List;

/**
 * Managed Redis/Jedis wrapper
 */
public class Cache implements Managed {

    protected static final Logger log = LoggerFactory.getLogger(Cache.class);

    private String m_host;

    private int m_database;

    private String m_password;

    private JedisPool m_pool;

    /**
     * Creates a Redis cache
     * @param host the host, e.g. "localhost"
     * @param database, the database index, e.g. 0 is default
     * @param password, the password to redis, e.g. null is default
     */
    public Cache(String host, int database, String password) {
        m_host = host;
        m_database = database;
	m_password = password;
    }

    /**
     * @see io.dropwizard.lifecycle.Managed#start()
     */
    @Override
    public void start() throws Exception {
        JedisPoolConfig config = new JedisPoolConfig();

        m_pool = new JedisPool(config, m_host, Protocol.DEFAULT_PORT, Protocol.DEFAULT_TIMEOUT, m_password, m_database);

        log.info("Created Redis pool ({} max-total, {} max-idle)", config.getMaxTotal(), config.getMaxIdle());
    }

    /**
     * @see io.dropwizard.lifecycle.Managed#stop()
     */
    @Override
    public void stop() throws Exception {
        m_pool.destroy();

        log.info("Destroyed Redis pool");
    }

    /**
     * Looks up a value in the cache
     * @param key the key
     * @return the value or null
     */
    public String getValue(String key) {
        return perform(res -> res.get(key));
    }

    /**
     * Sets a value in the cache that will never expire
     * @param key the key
     * @param value the value
     */
    public void setValue(String key, String value) {
        perform(res -> res.set(key, value));
    }

    /**
     * Sets a volatile value in the cache
     * @param key the key
     * @param ttl the time-to-live in milliseconds
     * @param value the value
     */
    public void setValue(String key, String value, long ttl) {
        perform(res -> res.psetex(key, (int) ttl, value));
    }

    /**
     * Sets a volatile value in the cache if it doesn't currently exist
     * @param key the key
     * @param ttl the time-to-live in milliseconds
     * @param value the value
     */
    public boolean setValueIfNotExists(String key, String value, long ttl) {
        return stringResult(perform(res -> res.set(key, value, "NX", "PX", ttl)));
    }

    /**
     * Sets a volatile value in the cache if it is null or currently exists with same value
     * @param key the key
     * @param ttl the time-to-live in milliseconds
     * @param value the value
     * @return the value of the key after this operation
     */
    public String setValueIfEqual(String key, String value, long ttl) {
        String script = "local existing = redis.call('get', KEYS[1]) " +
                        "if not existing or existing == ARGV[1] then " +
                        "  redis.call('set', KEYS[1], ARGV[1], 'PX', ARGV[2]) " +
                        "  return ARGV[1] " +
                        "else " +
                        "  return existing " +
                        "end ";
        return perform(res -> (String) res.eval(script, 1, key, value, String.valueOf(ttl)));
    }

    /**
     * Deletes a value from the cache
     * @param key the key
     */
    public void deleteValue(String key) {
        perform(res -> res.del(key));
    }

    /**
     * Pushes an item on to the left of a list
     * @param key the key
     * @param value the value
     */
    public long listLPush(String key, String value) {
        return perform(res -> res.lpush(key, value));
    }

    /**
     * Pushes an item on to the right of a list
     * @param key the key
     * @param value the value
     */
    public long listRPush(String key, String value) {
        return perform(res -> res.rpush(key, value));
    }

    /**
     * Pushes all items from a collection on to the right of a list
     * @param key the key
     * @param values the values
     */
    public void listLPushAll(String key, Collection<String> values) {
        performWithTransaction(trans -> {
            for (String value : values) {
                trans.lpush(key, value);
            }
            return null;
        });
    }

    /**
     * Pushes all items from a collection on to the right of a list
     * @param key the key
     * @param values the values
     */
    public void listRPushAll(String key, Collection<String> values) {
        performWithTransaction(trans -> {
            for (String value : values) {
                trans.rpush(key, value);
            }
            return null;
        });
    }

    /**
     * Gets all items from a list
     * @param key the key
     * @return the values
     */
    public List<String> listGetAll(String key) {
        return perform(res -> res.lrange(key, 0, -1));
    }

    /**
     * Pops an item from the left of a list
     * @param key the key
     * @return the value
     */
    public String listLPop(String key) {
        return perform(res -> res.lpop(key) );
    }

    /**
     * Pops an item from the right of a list
     * @param key the key
     * @return the value
     */
    public String listRPop(String key) {
        return perform(res -> res.rpop(key) );
    }

    /**
     * Pops all items from a list
     * @param key the key
     * @return the values
     */
    public List<String> listPopAll(String key) {
        return performWithTransaction(trans -> {
            Response<List<String>> vals = trans.lrange(key, 0, -1);
            trans.del(key);
            return vals;
        });
    }

    /**
     * Gets the length of a list
     * @param key the key
     * @return the length
     */
    public long listLength(String key) {
        return perform(res -> res.llen(key));
    }

    /**
     * Flushes everything in the database
     */
    public void flush() {
        perform(BinaryJedis::flushDB);
    }

    /**
     * Interface for operations which require a resource to be allocated and released around their execution
     */
    @FunctionalInterface
    public interface OperationWithResource<T> {
        T perform(Jedis resource);
    }

    /**
     * Runs the given operation after allocating a resource from the pool, and releases the resource when finished
     * @param operation the operation
     * @param <T> the return type of the runnable
     * @return the result of the runnable
     */
    public <T> T perform(OperationWithResource<T> operation) {
        Jedis resource = m_pool.getResource();
        try {
            return operation.perform(resource);
        }
        finally {
            m_pool.returnResource(resource);
        }
    }

    /**
     * Performs the given operation with a distributed lock
     * @param lockname the name of the lock
     * @param ttl the lock time-to-lve in milliseconds
     * @param operation the operation
     * @return the result of the operation
     */
    public <T> T performWithLock(String lockname, long ttl, OperationWithResource<T> operation) {
        Jedis resource = m_pool.getResource();
        JedisLock lock = new JedisLock(resource, lockname, 10000, (int) ttl);
        try {
            lock.acquire();
            return operation.perform(resource);
        }
        catch (InterruptedException ex) {
            throw new RuntimeException(ex);
        }
        finally {
            lock.release();
            m_pool.returnResource(resource);
        }
    }

    /**
     * Interface for operations which require a transaction to be created and committed around their execution
     */
    @FunctionalInterface
    public interface OperationWithTransaction<T> {
        Response<T> perform(Transaction transaction);
    }

    /**
     * Performs the given operation with a transaction
     * @param operation the operation
     * @return the result of the operation
     */
    public <T> T performWithTransaction(OperationWithTransaction<T> operation) {
        Jedis resource = m_pool.getResource();
        Transaction transaction = resource.multi();
        Response<T> response = null;
        try {
            response = operation.perform(transaction);
        }
        finally {
            transaction.exec();
            m_pool.returnResource(resource);
        }
        return response != null ? response.get() : null;
    }

    /**
     * Interface for operations which fetch an item not found in the cache
     */
    @FunctionalInterface
    public interface FetchOnMissOperation<T> {
        T fetch();
    }

    /**
     * Fetches a JSON serializable item from the cache. If item isn't found in the cache then the provided fetch operation
     * is invoked and object is placed in the cache provided it is non-null.
     * @param cacheKey the cache key
     * @param cacheTTL the cache TTL
     * @param itemClazz the item class
     * @param operation the fetch operation if item is not in the cache
     * @return the item
     */
    public <T> T fetchJsonSerializable(String cacheKey, long cacheTTL, Class<T> itemClazz, FetchOnMissOperation<T> operation) {
        return perform(res -> {
            String cached = res.get(cacheKey);
            if (cached != null) {
                return JsonUtils.parse(cached, itemClazz);
            }

            T item = operation.fetch();

            if (item != null) {
                res.set(cacheKey, JsonUtils.encode(item, true));
                res.pexpire(cacheKey, cacheTTL);
            }

            return item;
        });
    }

    protected boolean stringResult(String str) {
        return "OK".equals(str);
    }
}
