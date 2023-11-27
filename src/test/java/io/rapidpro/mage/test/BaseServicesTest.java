package io.rapidpro.mage.test;

import io.rapidpro.mage.cache.Cache;
import io.rapidpro.mage.dao.mapper.AnnotationMapperFactory;
import io.rapidpro.mage.service.ServiceManager;
import io.rapidpro.mage.temba.TembaManager;
import io.dropwizard.jdbi.logging.LogbackLog;
import org.dbunit.database.DatabaseConfig;
import org.dbunit.database.DatabaseConnection;
import org.dbunit.database.IDatabaseConnection;
import org.dbunit.database.QueryDataSet;
import org.dbunit.dataset.IDataSet;
import org.dbunit.dataset.xml.FlatXmlDataSet;
import org.dbunit.dataset.xml.FlatXmlDataSetBuilder;
import org.dbunit.operation.DatabaseOperation;
import org.junit.AfterClass;
import org.junit.Before;
import org.junit.BeforeClass;
import org.junit.Ignore;
import org.postgresql.ds.PGPoolingDataSource;
import org.skife.jdbi.v2.DBI;

import java.io.InputStream;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Base class for tests that need services
 */
@Ignore
public abstract class BaseServicesTest extends BaseMageTest {

    protected static final String POSTGRES_HOST = "localhost";
    protected static final String POSTGRES_DBNAME = "temba_mage_tests";
    protected static final String POSTGRES_USERNAME = "temba_mage_tests";
    protected static final String INITIAL_DATASET = "initial-dataset.xml";

    protected static final String REDIS_HOST = "localhost";
    protected static final int REDIS_DATABASE = 13;
    protected static final String REDIS_PASSWORD = null;

    private static IDatabaseConnection s_connection;
    private static IDataSet s_initialData;

    private static Cache s_cache;
    private static TembaManager s_temba;
    private static ServiceManager s_services;

    /**
     * Setup the database connection, DbUnit, DBI and service manager before each test class
     */
    @BeforeClass
    public static void setupServices() throws Exception {
        PGPoolingDataSource ds = new PGPoolingDataSource();
        ds.setServerName(POSTGRES_HOST);
        ds.setDatabaseName(POSTGRES_DBNAME);
        ds.setUser(POSTGRES_USERNAME);

        try {
            s_connection = new DatabaseConnection(ds.getConnection(), "public");
            s_connection.getConfig().setProperty(DatabaseConfig.FEATURE_CASE_SENSITIVE_TABLE_NAMES, Boolean.TRUE);
            s_connection.getConfig().setProperty(DatabaseConfig.PROPERTY_DATATYPE_FACTORY, new PostgresqlDataTypeFactoryExt());

            InputStream is = BaseServicesTest.class.getClassLoader().getResourceAsStream(INITIAL_DATASET);
            s_initialData = new FlatXmlDataSetBuilder().setColumnSensing(true).build(is);
        }
        catch (Exception e) {
            e.printStackTrace();
        }

        DatabaseOperation.CLEAN_INSERT.execute(s_connection, s_initialData);

        DBI dbi = new DBI(ds);
        dbi.setSQLLog(new LogbackLog());
        dbi.registerMapper(new AnnotationMapperFactory());

        // initialise the cache
        s_cache = new Cache(REDIS_HOST, REDIS_DATABASE, REDIS_PASSWORD);
        s_cache.start();

        s_temba = new TembaManager(s_cache, "http://temba.example.com/api/v1", "12345", false);
        s_temba.start();

        // initialise the service manager (all DAOs, services)
        s_services = new ServiceManager(dbi, s_cache, s_temba, false);
        s_services.start();
    }

    /**
     * Performs clean insert of initial data, and a cache flush before each unit test
     */
    @Before
    public void resetDatabaseAndCache() throws Exception {
        DatabaseOperation.CLEAN_INSERT.execute(s_connection, s_initialData);

        s_cache.flush();
    }

    /**
     * Stops the service manager and closes the database connection after each test class
     */
    @AfterClass
    public static void shutdownServices() throws Exception {
        s_services.stop();
        s_temba.stop();
        s_cache.stop();
        s_connection.close();
    }

    /**
     * Executes a SQL statement
     * @param sql the SQL statement
     */
    protected void executeSql(String sql) throws Exception {
        Statement statement = s_connection.getConnection().createStatement();
        statement.execute(sql);
    }

    /**
     * Executes a SQL statement
     * @param sql the SQL statement
     */
    protected ResultSet executeQuery(String sql) throws Exception {
        Statement statement = s_connection.getConnection().createStatement();
        return statement.executeQuery(sql);
    }

    /**
     * Executes a query and returns result as a list of maps for each row
     * @param sql the SQL query
     * @return the list of maps
     */
    protected List<Map<String,Object>> queryRows(String sql) throws Exception {
        return resultSetToListOfMaps(executeQuery(sql));
    }

    /**
     * Executes a query which should only return a single row
     * @param sql the SQL query
     * @return the row as a map
     * @throws IllegalArgumentException if query returns more than one row
     */
    protected Map<String,Object> querySingle(String sql) throws Exception {
        List<Map<String,Object>> rows = queryRows(sql);
        if (rows.size() != 1) {
            throw new IllegalArgumentException("Expected single row but got " + rows.size());
        }
        return rows.get(0);
    }

    /**
     * Convenience method to fetch a single row given a table name and id
     * @param table the table name
     * @param id the row id
     * @return the row as a map
     */
    protected Map<String,Object> fetchSingleById(String table, int id) throws Exception {
        return querySingle("SELECT * FROM " + table + " WHERE id = " + id);
    }

    /**
     * Prints the named tables to std out
     * @param tableNames the table names
     */
    protected static void printTables(String... tableNames) {
        for (String tableName : tableNames) {
            System.out.println("================ " + tableName + " ================");

            QueryDataSet outputSet = new QueryDataSet(s_connection);
            try {
                outputSet.addTable(tableName);
                FlatXmlDataSet.write(outputSet, System.out);

            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }

    /**
     * Converts a result set to a list of maps. Timestamps are converted to simple dates to allow simpler date assert
     * logic
     * @param rs the result set
     * @return the list of maps
     */
    private List<Map<String, Object>> resultSetToListOfMaps(ResultSet rs) throws SQLException {
        ResultSetMetaData md = rs.getMetaData();
        int columns = md.getColumnCount();
        List<Map<String, Object>> list = new ArrayList<>();

        while (rs.next()) {
            Map<String, Object> row = new HashMap<>(columns);

            for (int i = 1; i <= columns; ++i) {
                String column = md.getColumnName(i);
                Object value = rs.getObject(i);

                if (value instanceof Timestamp) {
                    value = new Date(((Timestamp) value).getTime());
                }

                row.put(column, value);
            }
            list.add(row);
        }
        return list;
    }

    protected static Cache getCache() {
        return s_cache;
    }

    public static TembaManager getTemba() {
        return s_temba;
    }

    protected static ServiceManager getServices() {
        return s_services;
    }
}
