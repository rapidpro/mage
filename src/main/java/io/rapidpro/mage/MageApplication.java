package io.rapidpro.mage;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.Appender;
import com.codahale.metrics.MetricFilter;
import com.codahale.metrics.MetricRegistry;
import com.google.common.io.Resources;
import com.librato.metrics.LibratoReporter;
import io.rapidpro.mage.cache.Cache;
import io.rapidpro.mage.config.EnvAwareFileConfigurationSourceProvider;
import io.rapidpro.mage.config.MageConfiguration;
import io.rapidpro.mage.dao.mapper.AnnotationMapperFactory;
import io.rapidpro.mage.health.QueueSizeCheckAndGauge;
import io.rapidpro.mage.process.MessageUpdateProcess;
import io.rapidpro.mage.resource.ExternalResource;
import io.rapidpro.mage.resource.TwilioResource;
import io.rapidpro.mage.resource.TwitterResource;
import io.rapidpro.mage.resource.VumiResource;
import io.rapidpro.mage.service.ServiceManager;
import io.rapidpro.mage.health.HealthCheckServlet;
import io.rapidpro.mage.task.SentryTestTask;
import io.rapidpro.mage.task.TwitterBackfillTask;
import io.rapidpro.mage.task.TwitterMasterTask;
import io.rapidpro.mage.temba.TembaManager;
import io.rapidpro.mage.twitter.TwitterManager;
import io.rapidpro.mage.util.JsonUtils;
import io.rapidpro.mage.util.MageUtils;
import com.tradier.raven.logging.RavenAppenderFactory;
import io.dropwizard.Application;
import io.dropwizard.assets.AssetsBundle;
import io.dropwizard.jdbi.DBIFactory;
import io.dropwizard.jdbi.bundles.DBIExceptionsBundle;
import io.dropwizard.setup.Bootstrap;
import io.dropwizard.setup.Environment;
import org.apache.commons.lang3.StringUtils;
import org.skife.jdbi.v2.DBI;
import org.slf4j.LoggerFactory;

import javax.servlet.Servlet;
import java.io.IOException;
import java.net.InetAddress;
import java.util.HashMap;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.TimeUnit;

/**
 * Main application (executable)
 */
public class MageApplication extends Application<MageConfiguration> {

    protected static final org.slf4j.Logger log = LoggerFactory.getLogger(MageApplication.class);

    public static void main(String[] args) throws Exception {
        new MageApplication().run(args);
    }

    /**
     * @see io.dropwizard.Application#getName()
     */
    @Override
    public String getName() {
        return "Mage";
    }

    /**
     * @see io.dropwizard.Application#initialize(io.dropwizard.setup.Bootstrap)
     */
    @Override
    public void initialize(Bootstrap<MageConfiguration> bootstrap) {
        bootstrap.setConfigurationSourceProvider(new EnvAwareFileConfigurationSourceProvider());
        bootstrap.addBundle(new DBIExceptionsBundle());
        bootstrap.addBundle(new AssetsBundle("/assets", "/", "index.html"));
    }

    /**
     * @see io.dropwizard.Application#run(io.dropwizard.Configuration, io.dropwizard.setup.Environment)
     */
    @Override
    public void run(MageConfiguration config, Environment environment) throws Exception {
        MageConfiguration.GeneralFactory generalCfg = config.getGeneralFactory();
        MageConfiguration.RedisFactory redisCfg = config.getRedisFactory();
        MageConfiguration.TembaFactory tembaCfg = config.getTembaFactory();
        MageConfiguration.TwitterFactory twitterCfg = config.getTwitterFactory();
        MageConfiguration.MonitoringFactory monitoringCfg = config.getMonitoringFactory();

        Properties build = loadBuildProperties();
        String appVersion = build.getProperty("version");
        String serverName = InetAddress.getLocalHost().getHostName();
        log.info("Mage v" + appVersion);
        log.info("Server name: " + serverName);
        log.info("Production: " + generalCfg.isProduction());

        // use explicit annotations for all JSON serialization
        JsonUtils.disableMapperAutoDetection(environment.getObjectMapper());

        if (StringUtils.isNotEmpty(monitoringCfg.getSentryDsn())) {
            initializeRaven(serverName, appVersion, monitoringCfg.getSentryDsn());
        }

        // create JDBI data source
        DBI dbi = new DBIFactory().build(environment, config.getDataSourceFactory(), "postgresql");
        dbi.registerMapper(new AnnotationMapperFactory());

        // register managed entities
        Cache cache = new Cache(redisCfg.getHost(), redisCfg.getDatabase(), redisCfg.getPassword());
        TembaManager temba = new TembaManager(cache, tembaCfg.getApiUrl(), tembaCfg.getAuthToken(), generalCfg.isProduction());
        ServiceManager services = new ServiceManager(dbi, cache, temba, generalCfg.isProduction());
        TwitterManager twitter = new TwitterManager(services, cache, temba, twitterCfg.getApiKey(), twitterCfg.getApiSecret());

        environment.lifecycle().manage(cache);
        environment.lifecycle().manage(temba);
        environment.lifecycle().manage(services);
        environment.lifecycle().manage(twitter);
        environment.lifecycle().manage(new MessageUpdateProcess(services, cache));

        // register admin tasks
        environment.admin().addTask(new TwitterMasterTask(twitter));
        environment.admin().addTask(new TwitterBackfillTask(twitter));
        environment.admin().addTask(new SentryTestTask());

        // register resources
        environment.jersey().register(new ExternalResource(services));
        environment.jersey().register(new TwilioResource(services));
        environment.jersey().register(new VumiResource(services));
        environment.jersey().register(new TwitterResource(twitter, services, tembaCfg.getAuthToken()));

        // register metrics and health checks
        Map<String, QueueSizeCheckAndGauge> gauges = new HashMap<>();
        gauges.put("queue.tembaapi", new QueueSizeCheckAndGauge(cache, MageConstants.CacheKey.TEMBA_REQUEST_QUEUE, 100));
        gauges.put("queue.streamop", new QueueSizeCheckAndGauge(cache, MageConstants.CacheKey.TWITTER_STREAMOP_QUEUE, 100));
        gauges.put("queue.msgupdate", new QueueSizeCheckAndGauge(cache, MageConstants.CacheKey.MESSAGE_UPDATE_QUEUE, 1000));

        gauges.forEach(environment.metrics()::register);
        gauges.forEach(environment.healthChecks()::register);

        // register servlets
        Servlet statusServlet = new HealthCheckServlet(environment.healthChecks());
        environment.servlets().addServlet("status-servlet", statusServlet).addMapping("/status");

        if (generalCfg.isProduction()) {
            initializeLibrato(environment.metrics(), serverName, monitoringCfg.getLibratoEmail(), monitoringCfg.getLibratoApiToken());
        }
    }

    /**
     * Loads the build properties
     * @return the properties
     */
    protected Properties loadBuildProperties() throws IOException {
        Properties build = new Properties();
        build.load(Resources.getResource("build.properties").openStream());
        return build;
    }

    /**
     * Initializes the Raven logging system which will send errors to Sentry
     * @param serverName the server name
     * @param appVersion the application version
     * @param sentryDsn the DSN
     */
    protected void initializeRaven(String serverName, String appVersion, String sentryDsn) {
        Logger root = (Logger) LoggerFactory.getLogger(Logger.ROOT_LOGGER_NAME);

        Map<String, String> tags = new HashMap<>();
        tags.put("app", "mage");
        tags.put("version", appVersion);
        tags.put("server_name", serverName);

        RavenAppenderFactory factory = new RavenAppenderFactory();
        factory.setDsn(sentryDsn);
        factory.setThreshold(Level.ERROR);
        factory.setTags(MageUtils.encodeMap(tags, ":", ","));

        Appender<ILoggingEvent> appender = factory.build(root.getLoggerContext(), getName(), null);
        root.addAppender(appender);

        log.info("Initialized Raven client");
    }

    protected void initializeLibrato(MetricRegistry metrics, String serverName, String email, String apiToken) {
        // for now just send our guage metrics
        MetricFilter filter = (s, metric) -> metric instanceof QueueSizeCheckAndGauge;

        LibratoReporter.Builder builder = LibratoReporter.builder(metrics, email, apiToken, serverName)
                .setPrefix("mage")
                .setFilter(filter);
        LibratoReporter.enable(builder, 10, TimeUnit.SECONDS);

        log.info(String.format("Initialized Liberato reporter (%s)", email));
    }
}
