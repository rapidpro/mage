package io.rapidpro.mage.dao;

import io.rapidpro.mage.core.ChannelContext;
import io.rapidpro.mage.core.ChannelType;
import io.rapidpro.mage.test.BaseServicesTest;
import org.junit.Test;

import java.util.List;

import static org.hamcrest.Matchers.*;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.dao.ChannelDao}
 */
public class ChannelDaoTest extends BaseServicesTest {

    private ChannelDao m_dao = getServices().getChannelService().getDao();

    /**
     * @see ChannelDao#getChannelsByType(io.rapidpro.mage.core.ChannelType)
     */
    @Test
    public void getChannelsByType() {
        List<ChannelContext> nexmo = m_dao.getChannelsByType(ChannelType.NEXMO);
        assertThat(nexmo, hasSize(1));
        assertThat(nexmo.get(0).getChannelId(), is(-42));
        assertThat(nexmo.get(0).getChannelUuid(), is("B8E3F824-D4B3-4A59-91E1-45BFF6D74263"));
        assertThat(nexmo.get(0).getChannelAddress(), is("+250222222222"));
        assertThat(nexmo.get(0).getChannelType(), is(ChannelType.NEXMO));
        assertThat(nexmo.get(0).getChannelConfig(), nullValue());
        assertThat(nexmo.get(0).getOrgId(), is(-11));

        List<ChannelContext> twitter = m_dao.getChannelsByType(ChannelType.TWITTER);
        assertThat(twitter, hasSize(2));
    }

    /**
     * @see io.rapidpro.mage.dao.ChannelDao#getChannelByUuid(String)
     */
    @Test
    public void getChannelByUuid() {
        ChannelContext twilio = m_dao.getChannelByUuid("A6977A60-77EE-46FD-BFFA-AE58A65150DA");
        assertThat(twilio.getChannelId(), is(-41));

        assertThat(m_dao.getChannelByUuid("xxxxx"), nullValue());
    }

    /**
     * @see io.rapidpro.mage.dao.ChannelDao#updateChannelBod(int, String)
     */
    @Test
    public void updateChannelBod() throws Exception {
        m_dao.updateChannelBod(-41, "1234");
        assertThat(querySingle("SELECT bod FROM " + Table.CHANNEL + " WHERE id = -41").get("bod"), is("1234"));
    }
}