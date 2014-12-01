package io.rapidpro.mage.config;

import com.fasterxml.jackson.annotation.JsonProperty;
import io.dropwizard.db.DataSourceFactory;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * The regular DataSourceFactory has separate fields for user, password and URL. This allows all three to be set with a
 * URL in the same format as what we use for Temba (Django)
 */
public class MageDataSourceFactory extends DataSourceFactory {

    private String m_fullUrl;

    @JsonProperty
    public String getFullUrl() {
        return m_fullUrl;
    }

    @JsonProperty
    public void setFullUrl(String fullUrl) {
        this.m_fullUrl = fullUrl;

        // see http://regex101.com/r/wE0xY0/1
        Pattern pattern = Pattern.compile("(?<driver>\\w+)://(?<user>\\w+):(?<password>\\w+)@(?<host>[\\w\\.\\-:]+)/(?<schema>\\w+)");

        Matcher matcher = pattern.matcher(fullUrl);
        if (!matcher.matches()) {
            throw new RuntimeException("database.fullUrl should be in format driver://user:password@host/schema");
        }

        String driver = matcher.group("driver");
        if ("postgres".equals(driver)) {
            driver = "postgresql";
        }

        this.setUrl("jdbc:" + driver + "://" + matcher.group("host") + "/" + matcher.group("schema"));
        this.setUser(matcher.group("user"));
        this.setPassword(matcher.group("password"));
    }
}