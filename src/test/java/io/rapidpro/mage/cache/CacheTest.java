package io.rapidpro.mage.cache;

import io.rapidpro.mage.test.BaseServicesTest;
import io.rapidpro.mage.test.TestPojo;
import io.rapidpro.mage.util.JsonUtils;
import org.junit.Test;

import java.util.Arrays;

import static org.hamcrest.Matchers.*;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.cache.Cache}
 */
public class CacheTest extends BaseServicesTest {

    private Cache m_cache = getCache();

    @Test
    public void getAndSetAndDel() {
        m_cache.deleteValue("foo");
        assertThat(m_cache.getValue("foo"), nullValue());

        m_cache.setValue("foo", "bar");
        assertThat(m_cache.getValue("foo"), is("bar"));

        m_cache.setValue("foo", "zoo", 1000l);
        assertThat(m_cache.getValue("foo"), is("zoo"));

        m_cache.deleteValue("foo");
        assertThat(m_cache.getValue("foo"), nullValue());

        assertThat(m_cache.setValueIfNotExists("foo", "zoo", 10_000l), is(true));
        assertThat(m_cache.getValue("foo"), is("zoo"));

        assertThat(m_cache.setValueIfNotExists("foo", "bar", 10_000l), is(false));
        assertThat(m_cache.getValue("foo"), is("zoo"));

        assertThat(m_cache.setValueIfEqual("foo", "zoo", 5_000l), is("zoo"));
        assertThat(m_cache.getValue("foo"), is("zoo"));
        assertThat(m_cache.setValueIfEqual("foo", "bar", 5_000l), is("zoo"));
        assertThat(m_cache.getValue("foo"), is("zoo"));
        m_cache.deleteValue("foo");

        assertThat(m_cache.setValueIfEqual("foo", "bar", 5_000l), is("bar"));
        assertThat(m_cache.getValue("foo"), is("bar"));
    }

    @Test
    public void lists() {
        m_cache.deleteValue("foo");
        assertThat(m_cache.listPopAll("foo"), empty());

        m_cache.listRPush("foo", "1");
        m_cache.listRPush("foo", "2");
        m_cache.listRPush("foo", "3");
        m_cache.listRPush("foo", "4");

        assertThat(m_cache.listLength("foo"), is(4L));
        assertThat(m_cache.listLPop("foo"), is("1"));
        assertThat(m_cache.listLength("foo"), is(3L));
        assertThat(m_cache.listRPop("foo"), is("4"));
        assertThat(m_cache.listLength("foo"), is(2L));
        assertThat(m_cache.listPopAll("foo"), contains("2", "3"));
        assertThat(m_cache.listLength("foo"), is(0L));
        assertThat(m_cache.listPopAll("foo"), empty());

        m_cache.listRPushAll("foo", Arrays.asList("4", "5", "6"));
        assertThat(m_cache.listPopAll("foo"), contains("4", "5", "6"));
    }

    /**
     * @see Cache#flush()
     */
    @Test
    public void flush() {
        m_cache.setValue("foo", "bar");
        m_cache.flush();
        assertThat(m_cache.getValue("foo"), nullValue());
    }

    /**
     * @see Cache#perform(io.rapidpro.mage.cache.Cache.OperationWithResource)
     */
    @Test
    public void perform() {
        m_cache.perform(res -> res.set("foo", "bar"));
        assertThat(m_cache.perform(res -> res.get("foo")), is("bar"));
    }

    /**
     * @see Cache#performWithLock(String, long, io.rapidpro.mage.cache.Cache.OperationWithResource)
     */
    @Test
    public void performWithLock() throws Exception {
        // TODO a better concurrent way to test locking
        m_cache.performWithLock("test_lock", 60000, res -> res.set("foo", "bar"));
        assertThat(m_cache.perform(res -> res.get("foo")), is("bar"));
    }

    /**
     * @see Cache#fetchJsonSerializable(String, long, Class, io.rapidpro.mage.cache.Cache.FetchOnMissOperation)
     */
    @Test
    public void fetchJsonSerializable() throws Exception {
        TestPojo pojo1 = new TestPojo(1, "2", JsonUtils.object(), TestPojo.Choice.YES);

        // first time won't be in cache
        TestPojo res1 = m_cache.fetchJsonSerializable("test_item:1", 10000, TestPojo.class, () -> pojo1);
        assertThat(res1, equalTo(pojo1));
        assertThat(m_cache.getValue("test_item:1"), notNullValue());

        // second time will be from cache
        TestPojo res2 = m_cache.fetchJsonSerializable("test_item:1", 10000, TestPojo.class, () -> pojo1);
        assertThat(res2, equalTo(pojo1));
    }
}