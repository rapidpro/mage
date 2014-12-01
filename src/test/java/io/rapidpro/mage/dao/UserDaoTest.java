package io.rapidpro.mage.dao;

import io.rapidpro.mage.test.BaseServicesTest;
import org.junit.Test;

import java.util.Map;

import static org.hamcrest.Matchers.is;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.dao.UserDao}
 */
public class UserDaoTest extends BaseServicesTest {

    private UserDao m_dao = getServices().getUserService().getDao();

    /**
     * @see UserDao#getUserId(String)
     */
    @Test
    public void getUserId() {
        assertThat(m_dao.getUserId("mage"), is(-3));
        assertThat(m_dao.getUserId("xxxxx"), nullValue());
    }

    /**
     * @see UserDao#insertUser(String, String)
     */
    @Test
    public void insertUser() throws Exception {
        int userId = m_dao.insertUser("mage2", "mm2@example.com");
        Map<String, Object> user = fetchSingleById(Table.USER, userId);
        assertThat(user.get("username"), is("mage2"));
        assertThat(user.get("email"), is("mm2@example.com"));
    }
}