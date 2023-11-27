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

	// see https://regex101.com/r/bWGsPF/1
	final String regex = "(?<driver>.+):\\/\\/(?<user>\\w+):(?<password>.*)@(?<host>.+):(?<port>\\d*)\\/(?<databaseName>\\w+)";
	Pattern pattern = Pattern.compile(regex);
        Matcher matcher = pattern.matcher(fullUrl);
        if (!matcher.matches()) {
            throw new RuntimeException("database.fullUrl should be in format driver://user:password@host/schema");
        }

	// Get the individual connection properties
	String host = matcher.group("host");
	String port = matcher.group("port");
	String databaseName = matcher.group("databaseName");
	String user = matcher.group("user");
	String password = matcher.group("password");

        String driver = matcher.group("driver");
        if ("postgres".equals(driver)) {
            driver = "postgresql";
        }

	password = (password.length() > 0) ? password : null;
	port = (port.length() > 0) ? port : "5432";

        this.setUrl(String.format("jdbc:%s://%s:%s/%s?ApplicationName=%s", driver, host, port, databaseName, "mage"));
        this.setUser(user);
        this.setPassword(password);
    }
}
