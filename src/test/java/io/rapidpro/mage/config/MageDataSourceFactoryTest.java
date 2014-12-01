package io.rapidpro.mage.config;

import io.rapidpro.mage.test.BaseMageTest;
import org.junit.Test;

import static org.hamcrest.Matchers.is;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.config.MageDataSourceFactory}
 */
public class MageDataSourceFactoryTest extends BaseMageTest {

    /**
     * @see io.rapidpro.mage.config.MageDataSourceFactory#setFullUrl(String)
     */
    @Test
    public void setFullUrl_shouldSetRegularFields() {
        MageDataSourceFactory dsf = new MageDataSourceFactory();

        // with port
        dsf.setFullUrl("postgres://billy:password123@data-base.com:123/temba");

        assertThat(dsf.getFullUrl(), is("postgres://billy:password123@data-base.com:123/temba"));
        assertThat(dsf.getUrl(), is("jdbc:postgresql://data-base.com:123/temba"));
        assertThat(dsf.getUser(), is("billy"));
        assertThat(dsf.getPassword(), is("password123"));

        // without port
        dsf.setFullUrl("postgres://jimmy:admin123@localhost/temba");

        assertThat(dsf.getFullUrl(), is("postgres://jimmy:admin123@localhost/temba"));
        assertThat(dsf.getUrl(), is("jdbc:postgresql://localhost/temba"));
        assertThat(dsf.getUser(), is("jimmy"));
        assertThat(dsf.getPassword(), is("admin123"));
    }

    /**
     * @see MageDataSourceFactory#setFullUrl(String)
     */
    @Test(expected = RuntimeException.class)
    public void setFullUrl_shouldThrowExceptionForIncorrectformat() {
        MageDataSourceFactory dsf = new MageDataSourceFactory();
        dsf.setFullUrl("postgres:xyz");
    }
}