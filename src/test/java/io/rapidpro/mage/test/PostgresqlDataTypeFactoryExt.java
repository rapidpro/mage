package io.rapidpro.mage.test;

import org.dbunit.dataset.datatype.AbstractDataType;
import org.dbunit.dataset.datatype.DataType;
import org.dbunit.dataset.datatype.DataTypeException;
import org.dbunit.dataset.datatype.TypeCastException;
import org.dbunit.ext.postgresql.PostgresqlDataTypeFactory;
import org.junit.Ignore;
import org.postgresql.util.PGobject;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Types;

/**
 * Extension to PostgresqlDataTypeFactory to add rudimentary support for hstore columns
 */
@Ignore
public class PostgresqlDataTypeFactoryExt extends PostgresqlDataTypeFactory {

    protected static final Logger log = LoggerFactory.getLogger(PostgresqlDataTypeFactoryExt.class);

    /**
     * @see PostgresqlDataTypeFactory#createDataType(int, String)
     */
    @Override
    public DataType createDataType(int sqlType, String sqlTypeName) throws DataTypeException {
        if (sqlType == Types.OTHER && "hstore".equals(sqlTypeName)) {
            return new HstoreType();
        }

        return super.createDataType(sqlType, sqlTypeName);
    }

    /**
     * Dumb implementation of a Hstore datatype. Dataset values should be formated as foo => 'bar', etc
     */
    public static class HstoreType extends AbstractDataType {

        /**
         * Logger for this class
         */
        private static final Logger logger = LoggerFactory.getLogger(HstoreType.class);

        public HstoreType() {
            super("hstore", Types.OTHER, String.class, false);
        }

        public Object getSqlValue(int column, ResultSet resultSet) throws SQLException, TypeCastException {
            return resultSet.getString(column);
        }

        public void setSqlValue(Object value, int column, PreparedStatement statement) throws SQLException, TypeCastException {
            statement.setObject(column, getHstore(value));
        }

        public Object typeCast(Object arg) throws TypeCastException {
            return arg.toString();
        }

        private PGobject getHstore(Object value) throws TypeCastException {
            PGobject obj = new PGobject();
            obj.setType("hstore");

            try {
                obj.setValue(value.toString());
            } catch (SQLException e) {
                e.printStackTrace();
            }

            return obj;
        }
    }
}