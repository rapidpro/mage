package io.rapidpro.mage.config;

import com.google.common.io.CharStreams;
import io.rapidpro.mage.test.BaseMageTest;
import org.junit.Test;

import java.io.FileNotFoundException;
import java.io.InputStream;
import java.io.InputStreamReader;

import static org.hamcrest.Matchers.is;
import static org.junit.Assert.assertThat;

/**
 * Tests for {@link io.rapidpro.mage.config.EnvAwareFileConfigurationSourceProvider}
 */
public class EnvAwareFileConfigurationSourceProviderTest extends BaseMageTest {

    /**
     * @see io.rapidpro.mage.config.EnvAwareFileConfigurationSourceProvider#open(String)
     */
    @Test
    public void open_shouldSubstituteEnvVars() throws Exception {
        EnvAwareFileConfigurationSourceProvider provider = new EnvAwareFileConfigurationSourceProvider();
        InputStream in = provider.open("src/test/resources/test-config.yml");

        String home = System.getProperty("user.home");
        String user = System.getProperty("user.name");
        String filtered = CharStreams.toString(new InputStreamReader(in));
        assertThat(filtered, is("somePlace: " +  home + "/x\nsomeUser: " + user));
    }

    @Test(expected = FileNotFoundException.class)
    public void open_shouldThrowExceptionIfFileNotFound() throws Exception {
        EnvAwareFileConfigurationSourceProvider provider = new EnvAwareFileConfigurationSourceProvider();
        provider.open("src/test/resources/test-config-missing.yml");
    }

    @Test(expected = RuntimeException.class)
    public void open_shouldThrowExceptionIfVarNotDefined() throws Exception {
        EnvAwareFileConfigurationSourceProvider provider = new EnvAwareFileConfigurationSourceProvider();
        provider.open("src/test/resources/test-config-invalid.yml");
    }
}