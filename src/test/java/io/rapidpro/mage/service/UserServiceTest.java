package io.rapidpro.mage.service;

import io.rapidpro.mage.test.BaseServicesTest;
import io.rapidpro.mage.dao.Table;
import org.junit.Test;

import java.util.Map;

import static org.hamcrest.Matchers.is;
import static org.hamcrest.Matchers.nullValue;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.service.UserService}
 */
public class UserServiceTest extends BaseServicesTest {

    private UserService m_service = getServices().getUserService();

    /**
     * @see UserService#getOrCreateServiceUser()
     */
    @Test
    public void getOrCreateServiceUser_shouldReturnIfExistsOrCreate() throws Exception {
        // delete service user from test data
        executeSql("DELETE FROM auth_user WHERE username = 'mage'");
        assertThat(m_service.getDao().getUserId("mage"), nullValue());

        // first invoke should re-create it
        int userId = m_service.getOrCreateServiceUser();
        Map<String, Object> user = fetchSingleById(Table.USER, userId);
        assertThat(user.get("username"), is("mage"));

        // second invoke just returns it
        m_service.getOrCreateServiceUser();
        user = fetchSingleById(Table.USER, userId);
        assertThat(user.get("username"), is("mage"));

        // clean up for subsequent test which expect the service user to exist when it's @BeforeClass annotated methods
        // are invoked.. which is before the database is reloaded
        resetDatabaseAndCache();
    }
}