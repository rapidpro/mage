package io.rapidpro.mage.config;

import com.fasterxml.jackson.annotation.JsonProperty;
import io.dropwizard.Configuration;
import org.hibernate.validator.constraints.NotEmpty;

import javax.validation.Valid;
import javax.validation.constraints.NotNull;

/**
 * Application configuration loaded from config.yml
 */
public class MageConfiguration extends Configuration {

    @Valid
    @NotNull
    @JsonProperty("general")
    private GeneralFactory m_general = new GeneralFactory();

    @Valid
    @NotNull
    @JsonProperty("database")
    private MageDataSourceFactory m_database = new MageDataSourceFactory();

    @Valid
    @NotNull
    @JsonProperty("temba")
    private TembaFactory m_temba = new TembaFactory();

    @Valid
    @NotNull
    @JsonProperty("redis")
    private RedisFactory m_redis = new RedisFactory();

    @Valid
    @NotNull
    @JsonProperty("twitter")
    private TwitterFactory m_twitter = new TwitterFactory();

    @Valid
    @NotNull
    @JsonProperty("monitoring")
    private MonitoringFactory m_monitoring = new MonitoringFactory();

    public GeneralFactory getGeneralFactory() { return m_general; }

    public MageDataSourceFactory getDataSourceFactory() {
        return m_database;
    }

    public RedisFactory getRedisFactory() {
        return m_redis;
    }

    public TembaFactory getTembaFactory() {
        return m_temba;
    }

    public TwitterFactory getTwitterFactory() {
        return m_twitter;
    }

    public MonitoringFactory getMonitoringFactory() {
        return m_monitoring;
    }

    /**
     * General configuration options
     */
    public static class GeneralFactory {
        @JsonProperty("production")
        private Integer production;

        public boolean isProduction() {
            return production != null && production == 1;
        }
    }

    /**
     * Temba configuration options
     */
    public static class TembaFactory {
        @NotEmpty
        @JsonProperty("apiUrl")
        private String m_apiUrl;

        @NotEmpty
        @JsonProperty("authToken")
        private String m_authToken;

        public String getApiUrl() {
            // Temba is always accessed over SSL, but for developer convenience, we allow SSL to be disabled via an env var
            if (System.getenv("TEMBA_NO_SSL") != null) {
                return m_apiUrl.replace("https://", "http://");
            }

            return m_apiUrl;
        }

        public String getAuthToken() {
            return m_authToken;
        }
    }

    /**
     * Redis configuration options
     */
    public static class RedisFactory {
        @NotEmpty
        @JsonProperty("host")
        private String m_host;

        @JsonProperty("database")
        private int m_database;

	@JsonProperty("password")
	private String m_password;

        public String getHost() {
            return m_host;
        }

        public int getDatabase() {
            return m_database;
        }

	public String getPassword() {
	    return m_password;
	}
    }

    /**
     * Twitter configuration options
     */
    public static class TwitterFactory {
        @NotEmpty
        @JsonProperty("apiKey")
        private String m_apiKey;

        @JsonProperty("apiSecret")
        private String m_apiSecret;

        public String getApiKey() {
            return m_apiKey;
        }

        public String getApiSecret() {
            return m_apiSecret;
        }
    }

    /**
     * Monitoring (SegmentIO, Sentry, Librato) configuration options
     */
    public static class MonitoringFactory {
        @JsonProperty("segmentioWriteKey")
        private String m_segmentioWriteKey;

        @JsonProperty("sentryDsn")
        private String m_sentryDsn;

        @JsonProperty("libratoEmail")
        private String m_libratoEmail;

        @JsonProperty("libratoApiToken")
        private String m_libratoApiToken;

        public String getSegmentioWriteKey() {
            return m_segmentioWriteKey;
        }

        public String getSentryDsn() {
            return m_sentryDsn;
        }

        public String getLibratoEmail() {
            return m_libratoEmail;
        }

        public String getLibratoApiToken() {
            return m_libratoApiToken;
        }
    }
}
