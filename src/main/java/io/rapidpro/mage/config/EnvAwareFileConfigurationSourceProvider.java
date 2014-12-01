package io.rapidpro.mage.config;

import com.google.common.base.Charsets;
import com.google.common.io.Files;
import io.dropwizard.configuration.ConfigurationSourceProvider;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Configuration provider for files containing environment variable references (${...})
 */
public class EnvAwareFileConfigurationSourceProvider implements ConfigurationSourceProvider {

    @Override
    public InputStream open(String path) throws IOException {
        final File file = new File(path);
        if (!file.exists()) {
            throw new FileNotFoundException("File " + file + " not found");
        }

        String content = Files.toString(new File(path), Charsets.UTF_8);
        content = substituteEnvVars(content);

        return new ByteArrayInputStream(content.getBytes(StandardCharsets.UTF_8));
    }

    /**
     * Performs environment variable substitution on the given string, e.g. "Your home is ${HOME}"
     * @param text the text to substitute
     * @return the substituted text
     */
    protected static String substituteEnvVars(String text) {
        Pattern pattern = Pattern.compile("[\\$]\\{([^\\}]+)\\}");
        Matcher m = pattern.matcher(text);
        StringBuffer sb = new StringBuffer(text.length());
        while (m.find()) {
            String reference = m.group(1).trim();
            String value = System.getenv(reference);

            if (value == null) {
                throw new RuntimeException("Missing environment variable: " + reference);
            }

            m.appendReplacement(sb, Matcher.quoteReplacement(value));
        }
        m.appendTail(sb);
        return sb.toString();
    }
}